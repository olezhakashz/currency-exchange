// Lab 07: administration (role ADMIN). The tab is shown only to admins, but
// that is not the protection: the service checks the role on every
// /admin/... call and answers 403 FORBIDDEN to anyone else.
//
// A switch changes only after the service confirms; while the request is on
// its way the row shows a spinner, and with no answer nothing changes.
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../widgets/status_views.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<UserAccount>? _users;
  ApiProblem? _problem;
  bool _loading = true;
  int? _busyId;

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
      final u = await widget.api.adminUsers();
      if (mounted) setState(() => _users = u);
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _problem = p);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(UserAccount u) async {
    setState(() => _busyId = u.id);
    try {
      final changed = await widget.api.adminSetDisabled(u.id, !u.disabled);
      if (!mounted) return;
      setState(() => _users = [for (final x in _users!) x.id == changed.id ? changed : x]);
      _say('${changed.email} is now ${changed.disabled ? 'disabled' : 'enabled'} (confirmed by the service).');
    } on ApiProblem catch (p) {
      if (!mounted) return;
      _say(p.reachedService
          ? 'Refused by the service: ${p.code}. Nothing was changed.'
          : 'No connection: the change was not confirmed. Check the list when you are back online.');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, key: const Key('admin-message'))));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Users (admin)'), actions: [
          IconButton(
              key: const Key('refresh'),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: _body(),
      );

  Widget _body() {
    if (_loading) return const LoadingView('Loading users...');
    final p = _problem;
    if (p != null) return ProblemView(p, onRetry: _load);
    final me = widget.api.session.user!.id;
    return ListView(children: [
      for (final u in _users!)
        ListTile(
          key: Key('user-${u.id}'),
          leading: Icon(u.isAdmin ? Icons.admin_panel_settings : Icons.person_outline),
          title: Text(u.email),
          subtitle: Text('id ${u.id}, ${u.role}${u.disabled ? ', DISABLED' : ''}'),
          trailing: _busyId == u.id
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Switch(
                  key: Key('enabled-${u.id}'),
                  value: !u.disabled,
                  onChanged: u.id == me || _busyId != null ? null : (_) => _toggle(u),
                ),
        ),
      const ListTile(subtitle: Text('Switch = account enabled. Disabling ends that user\'s sessions at once.')),
    ]);
  }
}
