import '../entities/bus_schedule.dart';
import '../entities/notification_settings.dart';

abstract class NotificationService {
  static int busNotificationId(BusEntry bus) =>
      '${bus.direction.name}_${bus.time}'.hashCode & 0x7FFFFFFF;

  Future<bool> requestPermission();
  Future<void> scheduleNotification(BusEntry bus, NotificationSettings settings);
  Future<void> cancel(int id);
  Future<void> cancelAll();
}
