import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/notification_settings.dart';

class NotificationSettingsRepository {
  static const _keyEnabled = 'notif_enabled';
  static const _keyMinutesBefore = 'notif_minutes_before';
  static const _keyScheduledBusKeys = 'notif_scheduled_bus_keys';

  Future<NotificationSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? false;
    final minutesBefore = prefs.getInt(_keyMinutesBefore) ?? 10;
    final scheduledBusKeys =
        (prefs.getStringList(_keyScheduledBusKeys) ?? []).toSet();
    return NotificationSettings(
      enabled: enabled,
      minutesBefore: minutesBefore,
      scheduledBusKeys: scheduledBusKeys,
    );
  }

  Future<void> save(NotificationSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, settings.enabled);
    await prefs.setInt(_keyMinutesBefore, settings.minutesBefore);
    await prefs.setStringList(
        _keyScheduledBusKeys, settings.scheduledBusKeys.toList());
  }
}
