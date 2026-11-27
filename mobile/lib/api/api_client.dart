// ApiClient: the only place in the app that talks HTTP to the web service.
//
// Every call either returns a value or throws an [ApiProblem]. The screens
// switch on [ApiProblem.kind], so they can tell apart:
//   - validation  : the service answered 400 (the input is wrong, nothing saved)
//   - noConnection: no answer at all (offline, wrong address, server down)
//   - timeout     : no answer within 10 s (for an order: result unknown)
//   - auth     : 401, or 403 ACCOUNT_DISABLED: the session is over (Lab 07)
//   - forbidden: 403 FORBIDDEN: signed in, but this caller may not do that
//   - conflict, server: the service answered with another error
//
// Lab 07: the client keeps the [Session]. Any HTTP answer marks the service
// reachable; no answer marks it unreachable but keeps the user signed in.
// Only an auth answer to a request that carried the token ends the session.
//
// An order that the service refused (409 RATE_CHANGED / INSUFFICIENT_FUNDS)
// is NOT an exception: it is a normal [OrderResult] with status REJECTED.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'session.dart';

enum ProblemKind { validation, noConnection, timeout, auth, forbidden, conflict, server }

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
    Session? session,
  })  : _http = client ?? http.Client(),
        session = session ?? Session();

  String baseUrl;
  final Duration timeout;
  final int readAttempts;
  final Duration retryDelay;
  final http.Client _http;
  final Session session;
  String? token;

  /// Sent as X-Client so the service log shows which client made a request.
  static final String clientName =
      'currency-exchange-mobile/0.7.0 (${kIsWeb ? 'web' : defaultTargetPlatform.name})';

  // ---------- endpoints ----------

  Future<UserAccount> login(String email, String password) async {
    final res = await _send('POST', '/auth/login',
        body: {'email': email, 'password': password});
    final body = _json(res) as Map<String, dynamic>;
    token = body['token'] as String;
    final user = UserAccount.fromJson(body['user'] as Map<String, dynamic>);
    session.start(user);
    return user;
  }

  /// Creates the account (role USER, chosen by the service) and signs in.
  Future<UserAccount> register(String email, String password) async {
    final res = await _send('POST', '/auth/register',
        body: {'email': email, 'password': password}, okStatuses: const {201});
    token = (_json(res) as Map<String, dynamic>)['token'] as String;
    final user = await getMe();
    session.start(user);
    return user;
  }

  Future<UserAccount> getMe() async {
    final res = await _read('/me', auth: true);
    return UserAccount.fromJson(_json(res) as Map<String, dynamic>);
  }

  /// Ends the session on the service (all tokens of this user stop working)
  /// and on the phone. Returns false when the service could not be told
  /// (no connection): the phone forgets the token anyway.
  Future<bool> logout() async {
    var told = true;
    try {
      await _send('POST', '/auth/logout', auth: true);
    } on ApiProblem catch (p) {
      // Any answer (even 401: already ended) means the service knows.
      told = p.reachedService;
    }
    token = null;
    session.end(told ? 'LOGGED_OUT' : 'LOGGED_OUT_OFFLINE');
    return told;
  }

  /// The caller's own orders, newest first (GET /orders).
  Future<List<OrderResult>> getOrders() async {
    final res = await _read('/orders', auth: true);
    return [
      for (final o in (_json(res) as Map<String, dynamic>)['orders'] as List)
        OrderResult.fromJson(o as Map<String, dynamic>),
    ];
  }

  // ---------- administration (the service refuses these for non-admins) ----------

  Future<List<UserAccount>> adminUsers() async {
    final res = await _read('/admin/users', auth: true);
    return [
      for (final u in (_json(res) as Map<String, dynamic>)['users'] as List)
        UserAccount.fromJson(u as Map<String, dynamic>),
    ];
  }

  Future<UserAccount> adminSetDisabled(int userId, bool disabled) async {
    final res = await _send('POST', '/admin/users/$userId/${disabled ? 'disable' : 'enable'}', auth: true);
    return UserAccount.fromJson(_json(res) as Map<String, dynamic>);
  }

  Future<RatesTable> getRates() async {
    final res = await _read('/rates');
    return RatesTable.fromJson(_json(res) as Map<String, dynamic>);
  }

  Future<Wallet> getWallet() async {
    final res = await _read('/wallet', auth: true);
    final w = Wallet.fromJson(_json(res) as Map<String, dynamic>);
    session.walletConfirmed(w);
    return w;
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
      session.unreachable();
      throw ApiProblem(ProblemKind.timeout, 'TIMEOUT',
          'The service did not answer within ${timeout.inSeconds} s.');
    } on http.ClientException catch (e) {
      // Socket errors on Android/iOS and fetch errors on web all end up here.
      session.unreachable();
      throw ApiProblem(ProblemKind.noConnection, 'NO_CONNECTION',
          'Could not reach the service at $baseUrl (${e.message}).');
    }

    session.reachable();
    if (okStatuses.contains(res.statusCode)) return res;
    final problem = _problemFrom(res, _tryJson(res));
    // The service says this token is no good: the session is over.
    if (auth && problem.kind == ProblemKind.auth) {
      token = null;
      session.end(problem.code);
    }
    throw problem;
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
      403 when code == 'ACCOUNT_DISABLED' => ProblemKind.auth,
      403 => ProblemKind.forbidden,
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
