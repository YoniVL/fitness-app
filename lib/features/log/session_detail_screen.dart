import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/rowing_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/program.dart';
import '../../domain/models/rowing.dart';
import '../../domain/models/strength_set.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/rowing_format.dart';
import '../../ui/async_view.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/spacing.dart';
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
        title: const Text('Sessiedetail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: discipline.view(
        (d) {
          if (d == null) {
            return const Center(child: Text('Sessie niet gevonden'));
          }
          return isRowing
              ? _RowingDetailBody(sessionId: sessionId)
              : _StrengthDetailBody(sessionId: sessionId);
        },
        loading: () => const LoadingBox(height: 240),
        error: (e) => const Center(child: ErrorBox(message: 'Fout')),
      ),
      bottomNavigationBar: _BottomBar(
        onDone: () =>
            context.go(isRowing ? '/rowing/today' : '/strength/today'),
        onNote: () => _editNote(context, ref, _currentNotes(ref)),
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
            child: const Text('ANNULEREN'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('OPSLAAN'),
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
    final ok = await confirmDialog(
      context,
      title: 'Sessie verwijderen?',
      message: 'Dit kan niet ongedaan worden gemaakt.',
      confirmLabel: 'Verwijderen',
      destructive: true,
    );
    if (!ok) return;
    final wasRowing = ref.read(_sessionDisciplineProvider(sessionId)).valueOrNull ==
        Discipline.rowing;
    await ref.read(workoutSessionRepositoryProvider).deleteSession(sessionId);
    ref.invalidate(recentSessionsProvider);
    if (wasRowing) {
      for (final p in rowingProgressProviders) {
        ref.invalidate(p);
      }
    }
    if (context.mounted) context.pop();
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onDone, required this.onNote});
  final VoidCallback onDone;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.ground,
        border: Border(top: BorderSide(color: p.rule, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onDone,
                    child: const Text('KLAAR'),
                  ),
                ),
                Gap.s,
                OutlinedButton(
                  onPressed: onNote,
                  child: const Text('NOTITIE'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Shared Modernist building blocks ---------------------------------

/// The kicker + big title block at the top of a detail screen.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.kicker, required this.title});
  final String kicker;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kicker.toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: p.accent, letterSpacing: 1.3, fontSize: 10)),
          const SizedBox(height: 4),
          Text(title, style: theme.textTheme.headlineSmall),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: p.line)),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10,
              letterSpacing: 0.8,
              color: p.mute,
            ),
      ),
    );
  }
}

/// A 2-column grid of big-number metric cells with 1px inner rules and a 2px
/// bottom rule.
class _StatGrid extends StatelessWidget {
  const _StatGrid(this.cells);

  /// (label, value, unit?) — unit renders small and muted after the value.
  final List<(String, String, String?)> cells;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      final left = cells[i];
      final right = i + 1 < cells.length ? cells[i + 1] : null;
      final lastRow = i + 2 >= cells.length;
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: p.line),
                    bottom:
                        lastRow ? BorderSide.none : BorderSide(color: p.line),
                  ),
                ),
                child: _cell(context, left),
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom:
                        lastRow ? BorderSide.none : BorderSide(color: p.line),
                  ),
                ),
                child: right == null
                    ? const SizedBox.shrink()
                    : _cell(context, right),
              ),
            ),
          ],
        ),
      ));
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule, width: 2)),
      ),
      child: Column(children: rows),
    );
  }

  Widget _cell(BuildContext context, (String, String, String?) c) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.$1.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9, letterSpacing: 1.1, color: p.mute)),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              text: c.$2,
              style: AppTheme.numeric(size: 34, color: p.ink),
              children: [
                if (c.$3 != null)
                  TextSpan(
                    text: ' ${c.$3!.trim()}',
                    style: AppTheme.numeric(size: 14, color: p.mute)
                        .copyWith(letterSpacing: 0),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10, letterSpacing: 1.2, color: p.mute)),
    );
  }
}

// --- Rowing detail --------------------------------------------------

class _RowingDetailBody extends ConsumerWidget {
  const _RowingDetailBody({required this.sessionId});
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(rowingSessionDetailProvider(sessionId));
    final theme = Theme.of(context);
    final p = context.palette;
    final zones = context.zones;
    final dateFmt = DateFormat('EEE d MMM · HH:mm', 'nl');

    return detail.view(
      (data) {
        if (data == null) {
          return const Center(child: Text('Sessie niet gevonden'));
        }
        final r = data.rowing;
        final avgPace = paceSecPer500(
            r.totalDistanceM, Duration(seconds: r.durationSeconds));

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _TitleBlock(
              kicker: 'Roeien · ${dateFmt.format(data.session.startedAt)}',
              title: distanceLabel(r.totalDistanceM),
            ),
            _StatGrid([
              ('Gem. tempo /500m', paceLabel(avgPace, withUnit: false), null),
              ('Tijd', hmsLabel(Duration(seconds: r.durationSeconds)), null),
              if (r.avgPower > 0)
                ('Gem. vermogen', r.avgPower.round().toString(), 'W'),
              if (r.avgStrokeRate > 0)
                ('Gem. slag', r.avgStrokeRate.round().toString(), ' s/m'),
              if (r.totalEnergyKcal > 0)
                ('Energie', r.totalEnergyKcal.round().toString(), ' kcal'),
            ]),
            if (data.samples.length >= 3) ...[
              _SectionLabel('Tempo tijdens de sessie'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                    height: 150, child: _PaceChart(samples: data.samples)),
              ),
            ],
            if (_hasField(data.samples, (s) => s.strokeRate)) ...[
              _SectionLabel('Slagtempo'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  height: 120,
                  child: _SampleChart(
                    samples: data.samples,
                    value: (s) => s.strokeRate,
                    color: zones.steady,
                  ),
                ),
              ),
            ],
            if (_hasField(data.samples, (s) => s.heartRate?.toDouble())) ...[
              _SectionLabel('Hartslag'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  height: 120,
                  child: _SampleChart(
                    samples: data.samples,
                    value: (s) => s.heartRate?.toDouble(),
                    color: zones.max,
                  ),
                ),
              ),
            ],
            if (data.planSegments.isNotEmpty) ...[
              _SectionLabel('Geplande sessie'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: IntervalProfile(
                  blocks: profileFromSegments(data.planSegments),
                  height: 40,
                ),
              ),
              for (var i = 0; i < data.planSegments.length; i++)
                _SegmentRow(
                  index: i,
                  duration: hmsLabel(Duration(
                      seconds: data.planSegments[i].durationSeconds)),
                  label: _segmentLabel(data.planSegments[i]),
                  last: i == data.planSegments.length - 1,
                ),
            ],
            if (data.session.notes != null &&
                data.session.notes!.isNotEmpty) ...[
              _SectionLabel('Notities'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(data.session.notes!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: p.ink)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
      loading: () => const LoadingBox(height: 240),
      error: (e) => const Center(child: ErrorBox(message: 'Fout')),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.index,
    required this.duration,
    required this.label,
    required this.last,
  });
  final int index;
  final String duration;
  final String label;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.line),
          bottom: last ? BorderSide(color: p.line) : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text((index + 1).toString().padLeft(2, '0'),
                style: AppTheme.numeric(size: 14, color: p.ink)
                    .copyWith(letterSpacing: 0)),
          ),
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(duration,
              style: AppTheme.numeric(size: 14, color: p.mute)
                  .copyWith(letterSpacing: 0)),
        ],
      ),
    );
  }
}

String _segmentLabel(ProgramRowSegment s) {
  if (s.isRest) return 'Rust';
  final spm = s.targetStrokeRate;
  if (spm == null) return s.intensityLabel;
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
    final p = context.palette;
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
          getDrawingHorizontalLine: (_) =>
              FlLine(color: p.line, strokeWidth: 1),
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
    final p = context.palette;
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
    String xLabel(double v) =>
        shortSession ? '${(v * 60).round()}s' : "${v.round()}'";

    return LineChart(
      LineChartData(
        minY: (minPace - 10).clamp(60, double.infinity),
        maxY: maxPace + 10,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: p.line, strokeWidth: 1),
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
            color: p.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// --- Strength detail ----------------------------------------------

class _StrengthDetailBody extends ConsumerWidget {
  const _StrengthDetailBody({required this.sessionId});
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(_sessionViewProvider(sessionId));
    return view.view(
      (data) => data == null
          ? const Center(child: Text('Sessie niet gevonden'))
          : _Body(view: data),
      loading: () => const LoadingBox(height: 240),
      error: (e) => const Center(child: ErrorBox(message: 'Fout')),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view});
  final _SessionView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final session = view.detail.session;
    final dateFmt = DateFormat('EEE d MMM · HH:mm', 'nl');

    final byExercise = <int, List<StrengthSet>>{};
    for (final s in view.detail.sets) {
      byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
    }

    final muscles = view.detail.muscleGroupSetCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _TitleBlock(
          kicker: 'Krachttraining · ${dateFmt.format(session.startedAt)}',
          title: session.duration != null
              ? _fmtDuration(session.duration!)
              : 'Sessie',
        ),
        _StatGrid([
          ('Sets', '${view.detail.workingSetCount}', null),
          ('Oefeningen', '${view.detail.exerciseCount}', null),
          ('Reps', '${view.detail.totalReps}', null),
          if (session.duration != null)
            ('Duur', _fmtDuration(session.duration!), null),
        ]),
        if (muscles.isNotEmpty) ...[
          _SectionLabel('Getrainde spieren'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in muscles)
                  _DetailChip('${view.muscleNames[m.key] ?? '?'} · ${m.value}'),
              ],
            ),
          ),
        ],
        for (final entry in byExercise.entries) ...[
          _SectionLabel(
              view.exerciseNames[entry.key]?.name ?? 'Oefening ${entry.key}'),
          for (final s in entry.value)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(s.setIndex.toString().padLeft(2, '0'),
                        style: AppTheme.numeric(size: 14, color: p.ink)
                            .copyWith(letterSpacing: 0)),
                  ),
                  Expanded(
                    child: Text(
                      (view.exerciseNames[entry.key]?.isTimeBased ?? false)
                          ? '${s.reps}s'
                          : '${s.reps} reps',
                      style: AppTheme.numeric(size: 18, color: p.ink)
                          .copyWith(letterSpacing: 0, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (s.isWarmup)
                    Text('W',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: p.mute, letterSpacing: 1)),
                ],
              ),
            ),
        ],
        if (session.notes != null && session.notes!.isNotEmpty) ...[
          _SectionLabel('Notities'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(session.notes!,
                style: theme.textTheme.bodyMedium?.copyWith(color: p.ink)),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}u ${m}m' : '${m}m';
  }
}
