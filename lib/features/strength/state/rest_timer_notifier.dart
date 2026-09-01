import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/workout_session_repository.dart';

/// State of the between-sets / after-exercise rest timer.
class RestTimerState {
  const RestTimerState({
    this.active = false,
    this.totalSeconds = 0,
    this.remainingSeconds = 0,
    this.forSetId,
  });

  final bool active;
  final int totalSeconds;
  final int remainingSeconds;

  /// The set this rest follows; its `rest_seconds` is written when the timer
  /// ends or is skipped.
  final int? forSetId;

  int get elapsedSeconds => totalSeconds - remainingSeconds;
  double get progress => totalSeconds == 0 ? 0 : elapsedSeconds / totalSeconds;

  static const idle = RestTimerState();

  RestTimerState copyWith({
    bool? active,
    int? totalSeconds,
    int? remainingSeconds,
    int? forSetId,
  }) =>
      RestTimerState(
        active: active ?? this.active,
        totalSeconds: totalSeconds ?? this.totalSeconds,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        forSetId: forSetId ?? this.forSetId,
      );
}

/// Counts down the rest. Beeps every second for the last 5 seconds and a longer
/// tone at zero (gated on the `rest_timer_sound` setting).
class RestTimerNotifier extends StateNotifier<RestTimerState> {
  RestTimerNotifier(this._ref) : super(RestTimerState.idle);

  final Ref _ref;
  Timer? _ticker;
  bool _soundOn = true;

  AudioPlayer? _beep;
  AudioPlayer? _beepFinal;

  AudioPlayer _player(String asset) {
    final p = AudioPlayer();
    p.setReleaseMode(ReleaseMode.stop).catchError((_) {});
    p.setPlayerMode(PlayerMode.lowLatency).catchError((_) {});
    p.setSource(AssetSource(asset)).catchError((_) {});
    return p;
  }

  void start(int seconds, {int? forSetId}) {
    _ticker?.cancel();
    state = RestTimerState(
      active: true,
      totalSeconds: seconds,
      remainingSeconds: seconds,
      forSetId: forSetId,
    );
    _prepareSound();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _prepareSound() async {
    try {
      _soundOn = await _ref
          .read(settingsRepositoryProvider)
          .getBool(SettingsKeys.restTimerSound, true);
    } catch (_) {
      _soundOn = false; // no DB (tests) — stay silent
      return;
    }
    if (!_soundOn || !_bindingReady) return;
    try {
      _beep ??= _player('audio/beep.wav');
      _beepFinal ??= _player('audio/beep_final.wav');
    } catch (_) {
      _soundOn = false;
    }
  }

  void _tick() {
    final remaining = state.remainingSeconds - 1;
    if (remaining <= 0) {
      _cue();
      _playFinal();
      _persistRest(state.totalSeconds);
      _ticker?.cancel();
      state = state.copyWith(active: false, remainingSeconds: 0);
    } else {
      if (remaining <= 5) _playBeep();
      state = state.copyWith(remainingSeconds: remaining);
    }
  }

  /// Adjust the running timer by [delta] seconds (may be negative). If the
  /// remaining time drops to zero or less, the rest ends immediately.
  void addSeconds(int delta) {
    if (!state.active) return;
    final total = (state.totalSeconds + delta).clamp(5, 3600);
    final remaining = state.remainingSeconds + delta;
    if (remaining <= 0) {
      _ticker?.cancel();
      _persistRest(state.elapsedSeconds);
      state = RestTimerState.idle;
      return;
    }
    state = state.copyWith(totalSeconds: total, remainingSeconds: remaining);
  }

  void skip() {
    if (!state.active) return;
    _ticker?.cancel();
    _persistRest(state.elapsedSeconds);
    state = RestTimerState.idle;
  }

  void cancel() {
    _ticker?.cancel();
    state = RestTimerState.idle;
  }

  Future<void> _persistRest(int seconds) async {
    final setId = state.forSetId;
    if (setId == null) return;
    await _ref
        .read(workoutSessionRepositoryProvider)
        .setRestForSet(setId, seconds);
  }

  void _playBeep() => _play(_beep);
  void _playFinal() => _play(_beepFinal);

  void _play(AudioPlayer? p) {
    if (!_soundOn || p == null) return;
    try {
      p.stop().catchError((_) {});
      p.resume().catchError((_) {});
    } catch (_) {}
  }

  void _cue() {
    if (!_bindingReady) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  bool get _bindingReady {
    try {
      return ServicesBinding.instance.hashCode != 0;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _beep?.dispose();
    _beepFinal?.dispose();
    super.dispose();
  }
}

final restTimerProvider =
    StateNotifierProvider<RestTimerNotifier, RestTimerState>(
  (ref) => RestTimerNotifier(ref),
);
