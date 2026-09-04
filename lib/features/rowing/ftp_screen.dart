import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/rowing_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../domain/models/program.dart';
import '../../domain/rowing_format.dart';
import '../../domain/rowing_ftp.dart';
import 'ble/connect_sheet.dart';
import 'state/active_rowing_provider.dart';

/// Whether the ramp test is wired up (arrives in a later phase).
const _rampAvailable = false;

class FtpScreen extends ConsumerWidget {
  const FtpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ftp = ref.watch(rowingFtpProvider).valueOrNull;
    final dragK = ref.watch(rowingDragKProvider).valueOrNull ?? kGeneric;
    final history = ref.watch(rowingFtpHistoryProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('FTP · roeitest')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _CurrentCard(ftp: ftp, dragK: dragK),
          const SizedBox(height: 8),
          Text(
            'Je FTP is het vermogen dat je ongeveer een uur volhoudt — de basis '
            'voor de richttempo\'s per zone. Zet ’m met een test, handmatig, '
            'of vanuit een eerdere sessie.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bolt),
                  title: const Text('Doe een test'),
                  subtitle: const Text('20 minuten of ~2 km, in de app begeleid'),
                  onTap: () => _pickProtocol(context, ref),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Handmatig invoeren'),
                  subtitle: const Text('Vermogen in watt, of je 2k-tijd'),
                  onTap: () => _manualEntry(context, ref, dragK),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Overnemen uit logboek'),
                  subtitle: const Text('Uit een afgeronde roeisessie'),
                  onTap: () => _importFromLog(context, ref),
                ),
              ],
            ),
          ),
          if (history.length >= 2) ...[
            const SizedBox(height: 20),
            Text('Verloop', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(height: 120, child: _HistoryChart(history: history)),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final h in history.reversed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${h.watts.round()} W · '
                    '${paceLabel(h.splitSeconds(dragK: dragK))}'),
                subtitle: Text(
                    '${DateFormat('d MMM y', 'nl').format(h.setAt)} · ${h.source.label}'),
              ),
          ],
        ],
      ),
    );
  }

  // --- Test ---------------------------------------------------------

  Future<void> _pickProtocol(BuildContext context, WidgetRef ref) async {
    final p = await showModalBottomSheet<FtpProtocol>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final proto in FtpProtocol.values)
              ListTile(
                enabled: proto != FtpProtocol.ramp || _rampAvailable,
                title: Text(proto == FtpProtocol.ramp && !_rampAvailable
                    ? '${proto.label} (binnenkort)'
                    : proto.label),
                subtitle: Text(proto.blurb),
                onTap: () => Navigator.pop(context, proto),
              ),
          ],
        ),
      ),
    );
    if (p == null || !context.mounted) return;
    final level =
        ref.read(rowingLevelProvider).valueOrNull ?? ProgramLevel.medium;
    await ensureRowerConnected(context, ref);
    if (!context.mounted) return;
    await ref
        .read(activeRowingProvider.notifier)
        .startWorkout(ftpTestSegments(p, level), kind: p.kind);
    if (context.mounted) context.push('/rowing/active');
  }

  // --- Manual -----------------------------------------------------

  Future<void> _manualEntry(
      BuildContext context, WidgetRef ref, double dragK) async {
    final wattsCtrl = TextEditingController();
    final splitCtrl = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FTP handmatig'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: wattsCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  const InputDecoration(labelText: 'Vermogen', suffixText: 'W'),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('of'),
            ),
            TextField(
              controller: splitCtrl,
              decoration: const InputDecoration(
                  labelText: '2k-tijd', hintText: 'bv. 7:45'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              final w = double.tryParse(wattsCtrl.text.trim());
              if (w != null && w > 0) {
                Navigator.pop(context, w);
                return;
              }
              final t = _parseMinSec(splitCtrl.text.trim());
              if (t != null && t > 0) {
                // 2k time → average 500 m split → average watts → FTP (× 0.88).
                final avgW = wattsForSplit(t / 4, dragK: dragK);
                Navigator.pop(context, avgW * 0.88);
              }
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    if (result == null || result <= 0 || !context.mounted) return;
    await _save(ref, RowingFtp(
      watts: result,
      setAt: DateTime.now(),
      source: FtpSource.manual,
    ));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FTP opgeslagen: ${result.round()} W')));
    }
  }

  // --- Import from the logbook ------------------------------------

  Future<void> _importFromLog(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(recentSessionsProvider).valueOrNull ?? const [];
    final rowing = sessions
        .where((s) =>
            s.session.discipline == Discipline.rowing &&
            s.session.isFinished &&
            (s.rowing?.distanceM ?? 0) > 0)
        .toList();
    if (rowing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nog geen afgeronde roeisessie in het logboek.')));
      return;
    }
    final picked = await showModalBottomSheet<SessionSummary>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in rowing.take(20))
              ListTile(
                title: Text(DateFormat('EEE d MMM · HH:mm', 'nl')
                    .format(s.session.startedAt)),
                subtitle: Text(
                    '${distanceLabel(s.rowing!.distanceM)} · ${hmsLabel(s.rowing!.duration)}'),
                onTap: () => Navigator.pop(context, s),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;

    final proto = await showDialog<FtpProtocol>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Wat voor inspanning was dit?'),
        children: [
          for (final p in [FtpProtocol.test20, FtpProtocol.testShort])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p),
              child: Text(p.label),
            ),
        ],
      ),
    );
    if (proto == null || !context.mounted) return;

    final detail = await ref
        .read(rowingRepositoryProvider)
        .rowingDetail(picked.session.id);
    if (detail == null || !context.mounted) return;
    final res = computeFtp((
      samples: detail.samples,
      planSegments: detail.planSegments,
      totalDistanceM: detail.rowing.totalDistanceM,
      durationSeconds: detail.rowing.durationSeconds,
    ), proto);
    if (res.watts <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Kon geen vermogen uit die sessie halen.')));
      return;
    }
    final dragK = ref.read(rowingDragKProvider).valueOrNull ?? kGeneric;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FTP overnemen?'),
        content: Text('${res.watts.round()} W · '
            '${paceLabel(splitForWatts(res.watts, dragK: dragK))}'
            '${res.lowConfidence ? '\n\nRuwe schatting — weinig meetdata.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuleren')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Opslaan')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _save(ref, RowingFtp(
      watts: res.watts,
      setAt: DateTime.now(),
      source: FtpSource.import,
    ));
  }

  Future<void> _save(WidgetRef ref, RowingFtp ftp) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setRowingFtp(ftp);
    await repo.appendFtpHistory(ftp);
    ref.invalidate(rowingFtpProvider);
    ref.invalidate(rowingFtpHistoryProvider);
  }
}

int? _parseMinSec(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.ftp, required this.dragK});
  final RowingFtp? ftp;
  final double dragK;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = ftp;
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: f == null
            ? Row(
                children: [
                  Icon(Icons.speed, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text('Nog geen FTP ingesteld',
                      style: theme.textTheme.titleMedium),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Huidige FTP', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text('${f.watts.round()} W',
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    '${paceLabel(f.splitSeconds(dragK: dragK))}  ·  '
                    '${DateFormat('d MMM y', 'nl').format(f.setAt)}  ·  ${f.source.label}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
      ),
    );
  }
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.history});
  final List<RowingFtp> history;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spots = [
      for (var i = 0; i < history.length; i++)
        FlSpot(i.toDouble(), history[i].watts),
    ];
    final ws = history.map((h) => h.watts);
    final mn = ws.reduce((a, b) => a < b ? a : b);
    final mx = ws.reduce((a, b) => a > b ? a : b);
    return LineChart(
      LineChartData(
        minY: mn - 10,
        maxY: mx + 10,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.onSurface.withValues(alpha: 0.08), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, m) => v == m.max || v == m.min
                  ? const SizedBox.shrink()
                  : Text('${v.round()}',
                      style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: scheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
