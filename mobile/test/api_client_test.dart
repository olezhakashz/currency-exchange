// ApiClient sorts every answer (or missing answer) into the right kind.
import 'dart:async';
import 'dart:convert';

import 'package:currency_exchange/api/api_client.dart';
import 'package:currency_exchange/api/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient clientWith(MockClientHandler handler, {Duration timeout = const Duration(seconds: 10)}) =>
    ApiClient(
        baseUrl: 'http://test',
        client: MockClient(handler),
        timeout: timeout,
        retryDelay: Duration.zero)
      ..token = 't';

http.Response json(Object body, int status, {Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});

OrderRequest order() => OrderRequest(
    requestId: newRequestId(), side: Side.buy, currency: 'EUR', amount: 100, seenRate: 4.265);

void main() {
  test('GET /rates success is parsed', () async {
    final api = clientWith((_) async => json({
          'effectiveDate': '2026-11-06',
          'stale': false,
          'rates': [
            {'code': 'EUR', 'mid': 4.265}
          ]
        }, 200));
    final t = await api.getRates();
    expect(t.effectiveDate, '2026-11-06');
    expect(t.rates.single.code, 'EUR');
  });

  test('400 from the service is a validation problem with field details', () async {
    final api = clientWith((_) async => json({
          'error': {
            'code': 'INVALID_AMOUNT',
            'message': 'Amount must be greater than 0.',
            'details': [
              {'field': 'amount', 'problem': 'must be > 0'}
            ]
          }
        }, 400));
    final p = await api.postOrder(order()).then<ApiProblem?>((_) => null, onError: (e) => e as ApiProblem);
    expect(p!.kind, ProblemKind.validation);
    expect(p.code, 'INVALID_AMOUNT');
    expect(p.reachedService, isTrue);
    expect(p.details.single.field, 'amount');
  });

  test('no connection is a different kind from validation, and reads are retried 3 times', () async {
    var calls = 0;
    final api = clientWith((_) async {
      calls++;
      throw http.ClientException('Connection refused');
    });
    final p = await api.getRates().then<ApiProblem?>((_) => null, onError: (e) => e as ApiProblem);
    expect(p!.kind, ProblemKind.noConnection);
    expect(p.reachedService, isFalse);
    expect(calls, 3);
  });

  test('an order is never retried automatically', () async {
    var calls = 0;
    final api = clientWith((_) async {
      calls++;
      throw http.ClientException('Network is unreachable');
    });
    await expectLater(api.postOrder(order()), throwsA(isA<ApiProblem>()));
    expect(calls, 1);
  });

  test('a slow service gives a timeout problem', () async {
    final api = clientWith((_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 50));
    final p = await api.postOrder(order()).then<ApiProblem?>((_) => null, onError: (e) => e as ApiProblem);
    expect(p!.kind, ProblemKind.timeout);
  });

  test('409 REJECTED is an order result, not an error; replay header is read', () async {
    final api = clientWith((_) async => json(
        {'requestId': 'x', 'status': 'REJECTED', 'reason': 'RATE_CHANGED', 'currentRate': 4.271}, 409,
        headers: {'idempotent-replayed': 'true'}));
    final r = await api.postOrder(order());
    expect(r.status, 'REJECTED');
    expect(r.reason, 'RATE_CHANGED');
    expect(r.currentRate, 4.271);
    expect(r.replayed, isTrue);
  });

  test('409 REQUEST_ID_REUSED (error body) is a conflict problem', () async {
    final api = clientWith((_) async =>
        json({'error': {'code': 'REQUEST_ID_REUSED', 'message': 'x'}}, 409));
    await expectLater(api.postOrder(order()),
        throwsA(isA<ApiProblem>().having((p) => p.kind, 'kind', ProblemKind.conflict)));
  });

  test('GET /orders/{id} 404 NOT_FOUND is a normal answer', () async {
    final api = clientWith((_) async => json({'requestId': 'x', 'status': 'NOT_FOUND'}, 404));
    expect((await api.getOrderStatus('x')).status, 'NOT_FOUND');
  });

  test('token is sent as a Bearer header', () async {
    String? auth;
    final api = clientWith((req) async {
      auth = req.headers['Authorization'];
      return json({'balances': {'PLN': 1000.0}}, 200);
    });
    await api.getWallet();
    expect(auth, 'Bearer t');
  });

  test('requestId is a UUID v4', () {
    expect(newRequestId(),
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });
}
