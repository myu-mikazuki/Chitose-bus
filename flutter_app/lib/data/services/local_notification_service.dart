import 'package:flutter/services.dart';
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
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;
      if (!granted) return false;
      // Android 12+ では正確なアラーム権限が別途必要。未付与の場合はシステム設定画面を開く。
      // ユーザーが設定画面で許可しなくても通知自体は有効にする（inexact フォールバックあり）。
      final canExact =
          await android.canScheduleExactNotifications() ?? false;
      if (!canExact) await android.requestExactAlarmsPermission();
      return true;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  @override
  Future<void> scheduleNotification(
      BusEntry bus, NotificationSettings settings) async {
    await initialize();
    final now = DateTime.now();
    final busTime = bus.toDateTimeToday(now: now);
    final notifyAt = busTime.subtract(Duration(minutes: settings.minutesBefore));
    if (notifyAt.isBefore(now)) return;

    final tzNotifyAt = tz.TZDateTime.from(notifyAt, tz.local);
    const details = NotificationDetails(
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
    );
    const interpretation =
        UILocalNotificationDateInterpretation.absoluteTime;

    try {
      await _plugin.zonedSchedule(
        NotificationService.busNotificationId(bus),
        'バスが出発します',
        '${settings.minutesBefore}分後に ${bus.destination} 行きバスが出発します',
        tzNotifyAt,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: interpretation,
      );
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') rethrow;
      // SCHEDULE_EXACT_ALARM 未付与時は inexact でフォールバック
      await _plugin.zonedSchedule(
        NotificationService.busNotificationId(bus),
        'バスが出発します',
        '${settings.minutesBefore}分後に ${bus.destination} 行きバスが出発します',
        tzNotifyAt,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: interpretation,
      );
    }
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
