import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/program_repository.dart';
import '../../domain/models/program.dart';
import '../../domain/models/rowing_plan.dart';
import '../../domain/rowing_plan_generator.dart';
import 'widgets/interval_profile.dart';
import 'widgets/week_load_chart.dart';

const _bands = <(int, int)>[
  (15, 25),
  (20, 30),
  (25, 40),
  (30, 45),
  (45, 60),
];

class RowingBuilderScreen extends ConsumerStatefulWidget {
  const RowingBuilderScreen({super.key});

  @override
  ConsumerState<RowingBuilderScreen> createState() =>
      _RowingBuilderScreenState();
}

class _RowingBuilderScreenState extends ConsumerState<RowingBuilderScreen> {
  final _name = TextEditingController();
  int _sessions = 3;
  RowingGoal _goal = RowingGoal.uithouding;
  ProgramLevel _level = ProgramLevel.medium;
  final Set<(int, int)> _selectedBands = {_bands[1]};
  int _weeks = 8;

  GeneratedRowingPlan? _plan;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _generate() {
    final plan = RowingPlanGenerator().generate(RowingPlanInput(
      sessionsPerWeek: _sessions,
      goal: _goal,
      level: _level,
      bands: _selectedBands.isEmpty ? {_bands[1]} : _selectedBands,
      weeks: _weeks,
      name: _name.text,
    ));
    setState(() => _plan = plan);
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _busy = true);
    final id = await ref.read(programRepositoryProvider).createProgram(
          NewProgramDraft(
            name: plan.name,
            category: ProgramCategory.rowGenerated,
            discipline: Discipline.rowing,
            equipmentProfile: const [],
            level: plan.level,
            daysPerWeek: plan.sessionsPerWeek,
            rowingGoal: plan.goal,
            days: [
              for (final s in plan.sessions)
                NewProgramDayDraft(
                  label: s.label,
                  rowSessionType: s.type.name,
                  segments: [
                    for (final seg in s.segments)
                      NewRowSegmentDraft(
                        durationSeconds: seg.durationSeconds,
                        targetStrokeRate: seg.targetSpm,
                        intensityLabel: seg.intensityLabel,
                        isRest: seg.isRest,
                        drillKey: seg.drillKey,
                        zone: seg.zone,
                      ),
                  ],
                ),
            ],
          ),
        );
    ref.invalidate(rowingProgramsProvider);
    if (mounted) context.go('/rowing/library/program/$id');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roeiplan samenstellen')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Naam (optioneel)'),
          ),
          const SizedBox(height: 16),
          _label('Doel'),
          Wrap(
            spacing: 8,
            children: [
              for (final g in RowingGoal.values)
                ChoiceChip(
                  label: Text(g.label),
                  selected: _goal == g,
                  onSelected: (_) => setState(() => _goal = g),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_goal.description,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 16),
          _label('Sessies per week'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
              ButtonSegment(value: 5, label: Text('5')),
            ],
            selected: {_sessions},
            onSelectionChanged: (s) => setState(() => _sessions = s.first),
          ),
          const SizedBox(height: 16),
          _label('Niveau'),
          SegmentedButton<ProgramLevel>(
            segments: [
              for (final l in ProgramLevel.values)
                ButtonSegment(value: l, label: Text(l.label)),
            ],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
          const SizedBox(height: 16),
          _label('Sessieduur (meerdere mag — meer variatie)'),
          Wrap(
            spacing: 8,
            children: [
              for (final b in _bands)
                FilterChip(
                  label: Text('${b.$1}–${b.$2} min'),
                  selected: _selectedBands.contains(b),
                  onSelected: (v) => setState(() {
                    v ? _selectedBands.add(b) : _selectedBands.remove(b);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Planlengte'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 8, label: Text('8 wk')),
              ButtonSegment(value: 10, label: Text('10 wk')),
              ButtonSegment(value: 12, label: Text('12 wk')),
            ],
            selected: {_weeks},
            onSelectionChanged: (s) => setState(() => _weeks = s.first),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_plan == null ? 'Genereer' : 'Genereer opnieuw'),
          ),
          if (_plan != null) ..._preview(_plan!),
        ],
      ),
      bottomNavigationBar: _plan == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Opslaan'),
                ),
              ),
            ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );

  List<Widget> _preview(GeneratedRowingPlan plan) {
    final theme = Theme.of(context);
    final byWeek = <int, List<GeneratedRowSession>>{};
    for (final s in plan.sessions) {
      byWeek.putIfAbsent(s.weekIndex, () => []).add(s);
    }
    final weekMinutes = [
      for (final w in byWeek.keys)
        (byWeek[w]!.fold(0, (s, x) => s + x.totalSeconds) / 60).round(),
    ];
    return [
      const Divider(height: 32),
      Text('${plan.weeks} weken · ${plan.sessionsPerWeek}×/week',
          style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('Trainingsminuten per week', style: theme.textTheme.labelMedium),
      const SizedBox(height: 8),
      WeekLoadChart(minutesPerWeek: weekMinutes),
      const SizedBox(height: 12),
      for (final week in byWeek.keys)
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Week ${week + 1}', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final s in byWeek[week]!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(s.label.split(' · ').last)),
                            Text('~${(s.totalSeconds / 60).round()} min',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        IntervalProfile(
                          blocks: profileFromGenerated(s.segments),
                          height: 34,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }
}
