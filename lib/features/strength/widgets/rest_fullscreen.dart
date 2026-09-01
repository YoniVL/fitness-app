import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/rest_timer_notifier.dart';

/// Full-screen rest view shown between sets and after an exercise. Big countdown
/// + the same controls as before. Room is left in the middle for the exercise
/// animation that lands in a later iteratie.
class RestFullscreen extends ConsumerWidget {
  const RestFullscreen({
    super.key,
    this.nextExerciseName,
    this.nextSetLabel,
  });

  final String? nextExerciseName;
  final String? nextSetLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(restTimerProvider);
    final notifier = ref.read(restTimerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final remaining = timer.remainingSeconds.clamp(0, 9999);
    final mmss = '${(remaining ~/ 60).toString().padLeft(2, '0')}:'
        '${(remaining % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text('RUST',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(letterSpacing: 4, color: scheme.primary)),
              const Spacer(),
              SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: CircularProgressIndicator(
                        value: (1 - timer.progress).clamp(0.0, 1.0),
                        strokeWidth: 10,
                        backgroundColor:
                            scheme.onSurface.withValues(alpha: 0.12),
                      ),
                    ),
                    Text(mmss, style: theme.textTheme.displayMedium),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (nextExerciseName != null) ...[
                Text('Volgende',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(nextExerciseName!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge),
                if (nextSetLabel != null)
                  Text(nextSetLabel!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
              ],
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundButton(
                    label: '−15s',
                    onTap: () => notifier.addSeconds(-15),
                  ),
                  const SizedBox(width: 16),
                  _RoundButton(
                    label: '+15s',
                    onTap: () => notifier.addSeconds(15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.onSecondaryContainer)),
        ),
      ),
    );
  }
}
