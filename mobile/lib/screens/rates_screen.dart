// READ path: GET /rates. Loading, success and error states.
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../widgets/status_views.dart';
import 'order_screen.dart';

class RatesScreen extends StatefulWidget {
  const RatesScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<RatesScreen> createState() => _RatesScreenState();
}

class _RatesScreenState extends State<RatesScreen> {
  RatesTable? _table;
  ApiProblem? _problem;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    try {
      final t = await widget.api.getRates();
      if (mounted) setState(() => _table = t);
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _problem = p);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Exchange rates'), actions: [
          IconButton(
              key: const Key('refresh'),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: _body(),
      );

  Widget _body() {
    if (_loading) return const LoadingView('Loading rates...');
    final p = _problem;
    if (p != null) return ProblemView(p, onRetry: _load);
    final t = _table!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        ListTile(
          key: const Key('rates-date'),
          leading: Icon(t.stale ? Icons.history : Icons.check_circle_outline,
              color: t.stale ? Colors.orange.shade800 : Colors.teal),
          title: Text('NBP table A, ${t.effectiveDate}'),
          subtitle: Text(t.stale
              ? 'Stale: NBP has published newer rates'
              : 'Current. Tap a currency to buy or sell.'),
        ),
        const Divider(height: 1),
        for (final r in t.rates)
          ListTile(
            key: Key('rate-${r.code}'),
            leading: CircleAvatar(child: Text(r.code.substring(0, 1))),
            title: Text(r.code),
            trailing: Text('${r.mid.toStringAsFixed(4)} PLN',
                style: Theme.of(context).textTheme.titleMedium),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OrderScreen(api: widget.api, rate: r))),
          ),
      ]),
    );
  }
}
