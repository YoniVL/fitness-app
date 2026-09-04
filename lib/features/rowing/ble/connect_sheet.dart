import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../data/repositories/settings_repository.dart';
import '../rower_service.dart';
import 'ble_rower_service.dart';

/// Opens the trainer-pairing sheet. Returns when it is dismissed.
Future<void> showConnectRowerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _ConnectSheet(),
  );
}

/// Before a rowing session: in demo mode or with a link already up, do nothing.
/// With a trainer paired, kick off the (re)connection and carry on — the live
/// screen shows the status. With no trainer paired, open the pairing sheet
/// (which also lets the user continue without one).
Future<void> ensureRowerConnected(BuildContext context, WidgetRef ref) async {
  final demo = ref.read(rowingDemoModeProvider).valueOrNull ?? false;
  if (demo) return;
  final svc = ref.read(rowerServiceProvider);
  if (svc is! BleRowerService) return;
  if (svc.status != RowerConnectionStatus.disconnected) return;
  if (await svc.hasPairedDevice) {
    unawaited(svc.connect());
    return;
  }
  if (context.mounted) await showConnectRowerSheet(context, ref);
}

class _ConnectSheet extends ConsumerStatefulWidget {
  const _ConnectSheet();

  @override
  ConsumerState<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends ConsumerState<_ConnectSheet> {
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  final Map<DeviceIdentifier, ScanResult> _found = {};
  bool _scanning = false;
  bool _adapterOn = FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
  String? _error;

  @override
  void initState() {
    super.initState();
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      final on = s == BluetoothAdapterState.on;
      if (mounted) setState(() => _adapterOn = on);
      if (on && _found.isEmpty && !_scanning) _scan();
    });
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        for (final r in results) {
          if (_name(r).isNotEmpty) _found[r.device.remoteId] = r;
        }
      });
    });
    _scan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _adapterSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  String _name(ScanResult r) => r.device.platformName.isNotEmpty
      ? r.device.platformName
      : r.advertisementData.advName;

  Future<void> _scan() async {
    if (ref.read(rowerServiceProvider) is! BleRowerService) {
      setState(() => _error = 'Demo-modus staat aan — zet die eerst uit.');
      return;
    }
    setState(() {
      _error = null;
      _scanning = true;
      _found.clear(); // drop stale results / RSSI from the previous pass
    });
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      if (!_adapterOn) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 6));
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(
        withServices: const [],
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Zet Bluetooth aan om te zoeken.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Zoeken mislukt: $e');
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _pick(ScanResult r) async {
    final svc = ref.read(rowerServiceProvider);
    if (svc is! BleRowerService) return;
    await FlutterBluePlus.stopScan();
    await svc.pair(r.device, _name(r));
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
    // The paired trainer has its own card above — don't list it twice.
    final devices = _found.values
        .where((r) => _name(r) != pairedName)
        .toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 8 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Roeitrainer koppelen',
                          style: theme.textTheme.titleLarge)),
                  if (_scanning)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      onPressed: _scan,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Opnieuw zoeken',
                    ),
                ],
              ),
              Text(
                'Zet je FTMS-roeitrainer aan; hij verschijnt hier vanzelf.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (pairedName != null)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
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
                              child: const Text('Vergeten')),
                        ),
                      ),
                    if (devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            _scanning
                                ? 'Zoeken naar trainers…'
                                : 'Geen toestellen gevonden.\n'
                                    'Staat je trainer aan?',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      for (final r in devices)
                        ListTile(
                          leading: const Icon(Icons.rowing),
                          title: Text(_name(r)),
                          subtitle: Text('${r.rssi} dBm'),
                          onTap: () => _pick(r),
                        ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Later koppelen'),
                ),
              ),
            ],
          ),
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
