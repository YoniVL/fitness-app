import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/rowing_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/program.dart';
import '../../domain/models/rowing.dart';
import '../../domain/models/strength_set.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/rowing_format.dart';
import '../rowing/widgets/interval_profile.dart';

class _SessionView {
  _SessionView(this.detail, this.exerciseNames, this.muscleNames);
  final WorkoutSessionDetail detail;
  final Map<int, Exercise> exerciseNames;
  final Map<int, String> muscleNames;
}

/// Just the discipline of a session, so the screen can pick the right body
/// before loading the (strength- or rowing-specific) detail.
final _sessionDisciplineProvider =
    FutureProvider.family<Discipline?, int>((ref, sessionId) async {
  final detail =
      await ref.watch(workoutSessionRepositoryProvider).sessionDetail(sessionId);
  return detail?.session.discipline;
});

final _sessionViewProvider =
    FutureProvider.family<_SessionView?, int>((ref, sessionId) async {
  final detail =
      await ref.watch(workoutSessionRepositoryProvider).sessionDetail(sessionId);
  if (detail == null) return null;
  final exRepo = ref.read(exerciseRepositoryProvider);
  final names = await exRepo.byIds(detail.sets.map((s) => s.exerciseId));
  final muscleNames = await exRepo.muscleGroupNames();
  return _SessionView(detail, names, muscleNames);
});

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discipline = ref.watch(_sessionDisciplineProvider(sessionId));
    final isRowing = discipline.valueOrNull == Discipline.rowing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Samenvatting'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Notitie',
            onPressed: () => _editNote(context, ref, _currentNotes(ref)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: discipline.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fout: $e')),
        data: (d) {
          if (d == null) {
            return const Center(child: Text('Sessie niet gevonden'));
          }
          return isRowing
              ? _RowingDetailBody(sessionId: sessionId)
              : _StrengthDetailBody(sessionId: sessionId);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => context.go(
                isRowing ? '/rowing/today' : '/strength/today'),
            child: const Text('Klaar'),
          ),
        ),
      ),
    );
  }

  String? _currentNotes(WidgetRef ref) =>
      ref.read(_sessionViewProvider(sessionId)).valueOrNull?.detail.session.notes ??
      ref.read(rowingSessionDetailProvider(sessionId)).valueOrNull?.session.notes;

  Future<void> _editNote(
      BuildContext context, WidgetRef ref, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final saved = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notitie'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Notitie bij deze sessie'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    await ref
        .read(workoutSessionRepositoryProvider)
        .updateNotes(sessionId, saved.isEmpty ? null : saved);
    ref.invalidate(_sessionViewProvider(sessionId));
    ref.invalidate(rowingSessionDetailProvider(sessionId));
    ref.invalidate(recentSessionsProvider);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sessie verwijderen?'),
        content: const Text('Dit kan niet ongedaan worden gemaakt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(workoutSessionRepositoryProvider).deleteSession(sessionId);
    ref.invalidate(recentSessionsProvider);
    if (context.mounted) context.pop();
  }
}

class _StrengthDetailBody extends ConsumerWidget {
  const _StrengthDetailBody({required this.sessionId});
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(_sessionViewProvider(sessionId));
    return view.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fout: $e')),
      data: (data) => data == null
          ? const Center(child: Text('Sessie niet gevonden'))
          : _Body(view: data),
    );
  }
}

class _RowingDetailBody extends ConsumerWidget {
  const _RowingDetailBody({required this.sessionId});
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(rowingSessionDetailProvider(sessionId));
    final theme = Theme.of(context);
    final dateFmt = DateFormat('EEEE d MMMM y · HH:mm', 'nl');

    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fout: $e')),
      data: (data) {
        if (data == null) {
          return const Center(child: Text('Sessie niet gevonden'));
        }
        final r = data.rowing;
        final avgPace = paceSecPer500(
            r.totalDistanceM, Duration(seconds: r.durationSeconds));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(dateFmt.format(data.session.startedAt),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _Stat(
                    label: 'Afstand',
                    value: distanceLabel(r.totalDistanceM)),
                _Stat(
                    label: 'Duur',
                    value: hmsLabel(Duration(seconds: r.durationSeconds))),
                _Stat(label: 'Tempo', value: paceLabel(avgPace)),
                if (r.avgStrokeRate > 0)
                  _Stat(label: 'Slag', value: spmLabel(r.avgStrokeRate)),
                if (r.avgPower > 0)
                  _Stat(label: 'Vermogen', value: powerLabel(r.avgPower)),
                if (r.totalEnergyKcal > 0)
                  _Stat(
                      label: 'Energie',
                      value: '${r.totalEnergyKcal.round()} kcal'),
              ],
            ),
            if (data.planSegments.isNotEmpty) ...[
              const Divider(height: 32),
              Text('Geplande sessie', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              IntervalProfile(
                blocks: profileFromSegments(data.planSegments),
                height: 72,
              ),
              const SizedBox(height: 10),
              for (final s in data.planSegments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          hmsLabel(Duration(seconds: s.durationSeconds)),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _segmentLabel(s),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (data.samples.length >= 3) ...[
              const Divider(height: 32),
              Text('Tempo tijdens de sessie',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              SizedBox(height: 180, child: _PaceChart(samples: data.samples)),
            ],
            if (_hasField(data.samples, (s) => s.strokeRate)) ...[
              const SizedBox(height: 20),
              Text('Slagtempo', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              SizedBox(
                height: 140,
                child: _SampleChart(
                  samples: data.samples,
                  value: (s) => s.strokeRate,
                  color: const Color(0xFF66BB6A),
                ),
              ),
            ],
            if (_hasField(data.samples, (s) => s.heartRate?.toDouble())) ...[
              const SizedBox(height: 20),
              Text('Hartslag', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              SizedBox(
                height: 140,
                child: _SampleChart(
                  samples: data.samples,
                  value: (s) => s.heartRate?.toDouble(),
                  color: const Color(0xFFEF5350),
                ),
              ),
            ],
            if (data.session.notes != null &&
                data.session.notes!.isNotEmpty) ...[
              const Divider(height: 32),
              Text('Notities', style: theme.textTheme.titleSmall),
              Text(data.session.notes!),
            ],
          ],
        );
      },
    );
  }
}

String _segmentLabel(ProgramRowSegment s) {
  if (s.isRest) return 'Rust';
  final spm = s.targetStrokeRate;
  if (spm == null) return s.intensityLabel;
  // The label is often already just "r22"; don't repeat the rate.
  if (s.intensityLabel.toLowerCase().replaceAll(' ', '') == 'r$spm') {
    return s.intensityLabel;
  }
  return '${s.intensityLabel} · $spm spm';
}

bool _hasField(List<RowingSample> samples, double? Function(RowingSample) f) =>
    samples.where((s) => (f(s) ?? 0) > 0).length >= 3;

/// A plain time-series line for one sample field (stroke rate, heart rate…).
class _SampleChart extends StatelessWidget {
  const _SampleChart({
    required this.samples,
    required this.value,
    required this.color,
  });

  final List<RowingSample> samples;
  final double? Function(RowingSample) value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = <FlSpot>[];
    for (final s in samples) {
      final v = value(s);
      if (v == null || v <= 0) continue;
      points.add(FlSpot(s.tOffsetMs / 60000, v));
    }
    if (points.length < 2) {
      return Center(
        child: Text('Te weinig data',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    final minV = points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxV = points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final maxMin = points.last.x;
    final shortSession = maxMin < 3;
    final xInterval = (maxMin / 4).clamp(shortSession ? 0.25 : 1.0, 60.0);
    String xLabel(double v) =>
        shortSession ? '${(v * 60).round()}s' : "${v.round()}'";

    return LineChart(
      LineChartData(
        minY: (minV - 2).clamp(0, double.infinity),
        maxY: maxV + 2,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.onSurface.withValues(alpha: 0.08),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, m) => v == m.max || v == m.min
                  ? const SizedBox.shrink()
                  : Text(v.round().toString(),
                      style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: xInterval,
              getTitlesWidget: (v, m) => v == m.min
                  ? const SizedBox.shrink()
                  : Text(xLabel(v),
                      style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: false,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _PaceChart extends StatelessWidget {
  const _PaceChart({required this.samples});
  final List<RowingSample> samples;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = <FlSpot>[];
    for (final s in samples) {
      final pace = s.paceSec500m;
      if (pace == null || pace <= 0 || pace > 600) continue;
      points.add(FlSpot(s.tOffsetMs / 60000, pace));
    }
    if (points.length < 2) {
      return Center(
        child: Text('Te weinig tempo-data',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    final minPace = points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxPace = points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final maxMin = points.last.x;
    final shortSession = maxMin < 3;
    final xInterval = (maxMin / 4).clamp(shortSession ? 0.25 : 1.0, 60.0);
    String xLabel(double v) => shortSession
        ? '${(v * 60).round()}s'
        : "${v.round()}'";

    return LineChart(
      LineChartData(
        // Lower seconds/500m = faster: flip so "up" reads as faster.
        minY: (minPace - 10).clamp(60, double.infinity),
        maxY: maxPace + 10,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.onSurface.withValues(alpha: 0.08),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, m) => v == m.max || v == m.min
                  ? const SizedBox.shrink()
                  : Text(paceLabel(v, withUnit: false),
                      style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: xInterval,
              getTitlesWidget: (v, m) => v == m.min
                  ? const SizedBox.shrink()
                  : Text(xLabel(v),
                      style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: false,
            color: scheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view});
  final _SessionView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = view.detail.session;
    final dateFmt = DateFormat('EEEE d MMMM y · HH:mm', 'nl');

    final byExercise = <int, List<StrengthSet>>{};
    for (final s in view.detail.sets) {
      byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
    }

    final muscles = view.detail.muscleGroupSetCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(dateFmt.format(session.startedAt),
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            if (session.duration != null)
              _Stat(label: 'Duur', value: _fmtDuration(session.duration!)),
            _Stat(label: 'Sets', value: '${view.detail.workingSetCount}'),
            _Stat(label: 'Oefeningen', value: '${view.detail.exerciseCount}'),
            _Stat(label: 'Reps', value: '${view.detail.totalReps}'),
          ],
        ),
        if (muscles.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Getrainde spieren', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in muscles)
                Chip(
                  label: Text(
                      '${view.muscleNames[m.key] ?? '?'} · ${m.value}'),
                ),
            ],
          ),
        ],
        const Divider(height: 32),
        for (final entry in byExercise.entries) ...[
          Text(
            view.exerciseNames[entry.key]?.name ?? 'Oefening ${entry.key}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          ...entry.value.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 28, child: Text('${s.setIndex}')),
                  Text('${s.reps} reps'),
                  if (s.isWarmup) ...[
                    const SizedBox(width: 8),
                    Text('opwarming', style: theme.textTheme.labelSmall),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (session.notes != null && session.notes!.isNotEmpty) ...[
          const Divider(),
          Text('Notities', style: theme.textTheme.titleSmall),
          Text(session.notes!),
        ],
      ],
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}u ${m}m' : '${m}m';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.titleLarge),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
