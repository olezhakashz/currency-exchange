// ApiClient: the only place in the app that talks HTTP to the web service.
//
// Every call either returns a value or throws an [ApiProblem]. The screens
// switch on [ApiProblem.kind], so they can tell apart:
//   - validation  : the service answered 400 (the input is wrong, nothing saved)
//   - noConnection: no answer at all (offline, wrong address, server down)
//   - timeout     : no answer within 10 s (for an order: result unknown)
//   - auth, conflict, server: the service answered with another error
//
// An order that the service refused (409 RATE_CHANGED / INSUFFICIENT_FUNDS)
// is NOT an exception: it is a normal [OrderResult] with status REJECTED.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

import 'models.dart';

enum ProblemKind { validation, noConnection, timeout, auth, conflict, server }

class FieldProblem {
  const FieldProblem(this.field, this.problem);
  final String field;
  final String problem;
}

class ApiProblem implements Exception {
  const ApiProblem(this.kind, this.code, this.message,
      {this.details = const [], this.httpStatus});

  final ProblemKind kind;

  /// Stable code from the service (docs/api.md), or NO_CONNECTION / TIMEOUT
  /// when the service never answered.
  final String code;
  final String message;
  final List<FieldProblem> details;
  final int? httpStatus;

  /// True when the service answered. False means we got no HTTP response.
  bool get reachedService => httpStatus != null;

  @override
  String toString() => 'ApiProblem($kind, $code, $message)';
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.readAttempts = 3,
    this.retryDelay = const Duration(seconds: 1),
  }) : _http = client ?? http.Client();

  String baseUrl;
  final Duration timeout;
  final int readAttempts;
  final Duration retryDelay;
  final http.Client _http;
  String? token;

  /// Sent as X-Client so the service log shows which client made a request.
  static final String clientName =
      'currency-exchange-mobile/0.6.0 (${kIsWeb ? 'web' : defaultTargetPlatform.name})';

  // ---------- endpoints ----------

  Future<String> login(String email, String password) async {
    final res = await _send('POST', '/auth/login',
        body: {'email': email, 'password': password});
    token = (_json(res) as Map<String, dynamic>)['token'] as String;
    return token!;
  }

  Future<RatesTable> getRates() async {
    final res = await _read('/rates');
    return RatesTable.fromJson(_json(res) as Map<String, dynamic>);
  }

  Future<Wallet> getWallet() async {
    final res = await _read('/wallet', auth: true);
    return Wallet.fromJson(_json(res) as Map<String, dynamic>);
  }

  /// Sends one buy/sell order. Never retried automatically: if no answer
  /// comes back, the caller asks [getOrderStatus] with the same requestId.
  Future<OrderResult> postOrder(OrderRequest order) async {
    final res = await _send('POST', '/orders',
        body: order.toJson(), auth: true, okStatuses: const {200, 409});
    final body = _json(res) as Map<String, dynamic>;
    // 409 is either a saved REJECTED order or an error such as REQUEST_ID_REUSED.
    if (body['status'] is! String) throw _problemFrom(res, body);
    return OrderResult.fromJson(body,
        replayed: res.headers['idempotent-replayed'] == 'true');
  }

  /// CONFIRMED / REJECTED (saved answer) or NOT_FOUND (never arrived).
  Future<OrderResult> getOrderStatus(String requestId) async {
    final res = await _read('/orders/$requestId',
        auth: true, okStatuses: const {200, 404});
    final body = _json(res) as Map<String, dynamic>;
    if (res.statusCode == 404 && body['status'] != 'NOT_FOUND') {
      throw _problemFrom(res, body);
    }
    return OrderResult.fromJson(body);
  }

  // ---------- plumbing ----------

  /// GET with up to [readAttempts] tries when there is no connection.
  /// Reads change nothing, so repeating them is safe (scenario S6).
  Future<http.Response> _read(String path,
      {bool auth = false, Set<int> okStatuses = const {200}}) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await _send('GET', path, auth: auth, okStatuses: okStatuses);
      } on ApiProblem catch (p) {
        if (p.kind != ProblemKind.noConnection || attempt >= readAttempts) {
          rethrow;
        }
        await Future<void>.delayed(retryDelay * attempt);
      }
    }
  }

  Future<http.Response> _send(String method, String path,
      {Object? body, bool auth = false, Set<int> okStatuses = const {200}}) async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
    final headers = <String, String>{'Accept': 'application/json', 'X-Client': clientName};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (auth && token != null) headers['Authorization'] = 'Bearer $token';

    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _http.send(req).timeout(timeout);
      res = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiProblem(ProblemKind.timeout, 'TIMEOUT',
          'The service did not answer within ${timeout.inSeconds} s.');
    } on http.ClientException catch (e) {
      // Socket errors on Android/iOS and fetch errors on web all end up here.
      throw ApiProblem(ProblemKind.noConnection, 'NO_CONNECTION',
          'Could not reach the service at $baseUrl (${e.message}).');
    }

    if (okStatuses.contains(res.statusCode)) return res;
    throw _problemFrom(res, _tryJson(res));
  }

  ApiProblem _problemFrom(http.Response res, Object? body) {
    final err = (body is Map<String, dynamic> && body['error'] is Map)
        ? body['error'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final code = (err['code'] as String?) ?? 'HTTP_${res.statusCode}';
    final message = (err['message'] as String?) ?? 'HTTP ${res.statusCode}';
    final details = [
      for (final d in (err['details'] as List?) ?? const [])
        FieldProblem('${(d as Map)['field']}', '${d['problem']}'),
    ];
    final kind = switch (res.statusCode) {
      400 => ProblemKind.validation,
      401 => ProblemKind.auth,
      409 => ProblemKind.conflict,
      _ => ProblemKind.server,
    };
    return ApiProblem(kind, code, message,
        details: details, httpStatus: res.statusCode);
  }

  Object? _json(http.Response res) => jsonDecode(utf8.decode(res.bodyBytes));

  Object? _tryJson(http.Response res) {
    try {
      return _json(res);
    } on FormatException {
      return null;
    }
  }
}
