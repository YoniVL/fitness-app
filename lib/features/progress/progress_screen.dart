import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/program.dart';
import '../../data/repositories/workout_session_repository.dart';

final _selectedExerciseProvider = StateProvider<int?>((ref) => null);

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key, required this.discipline});

  final Discipline discipline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (discipline == Discipline.rowing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Voortgang')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Roei-voortgang (afstand per week, tempo-trend) komt binnenkort.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final weekly = ref.watch(weeklySetsProvider);
    final muscles = ref.watch(muscleGroupLoadProvider);
    final trained = ref.watch(trainedExercisesProvider);
    final streak = ref.watch(trainingWeekStreakProvider).valueOrNull ?? 0;
    final records = ref.watch(personalRecordsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Voortgang')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (streak >= 2) ...[
            Card(
              child: ListTile(
                leading: const Text('🔥', style: TextStyle(fontSize: 24)),
                title: Text('$streak weken op rij getraind'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _Section(
            title: 'Sets per week',
            child: weekly.when(
              loading: () => const _ChartLoading(),
              error: (e, _) => Text('Fout: $e'),
              data: (points) {
                final withData = points.where((p) => p.value > 0).length;
                if (withData == 0) {
                  return const _Empty('Nog geen afgeronde trainingen.');
                }
                if (withData < 3) {
                  final total = points.fold(0, (s, p) => s + p.value);
                  return Text(
                    '$total sets over $withData '
                    'week${withData == 1 ? '' : 'en'} — de grafiek komt na een '
                    'paar weken data.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  );
                }
                return _WeeklySetsChart(points: points);
              },
            ),
          ),
          const SizedBox(height: 8),
          _Section(
            title: 'Sets per spiergroep · laatste 30 dagen',
            child: muscles.when(
              loading: () => const _ChartLoading(),
              error: (e, _) => Text('Fout: $e'),
              data: (rows) => rows.isEmpty
                  ? const _Empty('Nog niets getraind deze maand.')
                  : _MuscleBars(rows: rows),
            ),
          ),
          const SizedBox(height: 8),
          _Section(
            title: 'Per oefening · beste set',
            child: trained.when(
              loading: () => const _ChartLoading(),
              error: (e, _) => Text('Fout: $e'),
              data: (exercises) {
                if (exercises.isEmpty) {
                  return const _Empty('Log eerst enkele trainingen.');
                }
                final selected = ref.watch(_selectedExerciseProvider) ??
                    exercises.first.id;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButton<int>(
                      isExpanded: true,
                      value: selected,
                      items: [
                        for (final e in exercises)
                          DropdownMenuItem(value: e.id, child: Text(e.name)),
                      ],
                      onChanged: (v) => ref
                          .read(_selectedExerciseProvider.notifier)
                          .state = v,
                    ),
                    const SizedBox(height: 8),
                    _ExerciseHistoryChart(exerciseId: selected),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _Section(
            title: 'Persoonlijke records · beste set',
            child: records.when(
              loading: () => const _ChartLoading(),
              error: (e, _) => Text('Fout: $e'),
              data: (rows) => rows.isEmpty
                  ? const _Empty('Nog geen records — log enkele trainingen.')
                  : _RecordList(rows: rows),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.rows});
  final List<PersonalRecord> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM y', 'nl');
    return Column(
      children: [
        for (final (i, r) in rows.take(20).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(i == 0 ? '🥇' : '${i + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                Expanded(
                  child: Text(r.name, style: theme.textTheme.bodyMedium),
                ),
                Text('${r.reps} reps',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(width: 10),
                Text(fmt.format(r.date),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class _WeeklySetsChart extends StatelessWidget {
  const _WeeklySetsChart({required this.points});
  final List<WeeklyPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxY = (points.map((p) => p.value).reduce((a, b) => a > b ? a : b))
        .toDouble()
        .clamp(1, double.infinity);
    final fmt = DateFormat('d/M');

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY + (maxY * 0.15),
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
                reservedSize: 28,
                getTitlesWidget: (value, meta) =>
                    value == meta.max || value == 0
                        ? const SizedBox.shrink()
                        : Text('${value.toInt()}',
                            style: _axisStyle(context)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  // Label every other week to avoid crowding.
                  if (points.length > 6 && i.isOdd) return const SizedBox.shrink();
                  return Text(fmt.format(points[i].weekStart),
                      style: _axisStyle(context));
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${rod.toY.toInt()} sets',
                TextStyle(color: scheme.onInverseSurface),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: points[i].value.toDouble(),
                  color: scheme.primary,
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _MuscleBars extends StatelessWidget {
  const _MuscleBars({required this.rows});
  final List<MuscleGroupLoad> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = rows.first.sets;
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(r.name,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(
                          height: 18,
                          decoration: BoxDecoration(
                            color: scheme.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          height: 18,
                          width: c.maxWidth * (r.sets / max),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: Text('${r.sets}',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ExerciseHistoryChart extends ConsumerWidget {
  const _ExerciseHistoryChart({required this.exerciseId});
  final int exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(exerciseHistoryProvider(exerciseId));
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('d/M');

    return history.when(
      loading: () => const _ChartLoading(),
      error: (e, _) => Text('Fout: $e'),
      data: (points) {
        if (points.length < 2) {
          return const _Empty('Nog te weinig data — train deze oefening vaker.');
        }
        final maxReps = points
            .map((p) => p.bestReps)
            .reduce((a, b) => a > b ? a : b)
            .toDouble();
        return SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxReps + 2,
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
                    reservedSize: 28,
                    getTitlesWidget: (v, m) => v == m.max || v == 0
                        ? const SizedBox.shrink()
                        : Text('${v.toInt()}', style: _axisStyle(context)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: (points.length / 4).ceilToDouble(),
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Text(fmt.format(points[i].date),
                          style: _axisStyle(context));
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem(
                            '${s.y.toInt()} reps',
                            TextStyle(color: scheme.onInverseSurface),
                          ))
                      .toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].bestReps.toDouble()),
                  ],
                  isCurved: false,
                  color: scheme.primary,
                  barWidth: 2,
                  dotData: FlDotData(
                    getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                      radius: 3.5,
                      color: scheme.primary,
                      strokeWidth: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

TextStyle? _axisStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelSmall
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
