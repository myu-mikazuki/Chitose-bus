import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chitose_bus/data/repositories/notification_settings_repository.dart';
import 'package:chitose_bus/domain/entities/notification_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NotificationSettingsRepository', () {
    test('load: デフォルト値を返す（何も保存されていない場合）', () async {
      final repo = NotificationSettingsRepository();
      final settings = await repo.load();
      expect(settings.enabled, isFalse);
      expect(settings.minutesBefore, 10);
    });

    test('save して load: enabled・minutesBefore が永続化される', () async {
      final repo = NotificationSettingsRepository();
      final saved = NotificationSettings(
        enabled: true,
        minutesBefore: 5,
      );
      await repo.save(saved);
      final loaded = await repo.load();
      expect(loaded.enabled, isTrue);
      expect(loaded.minutesBefore, equals(5));
    });

    test('scheduledBusKeys: save して load: キーが永続化される', () async {
      final repo = NotificationSettingsRepository();
      final saved = NotificationSettings(
        enabled: true,
        minutesBefore: 10,
        scheduledBusKeys: {'fromChitose_08:30', 'toChitose_09:00'},
      );
      await repo.save(saved);
      final loaded = await repo.load();
      expect(loaded.scheduledBusKeys, {'fromChitose_08:30', 'toChitose_09:00'});
    });

    test('scheduledBusKeys: 空で save して load: 空の Set', () async {
      final repo = NotificationSettingsRepository();
      // まずキーあり で保存
      await repo.save(NotificationSettings(
        scheduledBusKeys: {'fromChitose_08:30'},
      ));
      // 空で上書き
      await repo.save(NotificationSettings());
      final loaded = await repo.load();
      expect(loaded.scheduledBusKeys, isEmpty);
    });
  });
}
