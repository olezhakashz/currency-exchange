// Log in or create an account (Lab 07). After success the app root shows the
// home screen, because the Session now has a user.
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../widgets/status_views.dart';

/// Why the last session ended, in words for the user.
String? endedText(String? code) => switch (code) {
      null => null,
      'LOGGED_OUT' => 'You are logged out. The service ended the session.',
      'LOGGED_OUT_OFFLINE' => 'You are logged out on this phone. There was no connection, so the service '
          'was not told; the old session ends on the service when its token expires.',
      'TOKEN_EXPIRED' => 'Your session expired. Please log in again.',
      'TOKEN_REVOKED' => 'This session was ended (you logged out, or an administrator ended it). '
          'Please log in again.',
      'ACCOUNT_DISABLED' => 'Your account has been disabled by an administrator.',
      _ => 'Please log in again ($code).',
    };

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _url = TextEditingController(text: widget.api.baseUrl);
  late final _email = TextEditingController(text: widget.api.session.lastEmail ?? 'demo@example.com');
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  ApiProblem? _problem;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    widget.api.baseUrl = _url.text.trim();
    try {
      if (_register) {
        await widget.api.register(_email.text.trim(), _password.text);
      } else {
        await widget.api.login(_email.text.trim(), _password.text);
      }
      // The app root switches to the home screen (Session.start).
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _problem = p);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _fieldError(String field) {
    final p = _problem;
    if (p == null || p.kind != ProblemKind.validation) return null;
    final d = p.details.where((d) => d.field == field);
    return d.isEmpty ? null : d.first.problem;
  }

  @override
  Widget build(BuildContext context) {
    final p = _problem;
    final ended = endedText(widget.api.session.endedReason);
    final error = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'Create account' : 'Currency Exchange')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (ended != null && p == null) ...[
          Card(
            key: const Key('session-ended'),
            elevation: 0,
            color: Colors.blueGrey.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.lock_outline),
                const SizedBox(width: 12),
                Expanded(child: Text(ended)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
            key: const Key('url'),
            controller: _url,
            decoration: const InputDecoration(
                labelText: 'Service address', helperText: 'http:// for the dev server, https:// when deployed')),
        TextField(
            key: const Key('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Email', errorText: _fieldError('email'))),
        TextField(
            key: const Key('password'),
            controller: _password,
            obscureText: true,
            onSubmitted: (_) => _busy ? null : _go(),
            decoration: InputDecoration(
                labelText: 'Password',
                helperText: _register ? '8 to 128 characters' : null,
                errorText: _fieldError('password'))),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('login'),
          onPressed: _busy ? null : _go,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_register ? 'Create account' : 'Log in'),
        ),
        TextButton(
          key: const Key('switch-mode'),
          onPressed: _busy
              ? null
              : () => setState(() {
                    _register = !_register;
                    _problem = null;
                    if (_register) _email.clear();
                  }),
          child: Text(_register ? 'I have an account: log in' : 'No account? Create one'),
        ),
        if (p != null) ...[
          const SizedBox(height: 16),
          switch (p.code) {
            'BAD_CREDENTIALS' => Text('Wrong email or password.', key: const Key('login-error'),
                style: TextStyle(color: error)),
            'EMAIL_TAKEN' => Text('An account with this email already exists. Log in instead.',
                key: const Key('login-error'), style: TextStyle(color: error)),
            'ACCOUNT_DISABLED' => Text('This account is disabled. Contact the administrator.',
                key: const Key('login-error'), style: TextStyle(color: error)),
            _ when p.kind == ProblemKind.validation => Text('Please check the fields above.',
                key: const Key('login-error'), style: TextStyle(color: Colors.orange.shade800)),
            _ => ProblemView(p),
          },
        ],
      ]),
    );
  }
}
