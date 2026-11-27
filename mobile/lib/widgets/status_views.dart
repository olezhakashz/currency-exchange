// Shared views for the three states every network call has:
// loading, success (drawn by each screen) and error.
import 'package:flutter/material.dart';

import '../api/api_client.dart';

class LoadingView extends StatelessWidget {
  const LoadingView(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        key: const Key('loading'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(text),
        ]),
      );
}

/// What the user is told for each kind of problem. Validation (the service
/// answered "your input is wrong") and no connection (no answer at all) look
/// different on purpose: different icon, colour, title and advice.
class ProblemText {
  const ProblemText(this.icon, this.title, this.advice);
  final IconData icon;
  final String title;
  final String advice;

  factory ProblemText.of(ApiProblem p) => switch (p.kind) {
        ProblemKind.noConnection => const ProblemText(Icons.wifi_off,
            'No connection to the service',
            'Your request did not reach the service. Check Wi-Fi or mobile data and try again.'),
        ProblemKind.timeout => const ProblemText(Icons.hourglass_bottom,
            'The service did not answer in time',
            'The network is slow or the service is busy. Try again.'),
        ProblemKind.validation => const ProblemText(Icons.edit_note,
            'Please check the input',
            'The service received the request and refused the input. Nothing was saved.'),
        ProblemKind.auth => const ProblemText(Icons.lock_outline,
            'Please log in again', 'Your session is not valid any more.'),
        ProblemKind.forbidden => const ProblemText(Icons.block,
            'Not allowed for your account',
            'The service checked your account and refused this. Nothing was changed.'),
        ProblemKind.conflict => const ProblemText(Icons.sync_problem,
            'The service refused the request', 'Start again with a new request.'),
        ProblemKind.server => const ProblemText(Icons.cloud_off,
            'The service has a problem', 'Try again in a moment.'),
      };
}

Color problemColor(BuildContext context, ApiProblem p) =>
    p.kind == ProblemKind.validation
        ? Colors.orange.shade800
        : Theme.of(context).colorScheme.error;

class ProblemView extends StatelessWidget {
  const ProblemView(this.problem, {super.key, this.onRetry, this.extra});
  final ApiProblem problem;
  final VoidCallback? onRetry;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final t = ProblemText.of(problem);
    final color = problemColor(context, problem);
    return Center(
      key: Key('problem-${problem.kind.name}'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(t.icon, size: 56, color: color),
          const SizedBox(height: 12),
          Text(t.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
          const SizedBox(height: 8),
          Text(t.advice, textAlign: TextAlign.center),
          if (extra != null) ...[
            const SizedBox(height: 8),
            Text(extra!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 8),
          Text('Code: ${problem.code}',
              style: Theme.of(context).textTheme.bodySmall),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again')),
          ],
        ]),
      ),
    );
  }
}

/// Lab 07: shown on every signed-in screen while the service can't be reached.
/// The user stays signed in; nothing is shown as done without an answer.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.email, this.walletAt});
  final String email;
  final DateTime? walletAt;

  @override
  Widget build(BuildContext context) => Material(
        key: const Key('offline-banner'),
        color: Colors.blueGrey.shade700,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Offline. Still signed in as $email. '
                  '${walletAt == null ? 'No balances confirmed yet.' : 'Balances are from ${hhmm(walletAt!)}.'} '
                  'Orders get a result only when the service answers.',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
      );
}

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
