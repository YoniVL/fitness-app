import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ftms/flutter_ftms.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/settings_repository.dart';
import '../rower_service.dart';
import 'ble_rower_service.dart';

Future<void> showConnectRowerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _ConnectSheet(),
  );
}

class _ConnectSheet extends ConsumerStatefulWidget {
  const _ConnectSheet();

  @override
  ConsumerState<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends ConsumerState<_ConnectSheet> {
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  List<ScanResult> _results = const [];
  bool _scanning = false;
  bool _adapterOn = FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
  String? _error;

  @override
  void initState() {
    super.initState();
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      if (mounted) setState(() => _adapterOn = s == BluetoothAdapterState.on);
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _adapterSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _scan() async {
    final svc = ref.read(rowerServiceProvider);
    if (svc is! BleRowerService) {
      setState(() => _error = 'Demo-modus staat aan — zet die eerst uit.');
      return;
    }
    if (!_adapterOn) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        setState(() => _error = 'Zet Bluetooth aan om te zoeken.');
        return;
      }
    }
    setState(() {
      _error = null;
      _scanning = true;
      _results = const [];
    });
    _scanSub?.cancel();
    _scanSub = FTMS.scanResults.listen((r) {
      if (mounted) setState(() => _results = r);
    });
    try {
      await FTMS.scanForBluetoothDevices();
    } catch (e) {
      if (mounted) setState(() => _error = 'Zoeken mislukt: $e');
    }
    // The scan runs ~4 s; reflect that it stopped.
    await Future<void>.delayed(const Duration(seconds: 5));
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _pick(ScanResult r) async {
    final svc = ref.read(rowerServiceProvider);
    if (svc is! BleRowerService) return;
    final name = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : (r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : 'Roeitrainer');
    await FlutterBluePlus.stopScan();
    await svc.pair(r.device, name);
    ref.invalidate(rowingDeviceNameProvider);
    ref.invalidate(rowingDemoModeProvider);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _forget() async {
    final svc = ref.read(rowerServiceProvider);
    if (svc is BleRowerService) await svc.forget();
    ref.invalidate(rowingDeviceNameProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pairedName = ref.watch(rowingDeviceNameProvider).valueOrNull;
    final status = ref.watch(rowerStatusProvider).valueOrNull;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Roeitrainer', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Koppel je FTMS-roeitrainer via Bluetooth. Zet de trainer aan en '
              'begin te roeien zodat hij zichtbaar wordt.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (pairedName != null)
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    status == RowerConnectionStatus.connected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth,
                    color: status == RowerConnectionStatus.connected
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  title: Text(pairedName),
                  subtitle: Text(switch (status) {
                    RowerConnectionStatus.connected => 'Verbonden',
                    RowerConnectionStatus.connecting => 'Verbinden…',
                    _ => 'Niet verbonden',
                  }),
                  trailing: TextButton(
                    onPressed: _forget,
                    child: const Text('Vergeten'),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_scanning ? 'Zoeken…' : 'Zoek trainers'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: _results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        _scanning
                            ? 'Zoeken naar trainers…'
                            : 'Nog geen trainers gevonden.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in _results)
                          ListTile(
                            leading: const Icon(Icons.rowing),
                            title: Text(r.device.platformName.isNotEmpty
                                ? r.device.platformName
                                : (r.advertisementData.advName.isNotEmpty
                                    ? r.advertisementData.advName
                                    : r.device.remoteId.str)),
                            subtitle: Text('${r.rssi} dBm'),
                            onTap: () => _pick(r),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The paired trainer's display name, or null.
final rowingDeviceNameProvider = FutureProvider<String?>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .getString(SettingsKeys.rowingDeviceName),
);
