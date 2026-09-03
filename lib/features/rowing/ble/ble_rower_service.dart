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
/// re-emitted on every update. `autoConnect` lets flutter_blue_plus re-establish
/// the link on its own when the trainer drops out or is switched off and on.
class BleRowerService implements RowerService {
  BleRowerService(this._ref);

  final Ref _ref;

  final _snapshots = StreamController<RowerSnapshot>.broadcast();
  final _statusCtrl = StreamController<RowerConnectionStatus>.broadcast();
  RowerConnectionStatus _status = RowerConnectionStatus.disconnected;

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _disposed = false;
  bool _dataSubscribed = false;

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

  /// Whether a trainer has been paired (so a session should try to connect).
  Future<bool> get hasPairedDevice async =>
      (await _settings.getString(SettingsKeys.rowingDeviceId)) != null;

  Future<String?> get pairedDeviceName =>
      _settings.getString(SettingsKeys.rowingDeviceName);

  @override
  Future<void> connect() async {
    final id = await _settings.getString(SettingsKeys.rowingDeviceId);
    if (id == null || _disposed) {
      _set(RowerConnectionStatus.disconnected);
      return;
    }
    await _attach(BluetoothDevice.fromId(id));
  }

  /// Pair with a device found by the connect sheet: remember it, then connect.
  Future<void> pair(BluetoothDevice device, String name) async {
    await _settings.set(SettingsKeys.rowingDeviceId, device.remoteId.str);
    await _settings.set(SettingsKeys.rowingDeviceName,
        name.isEmpty ? 'Roeitrainer' : name);
    // A real trainer is now paired — leave demo mode.
    await _settings.setBool(SettingsKeys.rowingDemoMode, false);
    await _attach(device);
  }

  Future<void> forget() async {
    await _settings.remove(SettingsKeys.rowingDeviceId);
    await _settings.remove(SettingsKeys.rowingDeviceName);
    await disconnect();
  }

  Future<void> _attach(BluetoothDevice device) async {
    _device = device;
    _dataSubscribed = false;
    _set(RowerConnectionStatus.connecting);
    await _connSub?.cancel();
    _connSub = device.connectionState.listen(_onConnectionState);
    try {
      await device.connect(
          license: License.nonprofit, autoConnect: true, mtu: null);
    } catch (e) {
      debugPrint('[BleRower] connect() threw: $e');
    }
  }

  void _onConnectionState(BluetoothConnectionState state) {
    if (_disposed) return;
    if (state == BluetoothConnectionState.connected) {
      _set(RowerConnectionStatus.connected);
      _subscribeData();
    } else {
      _dataSubscribed = false;
      // autoConnect keeps retrying under the hood.
      _set(RowerConnectionStatus.connecting);
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
    // `ParameterName` isn't exported by flutter_ftms, so the field is passed
    // through dynamically.
    double? read(dynamic name) {
      final p = data.getParameterValueByName(name);
      return p == null ? null : (p.value * p.factor).toDouble();
    }

    _strokeRate = read(DeviceDataParameterName.strokeRate) ?? _strokeRate;
    final sc = read(DeviceDataParameterName.strokeCount);
    if (sc != null) _strokeCount = sc.round();
    _distanceM = read(DeviceDataParameterName.totalDistance) ?? _distanceM;
    final pace = read(DeviceDataParameterName.instPace);
    if (pace != null && pace > 0 && pace < 600) _paceSec500m = pace;
    _powerW = read(DeviceDataParameterName.instPower) ?? _powerW;
    _energyKcal = read(DeviceDataParameterName.totalEnergy) ?? _energyKcal;
    final hr = read(DeviceDataParameterName.heartRate);
    if (hr != null && hr > 0) _heartRate = hr.round();
    final et = read(DeviceDataParameterName.elapsedTime);
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
    await _connSub?.cancel();
    _connSub = null;
    _dataSubscribed = false;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _set(RowerConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    _disposed = true;
    _connSub?.cancel();
    try {
      _device?.disconnect();
    } catch (_) {}
    _snapshots.close();
    _statusCtrl.close();
  }
}
