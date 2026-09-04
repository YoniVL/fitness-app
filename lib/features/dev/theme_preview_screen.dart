import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Debug-only: side-by-side light/dark preview of the app theme, with a
/// runtime switch between seed-variant "flavours" — all still green, per
/// `DynamicSchemeVariant`. Pick one, then it gets hardcoded in `theme.dart`
/// and this screen goes away (see the iteration 9 plan).
class ThemePreviewScreen extends StatefulWidget {
  const ThemePreviewScreen({super.key});

  @override
  State<ThemePreviewScreen> createState() => _ThemePreviewScreenState();
}

class _ThemePreviewScreenState extends State<ThemePreviewScreen> {
  DynamicSchemeVariant _variant = DynamicSchemeVariant.tonalSpot;

  static const _variants = [
    (DynamicSchemeVariant.tonalSpot, 'Standaard'),
    (DynamicSchemeVariant.fidelity, 'Verzadigd'),
    (DynamicSchemeVariant.neutral, 'Rustig'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thema-preview (dev)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<DynamicSchemeVariant>(
            segments: [
              for (final (v, label) in _variants)
                ButtonSegment(value: v, label: Text(label)),
            ],
            selected: {_variant},
            onSelectionChanged: (s) => setState(() => _variant = s.first),
          ),
          const SizedBox(height: 20),
          Text('Licht', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _ThemedPanel(theme: AppTheme.light(variant: _variant)),
          const SizedBox(height: 24),
          Text('Donker', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _ThemedPanel(theme: AppTheme.dark(variant: _variant)),
        ],
      ),
    );
  }
}

class _ThemedPanel extends StatelessWidget {
  const _ThemedPanel({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Theme(
        data: theme,
        child: Container(
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.all(16),
          child: const _PreviewContent(),
        ),
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final zones = theme.extension<RowZonePalette>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cadans', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Krachttraining en roeitraining bijhouden',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.rowing),
            title: const Text('Roeisessie afgerond'),
            subtitle: const Text('8,2 km · 32:10 · 2:03 /500m'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: () {}, child: const Text('Doorgaan')),
            OutlinedButton(onPressed: () {}, child: const Text('Later')),
            TextButton(onPressed: () {}, child: const Text('Annuleren')),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Demo-modus'),
          value: true,
          onChanged: (_) {},
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            Chip(label: const Text('Endurance')),
            ChoiceChip(label: const Text('Interval'), selected: true, onSelected: (_) {}),
            const Chip(label: Text('Test')),
          ],
        ),
        const SizedBox(height: 16),
        Text('Zone-ramp', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (c, label) in [
              (zones.easy, 'easy'),
              (zones.steady, 'steady'),
              (zones.threshold, 'thr'),
              (zones.hard, 'hard'),
              (zones.max, 'max'),
            ])
              Expanded(
                child: Column(
                  children: [
                    Container(height: 28, color: c),
                    const SizedBox(height: 4),
                    Text(label, style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: const [
                    FlSpot(0, 120), FlSpot(1, 118), FlSpot(2, 121),
                    FlSpot(3, 115), FlSpot(4, 112), FlSpot(5, 110),
                  ],
                  isCurved: true,
                  color: scheme.primary,
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                      show: true, color: scheme.primary.withValues(alpha: 0.12)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Sessie verwijderen?'),
              content: const Text('Dit kan niet ongedaan worden gemaakt.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuleren')),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Verwijderen')),
              ],
            ),
          ),
          child: const Text('Toon dialoog'),
        ),
      ],
    );
  }
}
