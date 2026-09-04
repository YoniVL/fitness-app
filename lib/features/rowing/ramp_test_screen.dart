import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/repositories/settings_repository.dart';
import '../../domain/rowing_format.dart';
import '../../domain/rowing_ftp.dart';
import 'state/ramp_test_provider.dart';
import 'state/rowing_achievements_provider.dart';
import 'widgets/achievement_sheet.dart';

/// Live ramp test: the watt target rises each minute; the rower chases it until
/// they can't. Landscape — like the live rowing screen — with one big target
/// and one big live readout side by side.
class RampTestScreen extends ConsumerStatefulWidget {
  const RampTestScreen({super.key});

  @override
  ConsumerState<RampTestScreen> createState() => _RampTestScreenState();
}

class _RampTestScreenState extends ConsumerState<RampTestScreen>
    with WidgetsBindingObserver {
  static const _landscape = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(_landscape);
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rampTestProvider.notifier).begin();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android drops the orientation lock while backgrounded — re-assert it.
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setPreferredOrientations(_landscape);
      WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    ref.listen(rampTestProvider.select((s) => s.sessionId), (_, id) async {
      if (id == null) return;
      final newBadges = await ref
          .read(rowingAchievementsProvider.notifier)
          .evaluateAndDiff();
      if (!context.mounted) return;
      await showAchievementsUnlockedSheet(context, newBadges);
      if (context.mounted) context.go('/rowing/ftp/result/$id');
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
        toolbarHeight: 44,
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
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
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
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: s.stepElapsed.inSeconds / RampProtocol.stepSeconds,
                      minHeight: 4,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _Big(
                              label: 'DOEL',
                              value: '${s.targetWatts.round()} W',
                              sub: paceLabel(
                                  splitForWatts(s.targetWatts, dragK: dragK),
                                  withUnit: false),
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _Big(
                              label: 'JIJ',
                              value: '${liveW.round()} W',
                              sub: paceLabel(live?.paceSec500m,
                                  withUnit: false),
                              color: holdColor,
                              badge: holdLabel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _Small('Slag', spmLabel(live?.strokeRate)),
                              _Small('Tijd', hmsLabel(s.elapsed)),
                              if ((live?.heartRate ?? 0) > 0)
                                _Small('HS', '${live!.heartRate}'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 48)),
                            onPressed: s.phase == RampPhase.done
                                ? null
                                : () =>
                                    ref.read(rampTestProvider.notifier).finish(),
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop — ik kan niet meer'),
                          ),
                        ),
                      ],
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (badge.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(badge,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w700)),
              ),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: theme.textTheme.titleLarge),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
