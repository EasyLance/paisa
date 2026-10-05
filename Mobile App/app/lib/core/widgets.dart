import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'theme/tokens.dart';

/// The leaf, as a rounded mark. A stand-in until the real leaf SVG is exported.
class PaisaMark extends StatelessWidget {
  const PaisaMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: context.paisa.lime, borderRadius: BorderRadius.circular(size / 3)),
    child: Icon(Icons.eco, size: size * 0.6, color: const Color(0xff1c3b2f)),
  );
}

/// A message that tells the person what happened and what to do, in the
/// ledger's own words.
class Notice extends StatelessWidget {
  const Notice(this.message, {super.key, this.isError = true});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: isError ? scheme.error : context.paisa.muted)),
    );
  }
}

/// Shown when something could not be loaded. It replaces the figures rather than
/// sitting beside them: a zeroed screen next to an error reads as "nothing
/// happened", and out-of-date numbers read as live ones.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, required this.what, required this.onRetry, this.extra = const []});

  final Object error;

  /// What failed to load, for the sentence: "your books", "this month".
  final String what;
  final VoidCallback onRetry;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final network = error is ApiError && (error as ApiError).isNetwork;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(network ? Icons.cloud_off : Icons.error_outline, size: 44, color: context.paisa.muted),
          const SizedBox(height: 14),
          Text(network ? 'Cannot reach Paisa' : 'Something went wrong', style: text.headlineSmall),
          const SizedBox(height: 6),
          Text(
            network
                ? 'Check your connection. Nothing is shown until Paisa can be reached, so you never see out-of-date figures.'
                : 'Paisa could not load $what. Try again in a moment.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ...extra,
        ]),
      ),
    );
  }
}
