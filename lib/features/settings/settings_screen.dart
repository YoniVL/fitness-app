import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/program_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/rowing_format.dart';
import '../../domain/rowing_ftp.dart';
import '../../domain/taxonomy.dart';
import '../../ui/app_section.dart';
import '../../ui/async_view.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/spacing.dart';
import '../exercises/exercise_media.dart';
import '../rowing/ble/connect_sheet.dart';
import '../rowing/rower_service.dart';
import '../rowing/rowing_cues.dart';
import '../watch/watch_ping.dart';
import 'backup.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(ownedEquipmentProvider);
    final restBetween = ref.watch(defaultRestBetweenSetsProvider);
    final restAfter = ref.watch(defaultRestAfterExerciseProvider);
    final sound = ref.watch(restTimerSoundProvider);
    final cueSound = ref.watch(rowingCueSoundProvider);
    final demoMode = ref.watch(rowingDemoModeProvider);
    final hasPowerMeter = ref.watch(rowingHasPowerMeterProvider);
    final paceCorrection = ref.watch(rowingPaceCorrectionProvider);
    final autoProgression = ref.watch(autoProgressionProvider);
    final warmup = ref.watch(warmupSuggestionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Instellingen')),
      body: ListView(
        children: [
          const AppSectionHeader('Mijn materiaal'),
          owned.view(
            loadingHeight: 80,
            (tags) => Column(
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
          const AppSectionHeader('Rusttijden'),
          restBetween.viewOrNothing(
            (seconds) => _RestRow(
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
          restAfter.viewOrNothing(
            (seconds) => _RestRow(
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
          sound.viewOrNothing(
            (on) => SwitchListTile(
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
          const AppSectionHeader('Roeien'),
          cueSound.viewOrNothing(
            (on) => SwitchListTile(
              title: const Text('Piep bij segmentwissel'),
              subtitle: const Text(
                  'Een korte toon 10 sec vóór en bij elke wissel tijdens een sessie'),
              value: on,
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setBool(SettingsKeys.rowingCueSound, v);
                ref.invalidate(rowingCueSoundProvider);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('Roeitrainer'),
            subtitle: Text(
                ref.watch(rowingDeviceNameProvider).valueOrNull ??
                    'Geen trainer gekoppeld'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showConnectRowerSheet(context, ref),
          ),
          hasPowerMeter.viewOrNothing(
            (on) => SwitchListTile(
              title: const Text('Vermogensmeter aanwezig'),
              subtitle: const Text(
                  'Alleen aanzetten als je roeitrainer echt vermogen meet. '
                  'Anders reken alles vanaf je tempo — de meeste trainers '
                  'hebben geen vermogensmeter.'),
              value: on,
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setRowingHasPowerMeter(v);
                ref.invalidate(rowingHasPowerMeterProvider);
                ref.invalidate(rowingDragKProvider);
              },
            ),
          ),
          paceCorrection.viewOrNothing(
            (pct) => _PercentRow(
              label: 'Tempo-correctie',
              subtitle: pct == 0
                  ? 'Vergelijk een korte, bekende afstand tussen deze app en '
                      'een andere bron; vul hier het verschil in. Positief = '
                      'je bent sneller dan de trainer denkt.'
                  : (pct > 0
                      ? '+${pct.round()}% — het weergegeven tempo/afstand is '
                          '${pct.round()}% sneller dan wat de trainer meldt.'
                      : '${pct.round()}% — het weergegeven tempo/afstand is '
                          '${pct.abs().round()}% trager dan wat de trainer '
                          'meldt.'),
              percent: pct.round(),
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setRowingPaceCorrectionPercent(v.toDouble());
                ref.invalidate(rowingPaceCorrectionProvider);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('FTP (roeitest)'),
            subtitle: Text(switch (ref.watch(rowingFtpProvider).valueOrNull) {
              final f? => '${f.watts.round()} W · '
                  '${paceLabel(f.splitSeconds(dragK: ref.watch(rowingDragKProvider).valueOrNull ?? kGeneric))}',
              _ => 'Nog niet ingesteld',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/rowing/ftp'),
          ),
          demoMode.viewOrNothing(
            (on) => SwitchListTile(
              title: const Text('Demo-modus'),
              subtitle: const Text(
                  'Gebruik gesimuleerde roeidata i.p.v. de Bluetooth-trainer'),
              value: on,
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setBool(SettingsKeys.rowingDemoMode, v);
                ref.invalidate(rowingDemoModeProvider);
                ref.invalidate(rowerServiceProvider);
              },
            ),
          ),
          const Divider(),
          const AppSectionHeader('Programma'),
          autoProgression.viewOrNothing(
            (on) => SwitchListTile(
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
          warmup.viewOrNothing(
            (on) => SwitchListTile(
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
          const AppSectionHeader('Horloge'),
          ListTile(
            leading: const Icon(Icons.watch_outlined),
            title: const Text('Verbinding testen'),
            subtitle: const Text('Stuur een ping naar je gekoppelde horloge'),
            onTap: () => pingWatch(context, ref),
          ),
          const Divider(),
          const AppSectionHeader('Back-up'),
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
          const AppSectionHeader('Credits'),
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
          Gap.xl,
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
    final ok = await confirmDialog(
      context,
      title: 'Back-up importeren?',
      message: 'Al je huidige trainingen, programma’s en instellingen worden '
          'overschreven door het gekozen bestand. Dit kan niet ongedaan '
          'gemaakt worden.',
      confirmLabel: 'Kiezen & vervangen',
    );
    if (!ok || !context.mounted) return;

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
    final ok = await confirmDialog(
      context,
      title: 'Alle gegevens wissen?',
      message:
          'Al je trainingen, eigen programma’s en instellingen worden gewist. '
          'De oefeningendatabase en de standaardschema’s blijven. Dit kan niet '
          'ongedaan gemaakt worden.',
      confirmLabel: 'Wissen',
      destructive: true,
    );
    if (!ok || !context.mounted) return;

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

}

class _PercentRow extends StatelessWidget {
  const _PercentRow({
    required this.label,
    required this.subtitle,
    required this.percent,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final int percent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            onPressed: percent > -50 ? () => onChanged(percent - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 52,
            child: Text('$percent%', textAlign: TextAlign.center),
          ),
          IconButton.filledTonal(
            onPressed: percent < 50 ? () => onChanged(percent + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
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
