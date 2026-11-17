// READ path with a token: GET /wallet.
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../widgets/status_views.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Wallet? _wallet;
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
      final w = await widget.api.getWallet();
      if (mounted) setState(() => _wallet = w);
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _problem = p);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Wallet'), actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: _body(),
      );

  Widget _body() {
    if (_loading) return const LoadingView('Loading wallet...');
    final p = _problem;
    if (p != null) return ProblemView(p, onRetry: _load);
    final b = _wallet!.balances;
    final codes = b.keys.toList()
      ..sort((x, y) => x == 'PLN' ? -1 : (y == 'PLN' ? 1 : x.compareTo(y)));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        for (final c in codes)
          ListTile(
            key: Key('balance-$c'),
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(c),
            trailing: Text(money(b[c]!), style: Theme.of(context).textTheme.titleMedium),
          ),
        const ListTile(
            subtitle: Text('Balances as stored by the service. Pull down to refresh.')),
      ]),
    );
  }
}
