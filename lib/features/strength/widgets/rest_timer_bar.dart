import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/rest_timer_notifier.dart';

/// Bottom bar shown while the rest timer runs. A single visual countdown — no
/// per-second nagging, no sound until the rowing iteratie.
class RestTimerBar extends ConsumerWidget {
  const RestTimerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(restTimerProvider);
    if (!timer.active) return const SizedBox.shrink();

    final notifier = ref.read(restTimerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final remaining = timer.remainingSeconds;
    final mmss =
        '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}';

    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined),
              const SizedBox(width: 12),
              Text('Rust  $mmss',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 12),
              Expanded(
                child: LinearProgressIndicator(
                  value: timer.progress.clamp(0.0, 1.0),
                ),
              ),
              TextButton(
                onPressed: () => notifier.addSeconds(30),
                child: const Text('+30s'),
              ),
              TextButton(
                onPressed: notifier.skip,
                child: const Text('Overslaan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
