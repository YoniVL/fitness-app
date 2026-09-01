import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/workout_session_repository.dart';

/// State of the between-sets rest timer.
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

/// Counts down the rest between sets. Duration is caller-supplied (per exercise,
/// defaulting to the user's `default_rest_seconds`). No per-stroke or per-second
/// nagging — just the countdown and a single cue when it hits zero.
class RestTimerNotifier extends StateNotifier<RestTimerState> {
  RestTimerNotifier(this._ref) : super(RestTimerState.idle);

  final Ref _ref;
  Timer? _ticker;

  void start(int seconds, {int? forSetId}) {
    _ticker?.cancel();
    state = RestTimerState(
      active: true,
      totalSeconds: seconds,
      remainingSeconds: seconds,
      forSetId: forSetId,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final remaining = state.remainingSeconds - 1;
    if (remaining <= 0) {
      _cue();
      _persistRest(state.totalSeconds);
      _ticker?.cancel();
      state = state.copyWith(active: false, remainingSeconds: 0);
    } else {
      state = state.copyWith(remainingSeconds: remaining);
    }
  }

  void addSeconds(int delta) {
    if (!state.active) return;
    state = state.copyWith(
      totalSeconds: state.totalSeconds + delta,
      remainingSeconds: state.remainingSeconds + delta,
    );
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
    await _ref.read(workoutSessionRepositoryProvider).setRestForSet(setId, seconds);
  }

  void _cue() {
    // Minimal cue only. A real countdown beep lands with the rowing iteratie
    // (audioplayers); for now a haptic pulse. Skip entirely when there's no
    // Flutter binding (unit tests) and swallow platform failures.
    if (!_bindingReady) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {
      // ignored
    }
  }

  bool get _bindingReady {
    try {
      // The `instance` getter throws until a Flutter binding is initialized.
      return ServicesBinding.instance.hashCode != 0;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final restTimerProvider =
    StateNotifierProvider<RestTimerNotifier, RestTimerState>(
  (ref) => RestTimerNotifier(ref),
);
