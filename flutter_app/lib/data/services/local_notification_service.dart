import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/bus_schedule.dart';
import '../../domain/entities/notification_settings.dart';
import '../../domain/services/notification_service.dart';

class LocalNotificationService implements NotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onDidReceiveBackgroundNotificationResponse,
    );
    _initialized = true;
  }

  static void _onDidReceiveNotificationResponse(NotificationResponse response) {
    // 通知タップ時の処理（フォアグラウンド・バックグラウンド共通）
  }

  @pragma('vm:entry-point')
  static void _onDidReceiveBackgroundNotificationResponse(
      NotificationResponse response) {
    // バックグラウンドで通知をタップした際の処理
    // @pragma('vm:entry-point') によりリリースビルドでも保持される
  }

  @override
  Future<bool> requestPermission() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    final granted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    // Android 13+ permissions are requested via the plugin's Android implementation
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  static int busNotificationId(BusEntry bus) =>
      '${bus.direction.name}_${bus.time}'.hashCode & 0x7FFFFFFF;

  @override
  Future<void> scheduleNotification(
      BusEntry bus, NotificationSettings settings) async {
    await initialize();
    final busTime = bus.toDateTimeToday();
    final notifyAt = busTime.subtract(Duration(minutes: settings.minutesBefore));
    if (notifyAt.isBefore(DateTime.now())) return;

    final tzNotifyAt = tz.TZDateTime.from(notifyAt, tz.local);
    await _plugin.zonedSchedule(
      busNotificationId(bus),
      'バスが出発します',
      '${settings.minutesBefore}分後に ${bus.destination} 行きバスが出発します',
      tzNotifyAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bus_departure',
          'バス出発通知',
          channelDescription: '次のバスの出発前に通知します',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id);
  }

  @override
  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }
}
