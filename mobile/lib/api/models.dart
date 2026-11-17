// Data the app exchanges with the web service (shapes from docs/api.md).
import 'dart:math';

class Rate {
  const Rate(this.code, this.mid);
  final String code;
  final num mid;
}

class RatesTable {
  const RatesTable(this.effectiveDate, this.stale, this.rates);
  final String effectiveDate;
  final bool stale;
  final List<Rate> rates;

  factory RatesTable.fromJson(Map<String, dynamic> j) => RatesTable(
        j['effectiveDate'] as String,
        j['stale'] as bool? ?? false,
        [
          for (final r in j['rates'] as List)
            Rate((r as Map)['code'] as String, r['mid'] as num),
        ],
      );
}

class Wallet {
  const Wallet(this.balances);
  final Map<String, num> balances;

  factory Wallet.fromJson(Map<String, dynamic> j) =>
      Wallet(Map<String, num>.from(j['balances'] as Map));
}

enum Side { buy, sell }

class OrderRequest {
  OrderRequest({
    required this.requestId,
    required this.side,
    required this.currency,
    required this.amount,
    required this.seenRate,
  });

  final String requestId;
  final Side side;
  final String currency;
  final num amount;
  final num seenRate;

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'side': side == Side.buy ? 'BUY' : 'SELL',
        'currency': currency,
        'amount': amount,
        'seenRate': seenRate,
      };

  /// Same order content (used to decide whether a requestId can be reused).
  bool sameContentAs(OrderRequest o) =>
      side == o.side &&
      currency == o.currency &&
      amount == o.amount &&
      seenRate == o.seenRate;
}

class OrderResult {
  OrderResult(this.status, this.raw, {this.replayed = false});

  /// CONFIRMED, REJECTED or NOT_FOUND.
  final String status;
  final Map<String, dynamic> raw;
  final bool replayed;

  String? get reason => raw['reason'] as String?;
  num? get currentRate => raw['currentRate'] as num?;
  num? get plnAmount => raw['plnAmount'] as num?;
  num? get rateUsed => raw['rateUsed'] as num?;
  Map<String, num> get balances =>
      Map<String, num>.from((raw['balances'] as Map?) ?? const {});
  Map<String, num> get needed =>
      Map<String, num>.from((raw['needed'] as Map?) ?? const {});
  Map<String, num> get available =>
      Map<String, num>.from((raw['available'] as Map?) ?? const {});

  factory OrderResult.fromJson(Map<String, dynamic> j, {bool replayed = false}) =>
      OrderResult(j['status'] as String, j, replayed: replayed);
}

/// Random UUID v4, made on the phone, so a repeated order is recognised.
String newRequestId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

String money(num v) => v.toStringAsFixed(2);
