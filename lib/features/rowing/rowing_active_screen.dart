import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/rowing_format.dart';
import '../../domain/rowing_ftp.dart';
import '../../domain/rowing_workouts.dart';
import '../../ui/async_view.dart';
import '../../ui/confirm_dialog.dart';
import 'ble/connect_sheet.dart';
import 'rower_service.dart';
import 'state/active_rowing_provider.dart';
import 'state/rowing_achievements_provider.dart';
import 'widgets/achievement_sheet.dart';
import 'widgets/interval_profile.dart';
import 'widgets/target_pace.dart';

/// The live rowing screen. Forced to landscape for a big, readable readout.
class RowingActiveScreen extends ConsumerStatefulWidget {
  const RowingActiveScreen({super.key});

  @override
  ConsumerState<RowingActiveScreen> createState() => _RowingActiveScreenState();
}

class _RowingActiveScreenState extends ConsumerState<RowingActiveScreen>
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    final async = ref.watch(activeRowingProvider);
    return Scaffold(
      body: SafeArea(
        child: async.view(
          (state) => state == null
              ? const Center(child: Text('Geen actieve roeisessie'))
              : _Body(state: state),
          loading: () => const Center(child: LoadingBox(height: 120)),
          error: (e) => const Center(child: ErrorBox(message: 'Fout')),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});
  final ActiveRowingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final live = state.live;
    final notifier = ref.read(activeRowingProvider.notifier);
    final hasSegments = state.segments.isNotEmpty;
    final ftp = ref.watch(rowingFtpProvider).valueOrNull;
    final dragK = ref.watch(rowingDragKProvider).valueOrNull ?? kGeneric;
    final status = ref.watch(rowerStatusProvider).valueOrNull ??
        ref.watch(rowerServiceProvider).status;

    final seg = state.currentSegment;
    final segZone = seg == null
        ? RowIntensity.easy
        : segmentZone(
            zone: seg.zone,
            spm: seg.targetStrokeRate,
            isRest: seg.isRest);
    final targetSplit =
        seg == null ? null : segmentTargetSplitSeconds(seg, ftp, dragK);

    return Column(
      children: [
        _TopBar(
          hasSegments: hasSegments,
          segmentIndex: state.segmentIndex,
          segmentCount: state.segments.length,
          segmentLabel: seg?.intensityLabel ?? 'Vrije sessie',
          zone: segZone,
          strokeTarget: seg?.targetStrokeRate,
          status: status,
          onStatusTap: () => showConnectRowerSheet(context, ref),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 360,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                        right: BorderSide(color: p.rule, width: 2)),
                  ),
                  child: _PacePanel(
                    pace: live?.paceSec500m,
                    targetSplit: targetSplit,
                    zone: segZone,
                    hasSegments: hasSegments,
                  ),
                ),
              ),
              Expanded(
                child: _MetricGrid(
                  strokeRate: live?.strokeRate,
                  power: live?.powerW,
                  distanceM: live?.distanceM ?? 0,
                  elapsed: state.elapsed,
                  heartRate: live?.heartRate ?? 0,
                ),
              ),
            ],
          ),
        ),
        _BottomBar(
          state: state,
          onPause: notifier.togglePause,
          onFinish: () => _finish(context, ref),
          onDiscard: () => _discard(context, ref),
        ),
      ],
    );
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(context,
        title: 'Sessie weggooien?',
        message: 'Niets wordt opgeslagen.',
        confirmLabel: 'Weggooien',
        destructive: true);
    if (!ok) return;
    await ref.read(activeRowingProvider.notifier).discard();
    if (context.mounted) context.go('/rowing/today');
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sessie afronden?'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Notitie (optioneel)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ANNULEREN'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('AFRONDEN'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final note = controller.text.trim();
    final id = await ref
        .read(activeRowingProvider.notifier)
        .finish(notes: note.isEmpty ? null : note);
    if (!context.mounted) return;
    if (id != null) {
      final newBadges = await ref
          .read(rowingAchievementsProvider.notifier)
          .evaluateAndDiff();
      if (!context.mounted) return;
      await showAchievementsUnlockedSheet(context, newBadges);
      if (!context.mounted) return;
    }
    if (id != null && (state.kind?.startsWith('ftp_') ?? false)) {
      context.go('/rowing/ftp/result/$id');
    } else {
      context.go(id != null ? '/rowing/log/session/$id' : '/rowing/today');
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.hasSegments,
    required this.segmentIndex,
    required this.segmentCount,
    required this.segmentLabel,
    required this.zone,
    required this.strokeTarget,
    required this.status,
    required this.onStatusTap,
  });

  final bool hasSegments;
  final int segmentIndex;
  final int segmentCount;
  final String segmentLabel;
  final RowIntensity zone;
  final int? strokeTarget;
  final RowerConnectionStatus status;
  final VoidCallback onStatusTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final zoneColor = context.zones.ramp[zone.index];
    final title = hasSegments
        ? 'INTERVAL ${segmentIndex + 1} VAN $segmentCount · '
            '${segmentLabel.toUpperCase()}'
        : segmentLabel.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule, width: 2)),
      ),
      child: Row(
        children: [
          _PulseMark(color: p.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: p.ink, letterSpacing: 1.0, fontSize: 11)),
          ),
          if (hasSegments) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              color: zoneColor,
              child: Text('ZONE ${_zoneName(zone)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: p.accentInk, fontSize: 10, letterSpacing: 0.6)),
            ),
            const SizedBox(width: 10),
          ],
          if (strokeTarget != null) ...[
            Text('SPM-DOEL $strokeTarget',
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontSize: 10, letterSpacing: 0.6)),
            const SizedBox(width: 10),
          ],
          InkWell(
            onTap: onStatusTap,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _StatusChip(status: status),
            ),
          ),
        ],
      ),
    );
  }
}

String _zoneName(RowIntensity z) => switch (z) {
      RowIntensity.rest => 'RUST',
      RowIntensity.easy => 'RUSTIG',
      RowIntensity.steady => 'DUUR',
      RowIntensity.threshold => 'DREMPEL',
      RowIntensity.hard => 'HARD',
      RowIntensity.max => 'MAX',
    };

class _PulseMark extends StatelessWidget {
  const _PulseMark({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(24, 14),
        painter: _PulsePainter(color),
      );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.miter;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.62)
      ..lineTo(w * 0.22, h * 0.62)
      ..lineTo(w * 0.32, h * 0.15)
      ..lineTo(w * 0.46, h * 0.95)
      ..lineTo(w * 0.6, 0)
      ..lineTo(w * 0.72, h * 0.62)
      ..lineTo(w, h * 0.62);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.color != color;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final RowerConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, color) = switch (status) {
      RowerConnectionStatus.connected => ('VERBONDEN', p.accent),
      RowerConnectionStatus.demo => ('DEMO', p.accent),
      RowerConnectionStatus.connecting => ('VERBINDEN…', p.mute),
      RowerConnectionStatus.disconnected => ('GEEN ROEIER', p.mute),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bluetooth, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10, letterSpacing: 0.6, color: color)),
      ],
    );
  }
}

class _PacePanel extends StatelessWidget {
  const _PacePanel({
    required this.pace,
    required this.targetSplit,
    required this.zone,
    required this.hasSegments,
  });

  final double? pace;
  final double? targetSplit;
  final RowIntensity zone;
  final bool hasSegments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final zones = context.zones;
    final delta = (pace != null && targetSplit != null)
        ? pace! - targetSplit!
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TEMPO /500M',
              style: theme.textTheme.labelSmall?.copyWith(
                  color: p.accent, letterSpacing: 1.4, fontSize: 11)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(paceLabel(pace, withUnit: false),
                      style: AppTheme.numeric(size: 104, color: p.ink)),
                ),
              ),
              if (delta != null && delta.abs() >= 1) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            delta < 0
                                ? Icons.arrow_drop_up
                                : Icons.arrow_drop_down,
                            size: 18,
                            color: delta < 0 ? p.accent : p.mute,
                          ),
                          Text('${delta.abs().round()}s',
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: delta < 0 ? p.accent : p.mute,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                      Text('VS DOEL',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(fontSize: 9, letterSpacing: 0.8)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (hasSegments) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: zones.ramp[i],
                        border: i == zone.index
                            ? Border.all(color: p.ink, width: 2)
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final z in RowIntensity.values)
                  Text(_zoneName(z),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 8,
                        letterSpacing: 0.3,
                        color: z == zone ? p.ink : p.mute,
                        fontWeight:
                            z == zone ? FontWeight.w800 : FontWeight.w600,
                      )),
              ],
            ),
          ] else if (targetSplit != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('DOEL ${paceLabel(targetSplit, withUnit: false)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontSize: 10, letterSpacing: 0.8)),
            ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.strokeRate,
    required this.power,
    required this.distanceM,
    required this.elapsed,
    required this.heartRate,
  });

  final double? strokeRate;
  final double? power;
  final double distanceM;
  final Duration elapsed;
  final int heartRate;

  @override
  Widget build(BuildContext context) {
    final showHr = heartRate > 0;
    final cells = <(String, String, String?)>[
      ('Slagfrequentie', (strokeRate ?? 0).round().toString(), ' s/m'),
      showHr
          ? ('Hartslag', '$heartRate', ' bpm')
          : ('Vermogen', (power ?? 0).round().toString(), ' W'),
      ('Afstand', distanceLabel(distanceM), null),
      ('Verstreken', hmsLabel(elapsed), null),
    ];
    final p = context.palette;
    return Column(
      children: [
        for (var r = 0; r < 2; r++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < 2; c++)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: c == 0
                              ? BorderSide(color: p.line)
                              : BorderSide.none,
                          bottom: r == 0
                              ? BorderSide(color: p.line)
                              : BorderSide.none,
                        ),
                      ),
                      child: _MetricCell(cells[r * 2 + c]),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell(this.data);
  final (String, String, String?) data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.$1.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10, letterSpacing: 1.1, color: p.mute)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RichText(
              text: TextSpan(
                text: data.$2,
                style: AppTheme.numeric(size: 52, color: p.ink),
                children: [
                  if (data.$3 != null)
                    TextSpan(
                      text: data.$3,
                      style: AppTheme.numeric(size: 17, color: p.mute)
                          .copyWith(letterSpacing: 0),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.onPause,
    required this.onFinish,
    required this.onDiscard,
  });

  final ActiveRowingState state;
  final VoidCallback onPause;
  final VoidCallback onFinish;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final notStarted = state.pausedReason == PauseReason.notStarted;
    final hasSegments = state.segments.isNotEmpty;

    final pauseHint = switch (state.pausedReason) {
      PauseReason.notStarted =>
        'Begin te roeien — de tijd start bij je eerste halen',
      PauseReason.idle => 'Gepauzeerd — begin te roeien om verder te gaan',
      PauseReason.background => 'Gepauzeerd — tik Hervat',
      _ => null,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.rule, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: hasSegments
                ? IntervalProfile(
                    blocks: profileFromSegments(state.segments),
                    height: 22,
                    progressFraction: state.segmentProgressFraction,
                  )
                : Text(
                    pauseHint ?? 'Vrije roeisessie loopt',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontSize: 11, letterSpacing: 0.4),
                  ),
          ),
          const SizedBox(width: 16),
          OutlinedButton(
            onPressed: onPause,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(state.paused ? Icons.play_arrow : Icons.pause, size: 16),
                const SizedBox(width: 7),
                Text(notStarted
                    ? 'START'
                    : state.paused
                        ? 'HERVAT'
                        : 'PAUZE'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onFinish,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.stop, size: 16),
                SizedBox(width: 7),
                Text('STOP'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onDiscard,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Weggooien',
          ),
        ],
      ),
    );
  }
}
