import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../widgets/status_views.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _url = TextEditingController(text: widget.api.baseUrl);
  final _email = TextEditingController(text: 'demo@example.com');
  final _password = TextEditingController();
  bool _busy = false;
  ApiProblem? _problem;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    widget.api.baseUrl = _url.text.trim();
    try {
      await widget.api.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(api: widget.api)));
    } on ApiProblem catch (p) {
      setState(() => _problem = p);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _problem;
    return Scaffold(
      appBar: AppBar(title: const Text('Currency Exchange')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        TextField(
            key: const Key('url'),
            controller: _url,
            decoration: const InputDecoration(
                labelText: 'Service address', helperText: 'http:// for the dev server, https:// when deployed')),
        TextField(
            key: const Key('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email')),
        TextField(
            key: const Key('password'),
            controller: _password,
            obscureText: true,
            onSubmitted: (_) => _busy ? null : _login(),
            decoration: const InputDecoration(labelText: 'Password')),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('login'),
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Log in'),
        ),
        if (p != null) ...[
          const SizedBox(height: 16),
          if (p.code == 'BAD_CREDENTIALS')
            Text('Wrong email or password.',
                style: TextStyle(color: Theme.of(context).colorScheme.error))
          else
            ProblemView(p),
        ],
      ]),
    );
  }
}
