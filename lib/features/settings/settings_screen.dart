import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/program_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/taxonomy.dart';
import '../exercises/exercise_media.dart';
import 'backup.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(ownedEquipmentProvider);
    final restBetween = ref.watch(defaultRestBetweenSetsProvider);
    final restAfter = ref.watch(defaultRestAfterExerciseProvider);
    final sound = ref.watch(restTimerSoundProvider);
    final autoProgression = ref.watch(autoProgressionProvider);
    final warmup = ref.watch(warmupSuggestionsProvider);

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
          const Divider(),
          _sectionHeader(context, 'Programma'),
          autoProgression.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (on) => SwitchListTile(
              title: const Text('Automatische progressie'),
              subtitle: const Text(
                  'Elke ronde iets zwaarder: +1 rep tot +3, dan +1 set'),
              value: on,
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setBool(SettingsKeys.autoProgression, v);
                ref.invalidate(autoProgressionProvider);
              },
            ),
          ),
          warmup.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (on) => SwitchListTile(
              title: const Text('Opwarmsets voorstellen'),
              subtitle: const Text(
                  'Tip + vinkje vooraf bij de eerste set van een compound'),
              value: on,
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setBool(SettingsKeys.warmupSuggestions, v);
                ref.invalidate(warmupSuggestionsProvider);
              },
            ),
          ),
          const Divider(),
          _sectionHeader(context, 'Back-up'),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Exporteren'),
            subtitle: const Text('Deel een kopie van al je gegevens'),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Importeren'),
            subtitle: const Text('Vervang alles door een back-upbestand'),
            onTap: () => _import(context),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error),
            title: Text('Alle gegevens wissen',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: const Text('Terug naar een lege app'),
            onTap: () => _factoryReset(context),
          ),
          const Divider(),
          _sectionHeader(context, 'Credits'),
          ListTile(
            title: const Text('Oefeningfoto’s'),
            subtitle: const Text('everkinetic · CC BY-SA 3.0'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Oefeningfoto’s'),
                content: const Text(
                  '$exercisePhotoCredit\n\n'
                  'Bron: github.com/yuhonas/free-exercise-db\n'
                  'Licentie: creativecommons.org/licenses/by-sa/3.0',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Sluiten'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Backup.export();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export mislukt: $e')));
    }
  }

  Future<void> _import(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Back-up importeren?'),
        content: const Text(
            'Al je huidige trainingen, programma’s en instellingen worden '
            'overschreven door het gekozen bestand. Dit kan niet ongedaan '
            'gemaakt worden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kiezen & vervangen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final imported = await Backup.import();
      if (!imported || !context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Back-up geïmporteerd'),
          content: const Text(
              'Sluit de app en open hem opnieuw om alles te vernieuwen.'),
          actions: [
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('App sluiten'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import mislukt: $e')));
      }
    }
  }

  Future<void> _factoryReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alle gegevens wissen?'),
        content: const Text(
            'Al je trainingen, eigen programma’s en instellingen worden gewist. '
            'De oefeningendatabase en de standaardschema’s blijven. Dit kan niet '
            'ongedaan gemaakt worden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wissen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await Backup.factoryReset();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Gegevens gewist'),
          content: const Text(
              'Sluit de app en open hem opnieuw om met een schone lei te starten.'),
          actions: [
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('App sluiten'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Wissen mislukt: $e')));
      }
    }
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
