import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ftms/flutter_ftms.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/settings_repository.dart';
import '../rower_service.dart';

/// Live rowing data over Bluetooth LE (FTMS "Rower Data" characteristic).
///
/// FTMS sends partial frames, so the last-known value per field is kept and
/// re-emitted on every update. These trainers advertise a rotating random
/// address, so reconnection works by scanning for the saved *name* rather than
/// trusting a stored MAC.
class BleRowerService implements RowerService {
  BleRowerService(this._ref);

  final Ref _ref;

  final _snapshots = StreamController<RowerSnapshot>.broadcast();
  final _statusCtrl = StreamController<RowerConnectionStatus>.broadcast();
  RowerConnectionStatus _status = RowerConnectionStatus.disconnected;

  BluetoothDevice? _device;
  String? _wantName;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _retry;
  bool _disposed = false;
  bool _dataSubscribed = false;
  bool _wantConnected = false;

  double? _strokeRate;
  int? _strokeCount;
  double? _distanceM;
  double? _paceSec500m;
  double? _powerW;
  double? _energyKcal;
  int? _heartRate;
  int? _elapsedSeconds;

  @override
  Stream<RowerSnapshot> get snapshots => _snapshots.stream;

  @override
  RowerConnectionStatus get status => _status;

  @override
  Stream<RowerConnectionStatus> get statusStream => _statusCtrl.stream;

  void _set(RowerConnectionStatus s) {
    if (_status == s) return;
    _status = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  SettingsRepository get _settings => _ref.read(settingsRepositoryProvider);

  Future<bool> get hasPairedDevice async =>
      (await _settings.getString(SettingsKeys.rowingDeviceName)) != null;

  Future<String?> get pairedDeviceName =>
      _settings.getString(SettingsKeys.rowingDeviceName);

  @override
  Future<void> connect() async {
    final name = await _settings.getString(SettingsKeys.rowingDeviceName);
    if (name == null || _disposed) {
      _set(RowerConnectionStatus.disconnected);
      return;
    }
    _wantName = name;
    _wantConnected = true;
    if (_status == RowerConnectionStatus.connected) {
      await _subscribeData();
      return;
    }
    if (_status != RowerConnectionStatus.connecting) _findAndConnect();
  }

  /// Pair with a device found by the connect sheet: remember it, then connect.
  Future<void> pair(BluetoothDevice device, String name) async {
    final label = name.isEmpty ? 'Roeitrainer' : name;
    await _settings.set(SettingsKeys.rowingDeviceId, device.remoteId.str);
    await _settings.set(SettingsKeys.rowingDeviceName, label);
    await _settings.setBool(SettingsKeys.rowingDemoMode, false);
    _wantName = label;
    _wantConnected = true;
    await _attach(device);
  }

  Future<void> forget() async {
    await _settings.remove(SettingsKeys.rowingDeviceId);
    await _settings.remove(SettingsKeys.rowingDeviceName);
    await disconnect();
  }

  String _nameOf(ScanResult r) => r.device.platformName.isNotEmpty
      ? r.device.platformName
      : r.advertisementData.advName;

  /// Scan briefly for the saved trainer (its address rotates) and connect to
  /// whatever address it currently advertises.
  Future<void> _findAndConnect() async {
    if (!_wantConnected || _disposed) return;
    _set(RowerConnectionStatus.connecting);

    // Fast path: try the last address we saw it on.
    final lastId = await _settings.getString(SettingsKeys.rowingDeviceId);
    if (lastId != null) {
      await _attach(BluetoothDevice.fromId(lastId));
      // Give the direct connect a few seconds before falling back to a scan.
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 6), () {
        if (_status != RowerConnectionStatus.connected) _scanThenConnect();
      });
      return;
    }
    _scanThenConnect();
  }

  Future<void> _scanThenConnect() async {
    if (!_wantConnected || _disposed) return;
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      final completer = Completer<BluetoothDevice>();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (_nameOf(r) == _wantName && !completer.isCompleted) {
            completer.complete(r.device);
          }
        }
      });
      await FlutterBluePlus.startScan(
        withServices: const [],
        timeout: const Duration(seconds: 12),
      );
      final device = await completer.future
          .timeout(const Duration(seconds: 12), onTimeout: () => throw '');
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      await _attach(device);
    } catch (_) {
      if (_wantConnected && !_disposed) {
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 4), _findAndConnect);
      }
    }
  }

  Future<void> _attach(BluetoothDevice device) async {
    _device = device;
    _dataSubscribed = false;
    _set(RowerConnectionStatus.connecting);
    await _connSub?.cancel();
    _connSub = device.connectionState.listen(_onConnectionState);
    device.connect(license: License.nonprofit, autoConnect: false).then(
        (_) {}, onError: (e) => debugPrint('[BleRower] connect() failed: $e'));
  }

  void _onConnectionState(BluetoothConnectionState state) {
    if (_disposed) return;
    if (state == BluetoothConnectionState.connected) {
      _retry?.cancel();
      // Persist the address we actually connected on.
      final d = _device;
      if (d != null) {
        _settings.set(SettingsKeys.rowingDeviceId, d.remoteId.str);
      }
      _set(RowerConnectionStatus.connected);
      _subscribeData();
    } else {
      _dataSubscribed = false;
      if (_wantConnected) {
        _set(RowerConnectionStatus.connecting);
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 3), _findAndConnect);
      } else {
        _set(RowerConnectionStatus.disconnected);
      }
    }
  }

  Future<void> _subscribeData() async {
    if (_dataSubscribed || _device == null) return;
    _dataSubscribed = true;
    try {
      await FTMS.useDeviceDataCharacteristic(
        _device!,
        _onData,
        preferredDeviceDataType: DeviceDataType.rower,
      );
    } catch (e) {
      _dataSubscribed = false;
      debugPrint('[BleRower] data subscribe failed: $e');
    }
  }

  void _onData(DeviceData data) {
    if (_disposed) return;
    double? read(dynamic name) {
      final p = data.getParameterValueByName(name);
      return p == null ? null : (p.value * p.factor).toDouble();
    }

    // 0xFFFF / 0xFF are FTMS "field absent" sentinels.
    double? sane(double? v, {double max = 65534}) =>
        (v == null || v >= max) ? null : v;

    _strokeRate = sane(read(DeviceDataParameterName.strokeRate)) ?? _strokeRate;
    final sc = sane(read(DeviceDataParameterName.strokeCount));
    if (sc != null) _strokeCount = sc.round();
    _distanceM = sane(read(DeviceDataParameterName.totalDistance)) ?? _distanceM;
    final pace = sane(read(DeviceDataParameterName.instPace));
    if (pace != null && pace > 0 && pace < 600) _paceSec500m = pace;
    _powerW = sane(read(DeviceDataParameterName.instPower)) ?? _powerW;
    _energyKcal =
        sane(read(DeviceDataParameterName.totalEnergy)) ?? _energyKcal;
    final hr = sane(read(DeviceDataParameterName.heartRate), max: 254);
    if (hr != null && hr > 0) _heartRate = hr.round();
    final et = sane(read(DeviceDataParameterName.elapsedTime));
    if (et != null) _elapsedSeconds = et.round();

    if (_snapshots.isClosed) return;
    _snapshots.add(RowerSnapshot(
      strokeRate: _strokeRate,
      strokeCount: _strokeCount,
      distanceM: _distanceM,
      paceSec500m: _paceSec500m,
      powerW: _powerW,
      energyKcal: _energyKcal,
      heartRate: _heartRate,
      elapsedSeconds: _elapsedSeconds,
    ));
  }

  @override
  Future<void> disconnect() async {
    _wantConnected = false;
    _retry?.cancel();
    await _scanSub?.cancel();
    await _connSub?.cancel();
    _connSub = null;
    _dataSubscribed = false;
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      await _device?.disconnect();
    } catch (_) {}
    _set(RowerConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    _disposed = true;
    _wantConnected = false;
    _retry?.cancel();
    _scanSub?.cancel();
    _connSub?.cancel();
    try {
      _device?.disconnect();
    } catch (_) {}
    _snapshots.close();
    _statusCtrl.close();
  }
}
