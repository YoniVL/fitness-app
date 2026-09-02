import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Schedules a single system notification for when the rest timer runs out, so
/// the beep still lands when the app is backgrounded or the screen is off.
///
/// Every method is a no-op until [init] has succeeded, so unit tests that never
/// call [init] (no plugin registered) are unaffected.
class RestNotifications {
  RestNotifications._();
  static final RestNotifications instance = RestNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const int _notificationId = 42;

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        const InitializationSettings(android: android),
      );
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      await androidImpl?.requestExactAlarmsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('[RestNotifications] init failed: $e');
    }
  }

  /// (Re)schedule the "rest over" notification [seconds] from now.
  Future<void> scheduleIn(int seconds) async {
    if (!_ready || seconds <= 0) return;
    try {
      final when =
          tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
      await _plugin.zonedSchedule(
        _notificationId,
        'Rust voorbij',
        'Tijd voor je volgende set.',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'rest_timer',
            'Rusttimer',
            channelDescription: 'Melding wanneer de rustpauze afgelopen is',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            // Play on the alarm stream so it still sounds on silent/DND.
            audioAttributesUsage: AudioAttributesUsage.alarm,
            playSound: true,
            enableVibration: true,
            timeoutAfter: 60000,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[RestNotifications] schedule failed: $e');
    }
  }

  Future<void> cancel() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_notificationId);
    } catch (e) {
      debugPrint('[RestNotifications] cancel failed: $e');
    }
  }
}
