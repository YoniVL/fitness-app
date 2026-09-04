import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';

/// Short audible cues for the live rowing screen: a single beep ~10 s before a
/// segment ends, a double beep at the switch. No vibration, no notification —
/// the beep only (see the iteration-5 plan). Audio routing (alarm stream) is set
/// once globally in `main()`.
class RowingCues {
  RowingCues({required this.enabled});

  /// Whether the beep is on — from `SettingsKeys.rowingCueSound`. The provider
  /// rebuilds this object when the Settings toggle changes.
  final bool enabled;

  AudioPlayer? _player;
  bool _prepared = false;

  Future<void> _prepare() async {
    if (_prepared || !enabled) return;
    _prepared = true;
    try {
      _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      debugPrint('[RowingCues] audio init failed: $e');
    }
  }

  Future<void> _beep() async {
    if (!enabled) return;
    await _prepare();
    final p = _player;
    if (p == null) return;
    try {
      await p.stop();
      await p.play(AssetSource('audio/beep.wav'));
    } catch (e) {
      debugPrint('[RowingCues] beep failed: $e');
    }
  }

  /// ~10 s before a segment ends.
  void preSwitch() => _beep();

  /// At a segment change: two quick beeps.
  Future<void> onSwitch() async {
    await _beep();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await _beep();
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}

final rowingCuesProvider = Provider<RowingCues>((ref) {
  final enabled = ref.watch(rowingCueSoundProvider).valueOrNull ?? true;
  final cues = RowingCues(enabled: enabled);
  ref.onDispose(cues.dispose);
  return cues;
});

/// Whether the segment-change beep is on. Toggled in Settings.
final rowingCueSoundProvider = FutureProvider<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .getBool(SettingsKeys.rowingCueSound, true),
);
