import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/notification_settings_repository.dart';
import '../../data/services/local_notification_service.dart';
import '../../domain/entities/bus_schedule.dart';
import '../../domain/entities/notification_settings.dart';
import '../../domain/services/notification_service.dart';
import 'schedule_viewmodel.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => LocalNotificationService.instance,
);

final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>(
  (ref) => NotificationSettingsRepository(),
);

final notificationSettingsProvider =
    AsyncNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
  NotificationSettingsNotifier.new,
);

class NotificationSettingsNotifier
    extends AsyncNotifier<NotificationSettings> {
  @override
  Future<NotificationSettings> build() async {
    final repo = ref.watch(notificationSettingsRepositoryProvider);
    return repo.load();
  }

  Future<void> saveSettings(NotificationSettings settings) async {
    final repo = ref.read(notificationSettingsRepositoryProvider);
    await repo.save(settings);
    state = AsyncData(settings);
    await _rescheduleIfNeeded(settings);
  }

  /// 通知を有効にする。権限がなければリクエストし、拒否された場合は enabled=false のまま保存する。
  Future<void> enableNotifications(NotificationSettings current) async {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.requestPermission();
    await saveSettings(current.copyWith(enabled: granted));
  }

  /// 設定変更後に通知を再スケジュールする。
  /// enabled=false または direction=null の場合は既存の通知をすべてキャンセルする。
  Future<void> _rescheduleIfNeeded(NotificationSettings settings) async {
    final service = ref.read(notificationServiceProvider);
    if (!settings.enabled || settings.direction == null) {
      await service.cancelAll();
      return;
    }
    final timetable =
        ref.read(scheduleViewModelProvider).valueOrNull?.current;
    if (timetable == null) {
      await service.cancelAll();
      return;
    }
    await scheduleForTimetable(timetable, settingsOverride: settings);
  }

  /// [settingsOverride] が指定された場合はその設定を使用し、
  /// 省略時は現在の [state] から設定を読み込む。
  Future<void> scheduleForTimetable(BusTimetable timetable,
      {NotificationSettings? settingsOverride}) async {
    final NotificationSettings settings;
    if (settingsOverride != null) {
      settings = settingsOverride;
    } else {
      final settingsState = state;
      if (settingsState is! AsyncData<NotificationSettings>) return;
      settings = settingsState.value;
    }
    if (!settings.enabled || settings.direction == null) return;

    final service = ref.read(notificationServiceProvider);
    await service.cancelAll();

    final now = DateTime.now();
    final upcomingBuses = timetable
        .schedules
        .where((b) =>
            b.direction == settings.direction &&
            b.toDateTimeToday().isAfter(now))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    for (final bus in upcomingBuses.take(3)) {
      await service.scheduleNotification(bus, settings);
    }
  }
}
