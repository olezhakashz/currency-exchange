#!/usr/bin/env bash
# Lab 07 demo: registration, login and authorisation, valid and rejected paths.
# Start the server first (python seed.py --reset; uvicorn ...), then from backend/:
#   bash demo_auth.sh | tee ../docs/lab07-demo-output.txt
# Needs curl and python. Uses DEMO_PASSWORD and ADMIN_PASSWORD from .env.
# All calls go straight to the service with curl: there is no app and no
# hidden button, so every refusal below comes from the service itself.
set -euo pipefail
cd "$(dirname "$0")"

BASE=${BASE_URL:-http://127.0.0.1:8000}
PY=${PYTHON:-python}
command -v "$PY" >/dev/null 2>&1 || PY=python3
env_value() { grep -E "^$1=" .env | cut -d= -f2- || true; }
DEMO_PASS=$(env_value DEMO_PASSWORD); ADMIN_PASS=$(env_value ADMIN_PASSWORD)
DB=$(env_value DATABASE_PATH); DB=${DB:-data/exchange.db}

call() {  # call METHOD PATH [JSON] [TOKEN]
  local method=$1 path=$2 data=${3:-} token=${4:-}
  echo "\$ $method $path ${data:+$data}${token:+  [token of $WHO]}"
  local args=(-s -X "$method" "$BASE$path" -H "Content-Type: application/json" -H "X-Client: demo_auth.sh" -w $'\n%{http_code}')
  [[ -n $data ]] && args+=(-d "$data")
  [[ -n $token ]] && args+=(-H "Authorization: Bearer $token")
  local out; out=$(curl "${args[@]}")
  echo "HTTP ${out##*$'\n'}"
  # Tokens are not printed; only their length.
  echo "${out%$'\n'*}" | "$PY" -c 'import sys,json; b=json.load(sys.stdin)
if isinstance(b, dict) and "token" in b: b["token"] = "<%d characters, not printed>" % len(b["token"])
print(json.dumps(b, indent=4))'
  echo
}
as() { WHO=$1; }   # label for the output only

sql() {
  echo "\$ sqlite> $1"
  "$PY" - "$DB" "$1" <<'PYEOF'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
cur = conn.execute(sys.argv[2])
print(" | ".join(d[0] for d in cur.description))
for row in cur:
    print(" | ".join(str(v) for v in row))
PYEOF
  echo
}

token_of() {  # token_of EMAIL PASSWORD
  curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" -H "X-Client: demo_auth.sh" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | "$PY" -c 'import sys,json; print(json.load(sys.stdin)["token"])'
}
field() { "$PY" -c "import sys,json; print(json.load(sys.stdin)$1)"; }
uuid() { "$PY" -c 'import uuid; print(uuid.uuid4())'; }
EUR=$(curl -s -H "X-Client: demo_auth.sh" "$BASE/rates" | "$PY" -c 'import sys,json; print([r["mid"] for r in json.load(sys.stdin)["rates"] if r["code"]=="EUR"][0])')

echo "##########  VALID ACCESS PATHS  ##########"; echo
echo "=== V1. Rates are public and read-only: no token needed ==="
call GET /rates

echo "=== V2. Register a new user (role is always USER) ==="
EMAIL="ola.$(date +%s)@example.com"
call POST /auth/register "{\"email\":\"$EMAIL\",\"password\":\"ola-secret-1\"}"
OLA=$(token_of "$EMAIL" ola-secret-1)
OLA_ID=$(curl -s "$BASE/me" -H "X-Client: demo_auth.sh" -H "Authorization: Bearer $OLA" | field '["id"]')

echo "=== V3. Log in: the answer names the identified caller ==="
echo "\$ POST /auth/login {\"email\":\"$EMAIL\",\"password\":\"ola-secret-1\"}"; echo "HTTP 200"
curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" -H "X-Client: demo_auth.sh" -d "{\"email\":\"$EMAIL\",\"password\":\"ola-secret-1\"}" \
  | "$PY" -c 'import sys,json; b=json.load(sys.stdin); b["token"]="<%d characters, not printed>" % len(b["token"]); print(json.dumps(b, indent=4))'
echo

as ola
echo "=== V4. Own account, wallet and orders (the id comes from the token) ==="
call GET /me "" "$OLA"
call GET /wallet "" "$OLA"
call GET "/users/$OLA_ID/wallet" "" "$OLA"

echo "=== V5. Data-changing operation on the own wallet ==="
RID=$(uuid)
call POST /orders "{\"requestId\":\"$RID\",\"side\":\"BUY\",\"currency\":\"EUR\",\"amount\":10.00,\"seenRate\":$EUR}" "$OLA"
call GET /orders "" "$OLA"

as demo
DEMO=$(token_of demo@example.com "$DEMO_PASS")
DEMO_ID=$(curl -s "$BASE/me" -H "X-Client: demo_auth.sh" -H "Authorization: Bearer $DEMO" | field '["id"]')

as admin
ADMIN=$(token_of admin@example.com "$ADMIN_PASS")
echo "=== V6. Admin: list users, read another user's wallet ==="
call GET /admin/users "" "$ADMIN"
call GET "/users/$OLA_ID/wallet" "" "$ADMIN"

echo "##########  REJECTED ACCESS PATHS  ##########"; echo
as nobody
echo "=== R1. No token: wallet and order refused (401) ==="
call GET /wallet
call POST /orders "{\"requestId\":\"$(uuid)\",\"side\":\"BUY\",\"currency\":\"EUR\",\"amount\":10,\"seenRate\":$EUR}"

echo "=== R2. Edited token: user id changed to the demo user, signature kept (401) ==="
EDITED="$DEMO_ID.${OLA#*.}"
as "ola, edited to user $DEMO_ID"
call GET /wallet "" "$EDITED"

as ola
echo "=== R3. Ola asks for the demo user's account and wallet by id (403) ==="
call GET "/users/$DEMO_ID" "" "$OLA"
call GET "/users/$DEMO_ID/wallet" "" "$OLA"

echo "=== R4. Ola tries to put the order on another wallet (unknown field, 400) ==="
call POST /orders "{\"requestId\":\"$(uuid)\",\"userId\":$DEMO_ID,\"side\":\"BUY\",\"currency\":\"EUR\",\"amount\":10,\"seenRate\":$EUR}" "$OLA"

echo "=== R5. Demo user asks for Ola's order by its requestId (looks like it doesn't exist, 404) ==="
as demo
call GET "/orders/$RID" "" "$DEMO"

echo "=== R6. Registration cannot pick the ADMIN role (400) ==="
call POST /auth/register "{\"email\":\"eve.$(date +%s)@example.com\",\"password\":\"eve-secret-1\",\"role\":\"ADMIN\"}"

as ola
echo "=== R7. Normal user calls admin functions directly (403; nothing changes) ==="
call GET /admin/users "" "$OLA"
call PUT /admin/rates/EUR "{\"mid\":1.0000}" "$OLA"
call POST "/admin/users/$DEMO_ID/disable" "" "$OLA"
sql "SELECT currency, mid_e4 FROM rates WHERE currency = 'EUR'"

echo "=== R8. Wrong password (401) ==="
call POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"wrong-password\"}"

echo "=== R9. Logout ends the session: the same token is refused (401 TOKEN_REVOKED) ==="
call POST /auth/logout "" "$OLA"
call GET /wallet "" "$OLA"
OLA=$(token_of "$EMAIL" ola-secret-1)

as admin
echo "=== R10. Admin disables Ola: her valid token and her login are refused (403) ==="
call POST "/admin/users/$OLA_ID/disable" "" "$ADMIN"
as ola
call POST /orders "{\"requestId\":\"$(uuid)\",\"side\":\"BUY\",\"currency\":\"EUR\",\"amount\":10,\"seenRate\":$EUR}" "$OLA"
call POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"ola-secret-1\"}"
as admin
call POST "/admin/users/$OLA_ID/enable" "" "$ADMIN"
call GET /admin/actions "" "$ADMIN"

echo "=== Database: users, orders per user, admin actions ==="
sql "SELECT id, email, role, disabled, token_version FROM users ORDER BY id"
sql "SELECT u.email, o.side, o.currency, o.amount_minor, o.status FROM orders o JOIN users u ON u.id = o.user_id ORDER BY o.created_at"
sql "SELECT a.id, u.email AS admin, a.action, a.target, a.created_at FROM admin_actions a JOIN users u ON u.id = a.admin_id ORDER BY a.id"
