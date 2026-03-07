import '../entities/bus_schedule.dart';
import '../entities/notification_settings.dart';

abstract class NotificationService {
  Future<bool> requestPermission();
  Future<void> scheduleNotification(BusEntry bus, NotificationSettings settings);
  Future<void> cancelAll();
}
