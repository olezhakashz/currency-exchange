#!/usr/bin/env bash
# End-to-end demo: service + database together.
# Start the server first (see backend/README.md), then from backend/:
#   bash demo.sh                # or: bash demo.sh | tee ../docs/lab05-demo-output.txt
# Needs curl and python (only to pretty-print JSON). Works in Git Bash on Windows.
set -euo pipefail
cd "$(dirname "$0")"

BASE=${BASE_URL:-http://127.0.0.1:8000}
PY=${PYTHON:-python}
command -v "$PY" >/dev/null 2>&1 || PY=python3
PASS=$(grep -E '^DEMO_PASSWORD=' .env | cut -d= -f2-)
DB=$(grep -E '^DATABASE_PATH=' .env | cut -d= -f2- || true); DB=${DB:-data/exchange.db}

call() {  # call METHOD PATH [JSON] [TOKEN]
  local method=$1 path=$2 data=${3:-} token=${4:-}
  echo "\$ $method $path ${data:+$data}"
  local args=(-s -X "$method" "$BASE$path" -H "Content-Type: application/json" -w $'\n%{http_code}')
  [[ -n $data ]] && args+=(-d "$data")
  [[ -n $token ]] && args+=(-H "Authorization: Bearer $token")
  local out; out=$(curl "${args[@]}")
  echo "HTTP ${out##*$'\n'}"
  echo "${out%$'\n'*}" | "$PY" -m json.tool
  echo
}

sql() {
  echo "\$ sqlite> $1"
  "$PY" - "$DB" "$1" <<'EOF'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
cur = conn.execute(sys.argv[2])
print(" | ".join(d[0] for d in cur.description))
for row in cur:
    print(" | ".join(str(v) for v in row))
EOF
  echo
}

uuid() { "$PY" -c 'import uuid; print(uuid.uuid4())'; }

echo "=== 0. Health check (service can reach the database) ==="
call GET /health

echo "=== 1. READ: rates stored in the database ==="
call GET /rates

echo "=== 2. Log in as the seeded demo user ==="
TOKEN=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"demo@example.com\",\"password\":\"$PASS\"}" | "$PY" -c 'import sys,json; print(json.load(sys.stdin)["token"])')
echo "token received (${#TOKEN} characters, not printed)"; echo

echo "=== 3. READ: wallet before the order ==="
call GET /wallet "" "$TOKEN"

RID=$(uuid)
EUR=$(curl -s "$BASE/rates" | "$PY" -c 'import sys,json; print([r["mid"] for r in json.load(sys.stdin)["rates"] if r["code"]=="EUR"][0])')
echo "=== 4. WRITE: buy 100 EUR at the rate the user saw ($EUR) ==="
call POST /orders "{\"requestId\":\"$RID\",\"side\":\"BUY\",\"currency\":\"EUR\",\"amount\":100.00,\"seenRate\":$EUR}" "$TOKEN"

echo "=== 5. READ: the committed change is stored ==="
call GET /wallet "" "$TOKEN"
call GET "/orders/$RID" "" "$TOKEN"
sql "SELECT request_id, side, currency, amount_minor, rate_used_e4, pln_minor, status FROM orders"
sql "SELECT u.email, b.currency, b.amount_minor FROM balances b JOIN users u ON u.id = b.user_id ORDER BY u.email, b.currency"

echo "=== 6. Same requestId again (lost reply, phone retries): runs once ==="
call POST /orders "{\"requestId\":\"$RID\",\"side\":\"BUY\",\"currency\":\"EUR\",\"amount\":100.00,\"seenRate\":$EUR}" "$TOKEN"
sql "SELECT COUNT(*) AS orders_with_this_id FROM orders WHERE request_id = '$RID'"

echo "=== 7. Bad input: 400/401 with an error code the app can switch on (nothing is stored) ==="
call POST /orders "{\"requestId\":\"$(uuid)\",\"side\":\"BUY\",\"currency\":\"EUR\",\"amount\":-5,\"seenRate\":$EUR}" "$TOKEN"
call POST /orders "{\"requestId\":\"$(uuid)\",\"side\":\"BUY\",\"currency\":\"XYZ\",\"amount\":10,\"seenRate\":1.0}" "$TOKEN"
call POST /orders "{\"side\":\"HOLD\",\"amount\":\"lots\"}" "$TOKEN"
call GET /wallet "" "not-a-real-token"

echo "=== 8. Valid input but the order is refused: 409, saved as REJECTED ==="
call POST /orders "{\"requestId\":\"$(uuid)\",\"side\":\"BUY\",\"currency\":\"EUR\",\"amount\":10,\"seenRate\":4.0000}" "$TOKEN"
call POST /orders "{\"requestId\":\"$(uuid)\",\"side\":\"BUY\",\"currency\":\"EUR\",\"amount\":900,\"seenRate\":$EUR}" "$TOKEN"

echo "=== 9. Status of an order the server never received ==="
call GET "/orders/$(uuid)" "" "$TOKEN"

echo "=== 10. Final database state ==="
sql "SELECT status, reason, COUNT(*) AS n FROM orders GROUP BY status, reason"
call GET /wallet "" "$TOKEN"
