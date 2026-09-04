import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/rowing_format.dart';
import '../../domain/rowing_ftp.dart';
import 'state/ramp_test_provider.dart';

/// Live ramp test: the watt target rises each minute; the rower chases it until
/// they can't. Portrait — one big target, one big live readout.
class RampTestScreen extends ConsumerStatefulWidget {
  const RampTestScreen({super.key});

  @override
  ConsumerState<RampTestScreen> createState() => _RampTestScreenState();
}

class _RampTestScreenState extends ConsumerState<RampTestScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rampTestProvider.notifier).begin();
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    ref.listen(rampTestProvider.select((s) => s.sessionId), (_, id) {
      if (id != null) context.go('/rowing/ftp/result/$id');
    });

    final s = ref.watch(rampTestProvider);
    final dragK = ref.watch(rowingDragKProvider).valueOrNull ?? kGeneric;
    final live = s.live;
    final liveW = live?.powerW ?? 0;

    final (holdLabel, holdColor) = s.phase == RampPhase.waiting
        ? ('', scheme.onSurfaceVariant)
        : switch (rampHold(s.recentAvgWatts, s.targetWatts)) {
            RampHold.onPace => ('op tempo', scheme.primary),
            RampHold.close => ('bijna', const Color(0xFFFFCA28)),
            RampHold.dropping => ('je valt terug', const Color(0xFFFF7043)),
          };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ramptest'),
        actions: [
          if (s.phase != RampPhase.done)
            TextButton(
              onPressed: () async {
                await ref.read(rampTestProvider.notifier).abort();
                if (context.mounted) context.go('/rowing/ftp');
              },
              child: const Text('Afbreken'),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: s.phase == RampPhase.waiting
              ? Center(
                  child: Text(
                    'Begin rustig te roeien — de test start bij je eerste halen. '
                    'Volg het wattdoel; het loopt elke minuut op.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              : Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Stap ${s.step + 1}',
                            style: theme.textTheme.titleMedium),
                        Text(hmsLabel(s.stepRemaining),
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    LinearProgressIndicator(
                      value: s.stepElapsed.inSeconds / RampProtocol.stepSeconds,
                      minHeight: 4,
                    ),
                    const SizedBox(height: 28),
                    _Big(
                      label: 'DOEL',
                      value: '${s.targetWatts.round()} W',
                      sub: paceLabel(
                          splitForWatts(s.targetWatts, dragK: dragK),
                          withUnit: false),
                      color: scheme.onSurface,
                    ),
                    const SizedBox(height: 24),
                    _Big(
                      label: 'JIJ',
                      value: '${liveW.round()} W',
                      sub: paceLabel(live?.paceSec500m, withUnit: false),
                      color: holdColor,
                      badge: holdLabel,
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _Small('Slag', spmLabel(live?.strokeRate)),
                        _Small('Tijd', hmsLabel(s.elapsed)),
                        if ((live?.heartRate ?? 0) > 0)
                          _Small('HS', '${live!.heartRate}'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 52)),
                        onPressed: s.phase == RampPhase.done
                            ? null
                            : () => ref.read(rampTestProvider.notifier).finish(),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop — ik kan niet meer'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    this.badge = '',
  });
  final String label;
  final String value;
  final String sub;
  final Color color;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (badge.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(badge,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: theme.textTheme.displayLarge
                  ?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ),
        Text('$sub /500m',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Small extends StatelessWidget {
  const _Small(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.titleLarge),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
