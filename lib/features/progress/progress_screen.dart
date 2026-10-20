import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/rowing_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../domain/models/program.dart';
import '../../domain/rowing_achievements.dart';
import '../../domain/rowing_format.dart';
import '../../domain/rowing_ftp.dart';
import '../../ui/app_section.dart';
import '../../ui/async_view.dart';
import '../../ui/empty_state.dart';
import '../../ui/spacing.dart';
import '../../ui/stat_tile.dart';
import '../rowing/state/rowing_achievements_provider.dart';

final _selectedExerciseProvider = StateProvider<int?>((ref) => null);

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key, required this.discipline});

  final Discipline discipline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (discipline == Discipline.rowing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Voortgang')),
        body: const _RowingProgress(),
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
        padding: Insets.screenList,
        children: [
          if (streak >= 2) ...[
            Card(
              child: ListTile(
                leading: const Text('🔥', style: TextStyle(fontSize: 24)),
                title: Text('$streak weken op rij getraind'),
              ),
            ),
            Gap.l,
          ],
          AppSection(
            title: 'Sets per week',
            child: weekly.view(
              (points) {
                final withData = points.where((p) => p.value > 0).length;
                if (withData == 0) {
                  return const EmptyState('Nog geen afgeronde trainingen.');
                }
                if (withData < 3) {
                  final total = points.fold(0, (s, p) => s + p.value);
                  return Text(
                    '$total sets over $withData '
                    '${withData == 1 ? 'week' : 'weken'} — de grafiek komt na '
                    'een paar weken data.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  );
                }
                return _WeeklySetsChart(points: points);
              },
              loadingHeight: 180,
            ),
          ),
          Gap.s,
          AppSection(
            title: 'Sets per spiergroep · laatste 30 dagen',
            child: muscles.view(
              (rows) => rows.isEmpty
                  ? const EmptyState('Nog niets getraind deze maand.')
                  : _MuscleBars(rows: rows),
              loadingHeight: 180,
            ),
          ),
          Gap.s,
          AppSection(
            title: 'Per oefening · beste set',
            child: trained.view(
              (exercises) {
                if (exercises.isEmpty) {
                  return const EmptyState('Log eerst enkele trainingen.');
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
                    Gap.s,
                    _ExerciseHistoryChart(exerciseId: selected),
                  ],
                );
              },
              loadingHeight: 180,
            ),
          ),
          Gap.s,
          AppSection(
            title: 'Persoonlijke records · beste set',
            child: records.view(
              (rows) => rows.isEmpty
                  ? const EmptyState('Nog geen records — log enkele trainingen.')
                  : _RecordList(rows: rows),
              loadingHeight: 180,
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

// --- Rowing -------------------------------------------------------

/// The pace-trend filter: which session kinds feed the "gemiddeld tempo" chart.
enum _PaceFilter {
  rustig('Rustig', {'endurance', 'herstel'}),
  interval('Interval',
      {'drempel', 'intervalKort', 'intervalLang', 'piramide', 'krachtStroken'}),
  alles('Alles', null);

  const _PaceFilter(this.label, this.kinds);
  final String label;
  final Set<String>? kinds;
}

class _RowingProgress extends ConsumerStatefulWidget {
  const _RowingProgress();

  @override
  ConsumerState<_RowingProgress> createState() => _RowingProgressState();
}

class _RowingProgressState extends ConsumerState<_RowingProgress> {
  _PaceFilter _filter = _PaceFilter.rustig;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekly = ref.watch(rowingWeeklyDistanceProvider);
    final pace = ref.watch(rowingPaceHistoryProvider(_filter.kinds));
    final benchmarks =
        ref.watch(rowingBenchmarkHistoryProvider).valueOrNull ?? const [];
    final streak = ref.watch(rowingWeekStreakProvider).valueOrNull ?? 0;
    final totals = ref.watch(rowingMonthTotalsProvider).valueOrNull;
    final ftpHistory =
        ref.watch(rowingFtpHistoryProvider).valueOrNull ?? const <RowingFtp>[];
    final dragK = ref.watch(rowingDragKProvider).valueOrNull ?? kGeneric;
    final hasMeter = ref.watch(rowingHasPowerMeterProvider).valueOrNull ?? false;

    return ListView(
      padding: Insets.screenList,
      children: [
        if (streak >= 2) ...[
          Card(
            child: ListTile(
              leading: const Text('🔥', style: TextStyle(fontSize: 24)),
              title: Text('$streak weken op rij geroeid'),
            ),
          ),
          Gap.l,
        ],
        const _AchievementsEntry(),
        Gap.s,
        AppSection(
          title: 'Laatste 30 dagen',
          child: totals == null
              ? const LoadingBox(height: 180)
              : Row(
                  children: [
                    Expanded(
                      child: StatTile(
                          label: 'sessies',
                          value: '${totals.sessions}',
                          size: StatSize.small),
                    ),
                    Expanded(
                      child: StatTile(
                          label: 'afstand',
                          value: distanceLabel(totals.distanceM),
                          size: StatSize.small),
                    ),
                    Expanded(
                      child: StatTile(
                          label: 'tijd',
                          value: hmsLabel(
                              Duration(seconds: totals.durationSeconds)),
                          size: StatSize.small),
                    ),
                  ],
                ),
        ),
        Gap.s,
        AppSection(
          title: 'Afstand per week',
          child: weekly.view(
            (points) {
              final withData = points.where((p) => p.distanceM > 0).length;
              if (withData == 0) {
                return const EmptyState('Nog geen afgeronde roeisessies.');
              }
              if (withData < 2) {
                final total = points.fold(0.0, (s, p) => s + p.distanceM);
                return Text(
                  '${distanceLabel(total)} tot nu toe — de grafiek komt na een '
                  'paar weken.',
                  style: theme.textTheme.bodyMedium,
                );
              }
              return _WeeklyDistanceChart(points: points);
            },
            loadingHeight: 180,
          ),
        ),
        Gap.s,
        AppSection(
          title: 'Gemiddeld tempo · per sessie',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final f in _PaceFilter.values)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              Gap.m,
              pace.view(
                (points) => points.length < 3
                    ? const EmptyState('Log enkele roeisessies met afstand.')
                    : _PaceTrendChart(points: points),
                loadingHeight: 180,
              ),
            ],
          ),
        ),
        if (ftpHistory.isNotEmpty) ...[
          Gap.s,
          AppSection(
            title: hasMeter ? 'FTP' : 'Drempel-slagtempo',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ftpLabel(ftpHistory.last,
                      hasPowerMeter: hasMeter, dragK: dragK),
                  style: theme.textTheme.titleMedium,
                ),
                if (ftpHistory.length >= 2) ...[
                  Gap.s,
                  SizedBox(
                      height: 120,
                      child: _FtpTrendChart(
                          history: ftpHistory, asSpm: !hasMeter)),
                ],
              ],
            ),
          ),
        ],
        if (benchmarks.isNotEmpty) ...[
          Gap.s,
          AppSection(
            title: 'Testen',
            child: Column(
              children: [
                for (final b in benchmarks) ...[
                  _BenchmarkTile(benchmark: b),
                  if (b != benchmarks.last) Gap.l,
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AchievementsEntry extends ConsumerWidget {
  const _AchievementsEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(rowingAchievementsProvider).valueOrNull;
    final earned = view?.earnedIds ?? const <String>{};
    final unlockedCount =
        rowingAchievements.where((a) => earned.contains(a.id)).length;

    String? nextGoal;
    if (view != null) {
      RowingAchievement? best;
      var bestFrac = -1.0;
      for (final key in ladderKeys) {
        final next = ladderState(key, earned).next;
        if (next == null) continue;
        final f = achievementFraction(next, view.stats);
        if (f > bestFrac) {
          bestFrac = f;
          best = next;
        }
      }
      nextGoal = best?.title;
    }

    return Card(
      child: ListTile(
        leading: const Icon(Icons.military_tech_outlined),
        title: Text('Prestaties · $unlockedCount behaald'),
        subtitle: nextGoal == null
            ? null
            : Text('Volgende: ${nextGoal.toLowerCase()}',
                style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/rowing/achievements'),
      ),
    );
  }
}

class _BenchmarkTile extends StatelessWidget {
  const _BenchmarkTile({required this.benchmark});
  final RowingBenchmark benchmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = benchmark;
    final label = b.distanceM >= 1000
        ? '${b.distanceM ~/ 1000}k'
        : '${b.distanceM} m';
    final best = Duration(seconds: b.bestSeconds);
    final latest = Duration(seconds: b.latest.seconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            const Spacer(),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('PR ${hmsLabel(best)}'),
            ),
          ],
        ),
        Text(
          b.attempts.length == 1
              ? '1 poging'
              : 'laatste ${hmsLabel(latest)} · ${b.attempts.length} pogingen',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (b.attempts.length >= 2) ...[
          Gap.s,
          SizedBox(height: 120, child: _BenchmarkChart(benchmark: b)),
        ],
      ],
    );
  }
}

class _BenchmarkChart extends StatelessWidget {
  const _BenchmarkChart({required this.benchmark});
  final RowingBenchmark benchmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = benchmark.attempts;
    final spots = [
      for (var i = 0; i < a.length; i++)
        FlSpot(i.toDouble(), a[i].seconds.toDouble()),
    ];
    final mn = a.map((x) => x.seconds).reduce((x, y) => x < y ? x : y);
    final mx = a.map((x) => x.seconds).reduce((x, y) => x > y ? x : y);
    return LineChart(
      LineChartData(
        minY: (mn - 8).toDouble(),
        maxY: (mx + 8).toDouble(),
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
          bottomTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, m) => v == m.max || v == m.min
                  ? const SizedBox.shrink()
                  : Text(hmsLabel(Duration(seconds: v.round())),
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

class _FtpTrendChart extends StatelessWidget {
  const _FtpTrendChart({required this.history, this.asSpm = false});
  final List<RowingFtp> history;

  /// Plot the stroke rate each FTP stands for instead of watts.
  final bool asSpm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    double value(RowingFtp h) => asSpm ? h.spm : h.watts;
    final spots = [
      for (var i = 0; i < history.length; i++)
        FlSpot(i.toDouble(), value(history[i])),
    ];
    final ws = history.map(value);
    final mn = ws.reduce((a, b) => a < b ? a : b);
    final mx = ws.reduce((a, b) => a > b ? a : b);
    final pad = asSpm ? 1.0 : 10.0;
    return LineChart(
      LineChartData(
        minY: mn - pad,
        maxY: mx + pad,
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
          bottomTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
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

class _WeeklyDistanceChart extends StatelessWidget {
  const _WeeklyDistanceChart({required this.points});
  final List<RowingWeekPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxKm = points
        .map((p) => p.distanceM / 1000)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);
    final fmt = DateFormat('d/M');

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxKm * 1.15,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
                color: scheme.onSurface.withValues(alpha: 0.08),
                strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, m) => v == m.max || v == 0
                    ? const SizedBox.shrink()
                    : Text('${v.toStringAsFixed(0)}k',
                        style: _axisStyle(context)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (points.length > 6 && i.isOdd) {
                    return const SizedBox.shrink();
                  }
                  return Text(fmt.format(points[i].weekStart),
                      style: _axisStyle(context));
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${rod.toY.toStringAsFixed(1)} km\n'
                '${points[group.x].sessions} sessie'
                '${points[group.x].sessions == 1 ? '' : 's'}',
                TextStyle(color: scheme.onInverseSurface),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: points[i].distanceM / 1000,
                  color: scheme.primary,
                  width: 14,
                  borderRadius: BorderRadius.zero,
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _PaceTrendChart extends StatelessWidget {
  const _PaceTrendChart({required this.points});
  final List<RowingPacePoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('d/M');
    final paces = points.map((p) => p.paceSec500).toList();
    final minP = paces.reduce((a, b) => a < b ? a : b);
    final maxP = paces.reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: (minP - 8).clamp(60, double.infinity),
          maxY: maxP + 8,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
                color: scheme.onSurface.withValues(alpha: 0.08),
                strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, m) => v == m.max || v == m.min
                    ? const SizedBox.shrink()
                    : Text(paceLabel(v, withUnit: false),
                        style: _axisStyle(context)),
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
                        paceLabel(s.y),
                        TextStyle(color: scheme.onInverseSurface),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].paceSec500),
              ],
              isCurved: false,
              color: scheme.primary,
              barWidth: 2,
              dotData: FlDotData(
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                    radius: 3, color: scheme.primary, strokeWidth: 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                  borderRadius: BorderRadius.zero,
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
                        Container(height: 16, color: scheme.outlineVariant),
                        Container(
                          height: 16,
                          width: c.maxWidth * (r.sets / max),
                          color: scheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                Gap.s,
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

    return history.view(
      loadingHeight: 180,
      (points) {
        if (points.length < 2) {
          return const EmptyState(
              'Nog te weinig data — train deze oefening vaker.');
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
