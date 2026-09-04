import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import 'ble/ble_rower_service.dart';

/// Live snapshot from the rower. Fields are null until the trainer reports them;
/// the BLE service keeps the last-known value per field (FTMS sends partial
/// frames). Over BLE, `distanceM` / `energyKcal` are left null — the trainer's
/// own totals are unreliable, so [ActiveRowingController] integrates them from
/// the split and power instead.
class RowerSnapshot {
  const RowerSnapshot({
    this.strokeRate,
    this.strokeCount,
    this.distanceM,
    this.paceSec500m,
    this.powerW,
    this.energyKcal,
    this.heartRate,
    this.elapsedSeconds,
  });

  final double? strokeRate;
  final int? strokeCount;
  final double? distanceM;
  final double? paceSec500m;
  final double? powerW;
  final double? energyKcal;
  final int? heartRate;
  final int? elapsedSeconds;
}

enum RowerConnectionStatus { disconnected, connecting, connected, demo }

/// Source of live rowing data: [BleRowerService] (a real FTMS trainer) or
/// [FakeRowerService] (the simulated demo mode).
abstract class RowerService {
  Stream<RowerSnapshot> get snapshots;
  RowerConnectionStatus get status;
  Stream<RowerConnectionStatus> get statusStream;

  Future<void> connect();
  Future<void> disconnect();
  void dispose();
}

/// A believable rowing simulation — pace wanders around a target, distance
/// accumulates, stroke rate and power track along. Used for development and for
/// the hidden "demo mode".
class FakeRowerService implements RowerService {
  FakeRowerService();

  final _snapshots = StreamController<RowerSnapshot>.broadcast();
  final _statusCtrl = StreamController<RowerConnectionStatus>.broadcast();
  final _rng = Random();

  Timer? _timer;
  RowerConnectionStatus _status = RowerConnectionStatus.disconnected;

  double _distance = 0;
  int _elapsed = 0;
  int _strokes = 0;
  double _pace = 135; // sec / 500 m
  double _energy = 0;

  @override
  Stream<RowerSnapshot> get snapshots => _snapshots.stream;

  @override
  RowerConnectionStatus get status => _status;

  @override
  Stream<RowerConnectionStatus> get statusStream => _statusCtrl.stream;

  @override
  Future<void> connect() async {
    _set(RowerConnectionStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _set(RowerConnectionStatus.demo);
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _set(RowerConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _snapshots.close();
    _statusCtrl.close();
  }

  void _set(RowerConnectionStatus s) {
    _status = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  void _tick() {
    _elapsed += 1;
    // Simulate the rower stopping for ~12 s every ~45 s so the app's
    // "no data → auto-pause" path is visible in the demo.
    if (_elapsed > 20 && _elapsed % 45 >= 33) return;
    // Pace drifts, mean-reverting to ~2:15.
    _pace += (_rng.nextDouble() - 0.5) * 4 + (135 - _pace) * 0.05;
    _pace = _pace.clamp(95, 175);
    final speed = 500 / _pace; // m/s
    _distance += speed;
    final spm = 22 + (135 - _pace) / 6 + (_rng.nextDouble() - 0.5) * 2;
    if (_elapsed % 2 == 0) _strokes += (spm / 30).round();
    final power = 2.8 / pow(_pace / 500, 3);
    _energy += power / 4184 * 1; // rough kcal/s

    if (_snapshots.isClosed) return;
    _snapshots.add(RowerSnapshot(
      strokeRate: spm,
      strokeCount: _strokes,
      distanceM: _distance,
      paceSec500m: _pace,
      powerW: power,
      energyKcal: _energy,
      heartRate: 120 + (175 - _pace).round().clamp(0, 60),
      elapsedSeconds: _elapsed,
    ));
  }
}

/// Whether the hidden demo mode is on — then the simulated rower is used
/// instead of the real Bluetooth trainer.
final rowingDemoModeProvider = FutureProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).rowingDemoMode(),
);

/// The active rower data source: the real [BleRowerService], or
/// [FakeRowerService] when demo mode is on. Only rebuilds when the *resolved*
/// demo flag flips — not on the initial loading→data transition, which would
/// otherwise dispose a service mid-session.
final rowerServiceProvider = Provider<RowerService>((ref) {
  final demo = ref.watch(
      rowingDemoModeProvider.select((v) => v.valueOrNull ?? false));
  final RowerService service =
      demo ? FakeRowerService() : BleRowerService(ref);
  ref.onDispose(service.dispose);
  return service;
});

final rowerStatusProvider = StreamProvider<RowerConnectionStatus>((ref) {
  final svc = ref.watch(rowerServiceProvider);
  return svc.statusStream;
});
