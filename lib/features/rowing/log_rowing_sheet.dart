import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/rowing_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../ui/spacing.dart';
import 'state/rowing_achievements_provider.dart';
import 'widgets/achievement_sheet.dart';

/// The session kinds offered in the manual log (label → `rowing_sessions.kind`).
const _manualKinds = <(String, String?)>[
  ('Endurance', 'endurance'),
  ('Interval', 'intervalKort'),
  ('Test', 'test'),
  ('Techniek', 'techniek'),
  ('Overig', null),
];

/// Manual rowing log — a fallback for sessions done without the Bluetooth link.
Future<void> showLogRowingSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: const _LogRowingForm(),
    ),
  );
}

class _LogRowingForm extends ConsumerStatefulWidget {
  const _LogRowingForm();

  @override
  ConsumerState<_LogRowingForm> createState() => _LogRowingFormState();
}

class _LogRowingFormState extends ConsumerState<_LogRowingForm> {
  final _distance = TextEditingController();
  final _minutes = TextEditingController();
  final _seconds = TextEditingController();
  final _spm = TextEditingController();
  final _notes = TextEditingController();
  String? _error;
  bool _busy = false;
  int _kindIndex = 0;
  DateTime _when = DateTime.now();

  @override
  void dispose() {
    for (final c in [_distance, _minutes, _seconds, _spm, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final metres = double.tryParse(_distance.text.trim().replaceAll(',', '.'));
    final min = int.tryParse(_minutes.text.trim()) ?? 0;
    final sec = int.tryParse(_seconds.text.trim()) ?? 0;
    final duration = Duration(minutes: min, seconds: sec);

    if (metres == null || metres <= 0) {
      setState(() => _error = 'Vul een afstand in (meters).');
      return;
    }
    if (duration.inSeconds <= 0) {
      setState(() => _error = 'Vul een duur in.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    await ref.read(rowingRepositoryProvider).logManualSession(
          distanceM: metres,
          duration: duration,
          avgStrokeRate:
              double.tryParse(_spm.text.trim().replaceAll(',', '.')) ?? 0,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          kind: _manualKinds[_kindIndex].$2,
          when: _when,
        );
    ref.invalidate(recentSessionsProvider);
    for (final p in rowingProgressProviders) {
      ref.invalidate(p);
    }
    if (!mounted) return;
    final newBadges =
        await ref.read(rowingAchievementsProvider.notifier).evaluateAndDiff();
    if (!mounted) return;
    await showAchievementsUnlockedSheet(context, newBadges);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time?.hour ?? 12,
          time?.minute ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Roeisessie loggen', style: theme.textTheme.titleLarge),
        Gap.l,
        TextField(
          controller: _distance,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Afstand',
            suffixText: 'm',
          ),
        ),
        Gap.m,
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Minuten'),
              ),
            ),
            Gap.m,
            Expanded(
              child: TextField(
                controller: _seconds,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Seconden'),
              ),
            ),
          ],
        ),
        Gap.m,
        TextField(
          controller: _spm,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Gemiddelde slag (optioneel)',
            suffixText: 'SPM',
          ),
        ),
        Gap.m,
        DropdownButtonFormField<int>(
          initialValue: _kindIndex,
          decoration: const InputDecoration(labelText: 'Soort'),
          items: [
            for (var i = 0; i < _manualKinds.length; i++)
              DropdownMenuItem(value: i, child: Text(_manualKinds[i].$1)),
          ],
          onChanged: (v) => setState(() => _kindIndex = v ?? 0),
        ),
        Gap.xs,
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: const Text('Wanneer'),
          subtitle: Text(DateFormat('EEE d MMM y · HH:mm', 'nl').format(_when)),
          onTap: _pickWhen,
        ),
        Gap.m,
        TextField(
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notitie (optioneel)'),
        ),
        if (_error != null) ...[
          Gap.m,
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Opslaan'),
          ),
        ),
      ],
    );
  }
}
