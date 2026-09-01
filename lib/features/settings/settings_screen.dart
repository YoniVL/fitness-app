import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/program_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/taxonomy.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(ownedEquipmentProvider);
    final restBetween = ref.watch(defaultRestBetweenSetsProvider);
    final restAfter = ref.watch(defaultRestAfterExerciseProvider);
    final sound = ref.watch(restTimerSoundProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Instellingen')),
      body: ListView(
        children: [
          _sectionHeader(context, 'Mijn materiaal'),
          owned.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Fout: $e'),
            ),
            data: (tags) => Column(
              children: [
                for (final tag in Equipment.all)
                  CheckboxListTile(
                    title: Text(Equipment.label(tag)),
                    subtitle: tag == Equipment.machine
                        ? const Text(Equipment.machineHint)
                        : null,
                    value: tags.contains(tag),
                    onChanged: (checked) async {
                      final next = {...tags};
                      if (checked == true) {
                        next.add(tag);
                      } else {
                        next.remove(tag);
                      }
                      await ref
                          .read(settingsRepositoryProvider)
                          .setOwnedEquipment(next);
                      ref.invalidate(ownedEquipmentProvider);
                      ref.invalidate(visibleStrengthProgramsProvider);
                    },
                  ),
              ],
            ),
          ),
          const Divider(),
          _sectionHeader(context, 'Rusttijden'),
          restBetween.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (seconds) => _RestRow(
              label: 'Tussen sets',
              seconds: seconds,
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setInt(SettingsKeys.defaultRestBetweenSets, v);
                ref.invalidate(defaultRestBetweenSetsProvider);
              },
            ),
          ),
          restAfter.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (seconds) => _RestRow(
              label: 'Tussen oefeningen',
              seconds: seconds,
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setInt(SettingsKeys.defaultRestAfterExercise, v);
                ref.invalidate(defaultRestAfterExerciseProvider);
              },
            ),
          ),
          sound.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (on) => SwitchListTile(
              title: const Text('Aftel-piep laatste 5 seconden'),
              value: on,
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setBool(SettingsKeys.restTimerSound, v);
                ref.invalidate(restTimerSoundProvider);
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _RestRow extends StatelessWidget {
  const _RestRow({
    required this.label,
    required this.seconds,
    required this.onChanged,
  });

  final String label;
  final int seconds;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            onPressed: seconds > 15 ? () => onChanged(seconds - 15) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 56,
            child: Text('$seconds s', textAlign: TextAlign.center),
          ),
          IconButton.filledTonal(
            onPressed: seconds < 300 ? () => onChanged(seconds + 15) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
