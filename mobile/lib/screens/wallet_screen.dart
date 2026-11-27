// READ path with a token: GET /wallet.
//
// Lab 07: with no connection, the screen shows the last balances the service
// confirmed, clearly marked with their time, instead of an empty error. It
// never computes balances on the phone.
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
              key: const Key('refresh'),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: _body(),
      );

  Widget _body() {
    if (_loading) return const LoadingView('Loading wallet...');
    final p = _problem;
    final s = widget.api.session;
    final offline = p != null && !p.reachedService;
    if (offline && s.lastWallet != null) {
      return _list(s.lastWallet!,
          key: const Key('wallet-cached'),
          note: 'Not updated: no connection to the service. These are the balances the service '
              'last confirmed, at ${hhmm(s.lastWalletAt!)}. Orders sent since then may not be in them.',
          warn: true);
    }
    if (p != null) return ProblemView(p, onRetry: _load);
    return _list(_wallet!,
        key: const Key('wallet-live'), note: 'Balances as stored by the service. Pull down to refresh.');
  }

  Widget _list(Wallet w, {required Key key, required String note, bool warn = false}) {
    final b = w.balances;
    final codes = b.keys.toList()
      ..sort((x, y) => x == 'PLN' ? -1 : (y == 'PLN' ? 1 : x.compareTo(y)));
    return RefreshIndicator(
      key: key,
      onRefresh: _load,
      child: ListView(children: [
        if (warn)
          ListTile(
            leading: Icon(Icons.history, color: Colors.orange.shade800),
            title: Text('Last confirmed balances', style: TextStyle(color: Colors.orange.shade800)),
            subtitle: Text(note),
          ),
        for (final c in codes)
          ListTile(
            key: Key('balance-$c'),
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(c),
            trailing: Text(money(b[c]!),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: warn ? Colors.grey.shade600 : null)),
          ),
        if (!warn) ListTile(subtitle: Text(note)),
      ]),
    );
  }
}
