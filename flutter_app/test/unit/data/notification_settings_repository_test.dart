import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chitose_bus/data/repositories/notification_settings_repository.dart';
import 'package:chitose_bus/domain/entities/bus_schedule.dart';
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
      expect(settings.direction, isNull);
    });

    test('save して load: 値が永続化される', () async {
      final repo = NotificationSettingsRepository();
      const saved = NotificationSettings(
        enabled: true,
        minutesBefore: 5,
        direction: BusDirection.fromChitose,
      );
      await repo.save(saved);
      final loaded = await repo.load();
      expect(loaded, equals(saved));
    });

    test('direction=null で save して load: direction が null', () async {
      final repo = NotificationSettingsRepository();
      // まず direction あり で保存
      await repo.save(const NotificationSettings(
        enabled: true,
        minutesBefore: 10,
        direction: BusDirection.toHonbuto,
      ));
      // direction なし で上書き
      await repo.save(const NotificationSettings(enabled: false));
      final loaded = await repo.load();
      expect(loaded.direction, isNull);
    });
  });
}
