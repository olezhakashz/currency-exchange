// Lab 07: login, registration, and the signed-in view when the connection is lost.
import 'dart:convert';

import 'package:currency_exchange/api/api_client.dart';
import 'package:currency_exchange/main.dart';
import 'package:currency_exchange/screens/wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const userJson = {'id': 3, 'email': 'ola@example.com', 'role': 'USER'};
const adminJson = {'id': 2, 'email': 'admin@example.com', 'role': 'ADMIN'};
final rates = json({'effectiveDate': '2026-11-06', 'stale': false, 'rates': [{'code': 'EUR', 'mid': 4.265}]}, 200);

/// A fake service: [online] switches the network; [routes] answers by "METHOD /path".
class FakeService {
  bool online = true;
  final calls = <String>[];
  final Map<String, http.Response Function(http.Request)> routes = {};

  void on(String key, http.Response Function(http.Request) answer) => routes[key] = answer;

  ApiClient client() => ApiClient(
      baseUrl: 'http://test',
      retryDelay: Duration.zero,
      client: MockClient((req) async {
        final key = '${req.method} ${req.url.path}';
        if (!online) throw http.ClientException('Network is unreachable');
        calls.add(key);
        final r = routes[key];
        return r == null ? json({'error': {'code': 'NOT_FOUND', 'message': key}}, 404) : r(req);
      }));
}

void main() {
  test('login stores the token and the identified user', () async {
    final s = FakeService()..on('POST /auth/login', (_) => json({'token': 'tok', 'user': userJson}, 200));
    final api = s.client();
    final u = await api.login('ola@example.com', 'secret-pass-1');
    expect(u.role, 'USER');
    expect(api.token, 'tok');
    expect(api.session.user!.email, 'ola@example.com');
  });

  test('register signs in with the account the service made', () async {
    final s = FakeService()
      ..on('POST /auth/register', (_) => json({'userId': 3, 'token': 'tok'}, 201))
      ..on('GET /me', (req) {
        expect(req.headers['Authorization'], 'Bearer tok');
        return json({...userJson, 'disabled': false, 'createdAt': 'x'}, 200);
      });
    final api = s.client();
    await api.register('ola@example.com', 'secret-pass-1');
    expect(api.session.signedIn, isTrue);
    expect(api.session.user!.id, 3);
  });

  test('no connection keeps the session; 401 from the service ends it', () async {
    final s = FakeService()
      ..on('POST /auth/login', (_) => json({'token': 'tok', 'user': userJson}, 200))
      ..on('GET /wallet', (_) => json({'error': {'code': 'TOKEN_REVOKED', 'message': 'x'}}, 401));
    final api = s.client();
    await api.login('ola@example.com', 'secret-pass-1');
    s.online = false;
    await expectLater(api.getWallet(), throwsA(isA<ApiProblem>()));
    expect(api.session.signedIn, isTrue, reason: 'offline must not sign out');
    expect(api.session.offline, isTrue);
    expect(api.token, 'tok');
    s.online = true;
    await expectLater(api.getWallet(),
        throwsA(isA<ApiProblem>().having((p) => p.kind, 'kind', ProblemKind.auth)));
    expect(api.session.signedIn, isFalse);
    expect(api.session.endedReason, 'TOKEN_REVOKED');
    expect(api.token, isNull);
  });

  test('403 FORBIDDEN is "not allowed" and keeps the session; ACCOUNT_DISABLED ends it', () async {
    final s = FakeService()
      ..on('POST /auth/login', (_) => json({'token': 'tok', 'user': userJson}, 200))
      ..on('GET /admin/users', (_) => json({'error': {'code': 'FORBIDDEN', 'message': 'x'}}, 403))
      ..on('GET /wallet', (_) => json({'error': {'code': 'ACCOUNT_DISABLED', 'message': 'x'}}, 403));
    final api = s.client();
    await api.login('ola@example.com', 'secret-pass-1');
    await expectLater(api.adminUsers(),
        throwsA(isA<ApiProblem>().having((p) => p.kind, 'kind', ProblemKind.forbidden)));
    expect(api.session.signedIn, isTrue);
    await expectLater(api.getWallet(), throwsA(isA<ApiProblem>()));
    expect(api.session.endedReason, 'ACCOUNT_DISABLED');
  });

  test('logout offline forgets the token on the phone and says the service was not told', () async {
    final s = FakeService()..on('POST /auth/login', (_) => json({'token': 'tok', 'user': userJson}, 200));
    final api = s.client();
    await api.login('ola@example.com', 'secret-pass-1');
    s.online = false;
    expect(await api.logout(), isFalse);
    expect(api.token, isNull);
    expect(api.session.endedReason, 'LOGGED_OUT_OFFLINE');
  });

  testWidgets('offline wallet shows the last confirmed balances, marked with their time', (tester) async {
    final s = FakeService()
      ..on('POST /auth/login', (_) => json({'token': 'tok', 'user': userJson}, 200))
      ..on('GET /wallet', (_) => json({'balances': {'PLN': 573.5, 'EUR': 100.0}}, 200));
    final api = s.client();
    await api.login('ola@example.com', 'secret-pass-1');
    await tester.pumpWidget(MaterialApp(home: WalletScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wallet-live')), findsOneWidget);

    s.online = false;
    await tester.tap(find.byKey(const Key('refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wallet-cached')), findsOneWidget);
    expect(find.text('Last confirmed balances'), findsOneWidget);
    expect(find.text('573.50'), findsOneWidget);
    expect(find.textContaining('Not updated: no connection'), findsOneWidget);
  });

  testWidgets('offline wallet with nothing confirmed yet shows the error, not invented zeros', (tester) async {
    final s = FakeService()..on('POST /auth/login', (_) => json({'token': 'tok', 'user': userJson}, 200));
    final api = s.client();
    await api.login('ola@example.com', 'secret-pass-1');
    s.online = false;
    await tester.pumpWidget(MaterialApp(home: WalletScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('problem-noConnection')), findsOneWidget);
    expect(find.byKey(const Key('wallet-cached')), findsNothing);
  });

  testWidgets('app: Admin tab only for admins; offline banner keeps the user signed in', (tester) async {
    final s = FakeService()
      ..on('POST /auth/login', (req) =>
          json({'token': 'tok', 'user': jsonDecode(req.body)['email'] == 'admin@example.com' ? adminJson : userJson}, 200))
      ..on('GET /rates', (_) => rates);
    final api = s.client();
    await tester.pumpWidget(CurrencyApp(api: api));
    await tester.enterText(find.byKey(const Key('password')), 'secret-pass-1');
    await tester.tap(find.byKey(const Key('login')));
    await tester.pumpAndSettle();
    expect(find.text('Rates'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);

    s.online = false;
    await tester.tap(find.byKey(const Key('refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline-banner')), findsOneWidget);
    expect(find.textContaining('Still signed in as ola@example.com'), findsOneWidget);
    expect(find.byKey(const Key('email')), findsNothing, reason: 'not sent back to login');

    s.online = true;
    await tester.tap(find.byKey(const Key('refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline-banner')), findsNothing);

    await api.logout();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-ended')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('email')), 'admin@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'admin-pass-1');
    await tester.tap(find.byKey(const Key('login')));
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('app: a 401 from the service returns to login with the reason', (tester) async {
    final s = FakeService()
      ..on('POST /auth/login', (_) => json({'token': 'tok', 'user': userJson}, 200))
      ..on('GET /rates', (_) => rates)
      ..on('GET /wallet', (_) => json({'error': {'code': 'TOKEN_EXPIRED', 'message': 'x'}}, 401));
    final api = s.client();
    await tester.pumpWidget(CurrencyApp(api: api));
    await tester.enterText(find.byKey(const Key('password')), 'secret-pass-1');
    await tester.tap(find.byKey(const Key('login')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-ended')), findsOneWidget);
    expect(find.text('Your session expired. Please log in again.'), findsOneWidget);
  });
}
