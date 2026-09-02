import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// A short-lived foreground service that runs while a rest timer is counting
/// down. It keeps the Dart isolate alive and the app "foreground" so the
/// in-app countdown and its alarm-stream beep keep working — and are audible —
/// even after the user leaves the app. Its notification shows the live count.
///
/// Every method is safe to call before/without [init] and outside Android
/// (no-ops), so tests are unaffected.
class RestForegroundService {
  RestForegroundService._();
  static final RestForegroundService instance = RestForegroundService._();

  bool _inited = false;

  void init() {
    if (_inited) return;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'rest_running',
          channelName: 'Rustpauze',
          channelDescription: 'Toont de resterende rusttijd tijdens een sessie',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );
      _inited = true;
    } catch (e) {
      debugPrint('[RestFgService] init failed: $e');
    }
  }

  Future<void> start(String countdown) async {
    if (!_inited) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Rustpauze',
          notificationText: countdown,
        );
        return;
      }
      await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.specialUse],
        notificationTitle: 'Rustpauze',
        notificationText: countdown,
      );
    } catch (e) {
      debugPrint('[RestFgService] start failed: $e');
    }
  }

  Future<void> update(String countdown) async {
    if (!_inited) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Rustpauze',
          notificationText: countdown,
        );
      }
    } catch (e) {
      debugPrint('[RestFgService] update failed: $e');
    }
  }

  Future<void> stop() async {
    if (!_inited) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('[RestFgService] stop failed: $e');
    }
  }
}
