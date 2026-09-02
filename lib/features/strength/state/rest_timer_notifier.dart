import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/workout_session_repository.dart';
import '../../../services/rest_foreground_service.dart';

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

String _mmss(int s) {
  final v = s < 0 ? 0 : s;
  return '${(v ~/ 60).toString().padLeft(2, '0')}:'
      '${(v % 60).toString().padLeft(2, '0')}';
}

/// Counts down the rest. A foreground service keeps this ticking (and its beeps
/// audible) after the user leaves the app; it beeps every second for the last
/// 5 seconds and a longer tone at zero (gated on the `rest_timer_sound` setting).
class RestTimerNotifier extends StateNotifier<RestTimerState> {
  RestTimerNotifier(this._ref) : super(RestTimerState.idle);

  final Ref _ref;
  Timer? _ticker;
  bool _soundOn = true;

  /// Absolute moment the current rest ends — lets [reconcile] correct any drift.
  DateTime? _endAt;

  AudioPlayer? _beep;
  AudioPlayer? _beepFinal;

  /// Audio routing (alarm stream) is set once globally in `main()`.
  AudioPlayer _player() => AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop).catchError((e) {
      debugPrint('[RestTimer] setReleaseMode failed: $e');
    });

  void start(int seconds, {int? forSetId}) {
    _ticker?.cancel();
    _endAt = DateTime.now().add(Duration(seconds: seconds));
    state = RestTimerState(
      active: true,
      totalSeconds: seconds,
      remainingSeconds: seconds,
      forSetId: forSetId,
    );
    _prepareSound();
    RestForegroundService.instance.start(_mmss(seconds));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Re-syncs the countdown with wall-clock time — e.g. after the OS briefly
  /// froze the ticker despite the foreground service.
  void reconcile() {
    if (!state.active || _endAt == null) {
      _endAt = null;
      return;
    }
    final remaining = _endAt!.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _finish();
    } else {
      state = state.copyWith(remainingSeconds: remaining);
      RestForegroundService.instance.update(_mmss(remaining));
    }
  }

  void _finish() {
    _ticker?.cancel();
    _persistRest(state.totalSeconds);
    _cue();
    _playFinal();
    RestForegroundService.instance.stop();
    _endAt = null;
    state = state.copyWith(active: false, remainingSeconds: 0);
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
      _beep ??= _player();
      _beepFinal ??= _player();
    } catch (e) {
      debugPrint('[RestTimer] could not create audio players: $e');
      _soundOn = false;
    }
  }

  void _tick() {
    final remaining = state.remainingSeconds - 1;
    if (remaining <= 0) {
      _finish();
    } else {
      if (remaining <= 5) _playBeep();
      state = state.copyWith(remainingSeconds: remaining);
      RestForegroundService.instance.update(_mmss(remaining));
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
      RestForegroundService.instance.stop();
      _endAt = null;
      state = RestTimerState.idle;
      return;
    }
    _endAt = DateTime.now().add(Duration(seconds: remaining));
    state = state.copyWith(totalSeconds: total, remainingSeconds: remaining);
    RestForegroundService.instance.update(_mmss(remaining));
  }

  void skip() {
    if (!state.active) return;
    _ticker?.cancel();
    _persistRest(state.elapsedSeconds);
    RestForegroundService.instance.stop();
    _endAt = null;
    state = RestTimerState.idle;
  }

  void cancel() {
    _ticker?.cancel();
    RestForegroundService.instance.stop();
    _endAt = null;
    state = RestTimerState.idle;
  }

  Future<void> _persistRest(int seconds) async {
    final setId = state.forSetId;
    if (setId == null) return;
    await _ref
        .read(workoutSessionRepositoryProvider)
        .setRestForSet(setId, seconds);
  }

  void _playBeep() => _play(_beep, 'audio/beep.wav');
  void _playFinal() => _play(_beepFinal, 'audio/beep_final.wav');

  void _play(AudioPlayer? p, String asset) {
    if (!_soundOn || p == null) return;
    try {
      p.play(AssetSource(asset)).catchError((e) {
        debugPrint('[RestTimer] play($asset) failed: $e');
      });
    } catch (e) {
      debugPrint('[RestTimer] play($asset) threw: $e');
    }
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
    RestForegroundService.instance.stop();
    _beep?.dispose();
    _beepFinal?.dispose();
    super.dispose();
  }
}

final restTimerProvider =
    StateNotifierProvider<RestTimerNotifier, RestTimerState>(
  (ref) => RestTimerNotifier(ref),
);
