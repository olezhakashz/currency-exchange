// The order screen shows the right state for each kind of answer.
import 'dart:async';
import 'dart:convert';

import 'package:currency_exchange/api/api_client.dart';
import 'package:currency_exchange/api/models.dart';
import 'package:currency_exchange/screens/order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<void> pumpOrder(WidgetTester tester, MockClientHandler handler) async {
  final api = ApiClient(baseUrl: 'http://test', client: MockClient(handler), retryDelay: Duration.zero)
    ..token = 't';
  await tester.pumpWidget(MaterialApp(home: OrderScreen(api: api, rate: const Rate('EUR', 4.265))));
}

void main() {
  testWidgets('tap -> sending -> confirmed by the service', (tester) async {
    final reply = Completer<http.Response>();
    await pumpOrder(tester, (req) => reply.future);
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(find.text('Sending order...'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed, isNull);

    reply.complete(json({
      'requestId': '6f1c2a8e-3b4d-4c55-9a1e-2f7b8d0c1e42',
      'status': 'CONFIRMED',
      'side': 'BUY',
      'currency': 'EUR',
      'amount': 100.0,
      'rateUsed': 4.265,
      'plnAmount': 426.5,
      'balances': {'PLN': 573.5, 'EUR': 100.0}
    }, 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('outcome-confirmed')), findsOneWidget);
    expect(find.textContaining('PLN 573.50'), findsOneWidget);
  });

  testWidgets('400 shows a validation state under the amount field', (tester) async {
    await pumpOrder(tester, (req) async => json({
          'error': {
            'code': 'INVALID_AMOUNT',
            'message': 'Amount must be greater than 0.',
            'details': [
              {'field': 'amount', 'problem': 'must be > 0'}
            ]
          }
        }, 400));
    await tester.enterText(find.byKey(const Key('amount')), '-5');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('outcome-invalid')), findsOneWidget);
    expect(find.text('must be > 0'), findsOneWidget);
    expect(find.byKey(const Key('outcome-unknown')), findsNothing);
  });

  testWidgets('no connection shows "result not known" and checks status, not "failed"', (tester) async {
    var posts = 0;
    var gets = 0;
    await pumpOrder(tester, (req) async {
      if (req.method == 'POST') posts++;
      if (req.method == 'GET') gets++;
      throw http.ClientException('Connection refused');
    });
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('outcome-unknown')), findsOneWidget);
    expect(find.textContaining('No connection to the service'), findsOneWidget);
    expect(find.byKey(const Key('outcome-invalid')), findsNothing);
    expect(posts, 1);
    expect(gets, 3); // automatic status check, retried like every read
  });
}
