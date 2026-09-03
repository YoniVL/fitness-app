import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/rowing_repository.dart';
import '../../data/repositories/workout_session_repository.dart';

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
        );
    ref.invalidate(recentSessionsProvider);
    for (final p in rowingProgressProviders) {
      ref.invalidate(p);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Roeisessie loggen', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _distance,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Afstand',
            suffixText: 'm',
          ),
        ),
        const SizedBox(height: 12),
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
            const SizedBox(width: 12),
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
        const SizedBox(height: 12),
        TextField(
          controller: _spm,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Gemiddelde slag (optioneel)',
            suffixText: 'spm',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notitie (optioneel)'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
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
