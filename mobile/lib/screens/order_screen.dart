// DATA-CHANGING path: POST /orders (buy or sell), then GET /orders/{id}
// when the answer is lost.
//
// A tap only *asks* for the order. The screen shows "Confirmed" only when the
// service says CONFIRMED. The states:
//   editing   -> form, button enabled
//   sending   -> spinner, button disabled (no double tap, scenario S13)
//   confirmed -> service confirmed; shows the stored balances it returned
//   rejected  -> service refused (RATE_CHANGED / INSUFFICIENT_FUNDS), saved as REJECTED
//   invalid   -> service answered 400: input is wrong, nothing saved
//   unknown   -> no answer (no connection / timeout): result not known yet
//   checking  -> asking GET /orders/{id} for the real result (scenario S2/S3)
//   notFound  -> the order never reached the service; safe to send again
//   failed    -> other error (login expired, server error)
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../widgets/status_views.dart';

enum OrderPhase { editing, sending, confirmed, rejected, invalid, unknown, checking, notFound, failed }

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.api, required this.rate});
  final ApiClient api;
  final Rate rate;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final _amount = TextEditingController(text: '100.00');
  late num _seenRate = widget.rate.mid;
  Side _side = Side.buy;
  OrderPhase _phase = OrderPhase.editing;
  OrderRequest? _sent; // last order sent; kept so a retry reuses its requestId
  OrderResult? _result;
  ApiProblem? _problem;
  String? _localError;

  String get _code => widget.rate.code;
  bool get _busy => _phase == OrderPhase.sending || _phase == OrderPhase.checking;
  bool get _finished => _phase == OrderPhase.confirmed || _phase == OrderPhase.rejected;

  Future<void> _submit() async {
    final amount = num.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (amount == null) {
      setState(() => _localError = 'Enter a number, for example 100.00');
      return;
    }
    final draft = OrderRequest(
        requestId: newRequestId(), side: _side, currency: _code, amount: amount, seenRate: _seenRate);
    // After a lost answer, the same order keeps its requestId, so the service
    // runs it at most once even if the first one did arrive (S7).
    final retry = _sent != null &&
        (_phase == OrderPhase.unknown || _phase == OrderPhase.notFound) &&
        _sent!.sameContentAs(draft);
    final order = retry
        ? OrderRequest(
            requestId: _sent!.requestId, side: _side, currency: _code, amount: amount, seenRate: _seenRate)
        : draft;

    setState(() {
      _localError = null;
      _problem = null;
      _result = null;
      _sent = order;
      _phase = OrderPhase.sending;
    });
    try {
      final r = await widget.api.postOrder(order);
      _show(r);
    } on ApiProblem catch (p) {
      if (!mounted) return;
      if (p.kind == ProblemKind.noConnection || p.kind == ProblemKind.timeout) {
        setState(() {
          _problem = p;
          _phase = OrderPhase.unknown;
        });
        await _checkStatus(); // one automatic check; the user can check again
      } else {
        setState(() {
          _problem = p;
          _phase = p.kind == ProblemKind.validation ? OrderPhase.invalid : OrderPhase.failed;
        });
      }
    }
  }

  Future<void> _checkStatus() async {
    final sent = _sent;
    if (sent == null) return;
    setState(() => _phase = OrderPhase.checking);
    try {
      final r = await widget.api.getOrderStatus(sent.requestId);
      _show(r);
    } on ApiProblem catch (p) {
      if (mounted) {
        setState(() {
          _problem = p;
          _phase = OrderPhase.unknown;
        });
      }
    }
  }

  void _show(OrderResult r) {
    if (!mounted) return;
    setState(() {
      _result = r;
      _problem = null;
      _phase = switch (r.status) {
        'CONFIRMED' => OrderPhase.confirmed,
        'REJECTED' => OrderPhase.rejected,
        _ => OrderPhase.notFound,
      };
    });
  }

  void _newOrder({num? rate}) => setState(() {
        if (rate != null) _seenRate = rate;
        _sent = null;
        _result = null;
        _problem = null;
        _phase = OrderPhase.editing;
      });

  String? _amountError() {
    if (_localError != null) return _localError;
    final p = _problem;
    if (_phase != OrderPhase.invalid || p == null) return null;
    final d = p.details.where((d) => d.field == 'amount').toList();
    if (d.isNotEmpty) return d.first.problem;
    return p.code == 'INVALID_AMOUNT' ? p.message : null;
  }

  @override
  Widget build(BuildContext context) {
    final amount = num.tryParse(_amount.text.trim().replaceAll(',', '.'));
    final verb = _side == Side.buy ? 'Buy' : 'Sell';
    return Scaffold(
      appBar: AppBar(title: Text('$verb $_code')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        SegmentedButton<Side>(
          segments: const [
            ButtonSegment(value: Side.buy, label: Text('Buy'), icon: Icon(Icons.add)),
            ButtonSegment(value: Side.sell, label: Text('Sell'), icon: Icon(Icons.remove)),
          ],
          selected: {_side},
          onSelectionChanged: _busy || _finished ? null : (s) => setState(() => _side = s.first),
        ),
        const SizedBox(height: 16),
        Text('Rate you see: 1 $_code = ${_seenRate.toStringAsFixed(4)} PLN',
            key: const Key('seen-rate')),
        const SizedBox(height: 12),
        TextField(
          key: const Key('amount'),
          controller: _amount,
          enabled: !_busy && !_finished,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() => _localError = null),
          decoration: InputDecoration(
            labelText: 'Amount in $_code',
            border: const OutlineInputBorder(),
            errorText: _amountError(),
            helperText: amount == null ? null : 'About ${money(amount * _seenRate)} PLN',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('submit'),
          onPressed: _busy || _finished ? null : _submit,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _phase == OrderPhase.sending
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Sending order...'),
                  ])
                : Text(_phase == OrderPhase.unknown || _phase == OrderPhase.notFound
                    ? 'Send the same order again'
                    : '$verb ${_amount.text} $_code'),
          ),
        ),
        const SizedBox(height: 20),
        _outcome(context),
      ]),
    );
  }

  Widget _outcome(BuildContext context) {
    final r = _result;
    final p = _problem;
    switch (_phase) {
      case OrderPhase.editing:
      case OrderPhase.sending:
        return const SizedBox.shrink();
      case OrderPhase.checking:
        return const _Banner(
            key: Key('outcome-checking'),
            icon: Icons.manage_search,
            color: Colors.blueGrey,
            title: 'Checking order...',
            body: 'Asking the service whether the order arrived.');
      case OrderPhase.confirmed:
        final b = r!.balances;
        return _Banner(
          key: const Key('outcome-confirmed'),
          icon: Icons.check_circle,
          color: Colors.green.shade700,
          title: 'Confirmed by the service',
          body: [
            '${r.raw['side']} ${money(r.raw['amount'] as num)} $_code '
                'at ${(r.rateUsed ?? 0).toStringAsFixed(4)} = ${money(r.plnAmount ?? 0)} PLN',
            'Wallet now: ${b.entries.map((e) => '${e.key} ${money(e.value)}').join(', ')}',
            'Order ${r.raw['requestId'].toString().substring(0, 8)}'
                '${r.replayed ? ' (answer saved earlier, not run twice)' : ''}',
          ].join('\n'),
          action: TextButton(onPressed: _newOrder, child: const Text('New order')),
        );
      case OrderPhase.rejected:
        if (r!.reason == 'RATE_CHANGED') {
          final nr = r.currentRate!;
          return _Banner(
            key: const Key('outcome-rejected'),
            icon: Icons.trending_up,
            color: Colors.orange.shade800,
            title: 'Rate changed, order not executed',
            body: 'The service now uses 1 $_code = ${nr.toStringAsFixed(4)} PLN. Nothing was bought or sold.',
            action: TextButton(
                onPressed: () => _newOrder(rate: nr),
                child: Text('Use ${nr.toStringAsFixed(4)} and review')),
          );
        }
        String fmt(Map<String, num> m) => m.entries.map((e) => '${money(e.value)} ${e.key}').join(', ');
        return _Banner(
          key: const Key('outcome-rejected'),
          icon: Icons.block,
          color: Colors.orange.shade800,
          title: 'Not enough money, order not executed',
          body: 'Needed ${fmt(r.needed)}, available ${fmt(r.available)}.',
          action: TextButton(onPressed: _newOrder, child: const Text('Change the order')),
        );
      case OrderPhase.invalid:
        final others = p!.details.where((d) => d.field != 'amount').map((d) => '${d.field}: ${d.problem}');
        return _Banner(
          key: const Key('outcome-invalid'),
          icon: Icons.edit_note,
          color: Colors.orange.shade800,
          title: 'Please check the input',
          body: [
            'The service received the order and refused the input (${p.code}). Nothing was saved.',
            p.message,
            ...others,
          ].join('\n'),
        );
      case OrderPhase.unknown:
        final t = ProblemText.of(p!);
        return _Banner(
          key: const Key('outcome-unknown'),
          icon: t.icon,
          color: Theme.of(context).colorScheme.error,
          title: '${t.title}: result not known yet',
          body: 'We did not get an answer, so we cannot say whether the order was executed. '
              'It is not marked as failed. Check its status when the connection is back.\n(${p.code})',
          action: TextButton(
              key: const Key('check-status'), onPressed: _checkStatus, child: const Text('Check order status')),
        );
      case OrderPhase.notFound:
        return const _Banner(
          key: Key('outcome-notfound'),
          icon: Icons.info_outline,
          color: Colors.blueGrey,
          title: 'Not executed',
          body: 'The order never reached the service. Nothing was bought or sold. You can send it again.',
        );
      case OrderPhase.failed:
        return ProblemView(p!);
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner(
      {super.key, required this.icon, required this.color, required this.title, required this.body, this.action});
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
            side: BorderSide(color: color), borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color))),
            ]),
            const SizedBox(height: 8),
            Text(body),
            if (action != null) Align(alignment: Alignment.centerRight, child: action),
          ]),
        ),
      );
}
