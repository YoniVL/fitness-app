import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One bar per week — training load (total minutes) — showing the build over a
/// plan. Modelled on a classic periodised-plan chart.
class WeekLoadChart extends StatelessWidget {
  const WeekLoadChart({super.key, required this.minutesPerWeek});

  /// Total training minutes for week 0, 1, 2, …
  final List<int> minutesPerWeek;

  @override
  Widget build(BuildContext context) {
    if (minutesPerWeek.length < 2) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final maxV =
        minutesPerWeek.reduce((a, b) => a > b ? a : b).toDouble().clamp(1, 1e9);

    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxV * 1.15,
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
                reservedSize: 30,
                getTitlesWidget: (v, m) => v == m.max || v == 0
                    ? const SizedBox.shrink()
                    : Text('${v.toInt()}',
                        style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= minutesPerWeek.length) {
                    return const SizedBox.shrink();
                  }
                  if (minutesPerWeek.length > 8 && i.isOdd) {
                    return const SizedBox.shrink();
                  }
                  return Text('${i + 1}',
                      style: Theme.of(context).textTheme.labelSmall);
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                'wk ${group.x + 1}\n${rod.toY.toInt()} min',
                TextStyle(color: scheme.onInverseSurface),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < minutesPerWeek.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: minutesPerWeek[i].toDouble(),
                  color: Color.lerp(scheme.primary.withValues(alpha: 0.55),
                      scheme.primary, minutesPerWeek[i] / maxV),
                  width: 12,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
