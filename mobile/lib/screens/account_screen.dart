// Lab 07: who is signed in, their own orders (GET /orders), and logout.
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../widgets/status_views.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<OrderResult>? _orders;
  ApiProblem? _problem;
  bool _loading = true;
  bool _loggingOut = false;

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
      final o = await widget.api.getOrders();
      if (mounted) setState(() => _orders = o);
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _problem = p);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    // The app root shows the login screen with the result (told the service or not).
    await widget.api.logout();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.api.session.user;
    if (u == null) return const SizedBox.shrink();
    final p = _problem;
    return Scaffold(
      appBar: AppBar(title: const Text('Account'), actions: [
        IconButton(
            key: const Key('refresh'),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh)),
      ]),
      body: ListView(children: [
        ListTile(
          key: const Key('account-user'),
          leading: CircleAvatar(child: Icon(u.isAdmin ? Icons.admin_panel_settings : Icons.person)),
          title: Text(u.email),
          subtitle: Text('User ${u.id}, role ${u.role}'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            key: const Key('logout'),
            onPressed: _loggingOut ? null : _logout,
            icon: const Icon(Icons.logout),
            label: Text(_loggingOut ? 'Logging out...' : 'Log out'),
          ),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('My orders (as stored by the service)', style: Theme.of(context).textTheme.titleSmall),
        ),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: LoadingView('Loading orders...'))
        else if (p != null)
          ProblemView(p, onRetry: _load,
              extra: p.reachedService ? null : 'Orders can only be listed when the service answers.')
        else if (_orders!.isEmpty)
          const ListTile(key: Key('orders-empty'), title: Text('No orders yet.'))
        else
          for (final o in _orders!) _orderTile(o),
      ]),
    );
  }

  Widget _orderTile(OrderResult o) {
    final ok = o.status == 'CONFIRMED';
    final id = o.raw['requestId'].toString().substring(0, 8);
    return ListTile(
      key: Key('order-$id'),
      dense: true,
      leading: Icon(ok ? Icons.check_circle : Icons.block,
          color: ok ? Colors.green.shade700 : Colors.orange.shade800),
      title: Text(ok
          ? '${o.raw['side']} ${money(o.raw['amount'] as num)} ${o.raw['currency']} = ${money(o.plnAmount ?? 0)} PLN'
          : 'Rejected: ${o.reason}'),
      subtitle: Text('Order $id, ${o.raw['createdAt'] ?? ''}'),
    );
  }
}
