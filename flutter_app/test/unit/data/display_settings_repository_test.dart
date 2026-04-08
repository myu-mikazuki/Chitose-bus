import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/data/repositories/display_settings_repository.dart';
import 'package:kagi_bus/domain/entities/display_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DisplaySettingsRepository', () {
    test('load: 未保存のとき showLectureTags=true（デフォルト）', () async {
      final repo = DisplaySettingsRepository();
      final settings = await repo.load();
      expect(settings.showLectureTags, isTrue);
    });

    test('save(false) して load: showLectureTags=false が永続化される', () async {
      final repo = DisplaySettingsRepository();
      await repo.save(const DisplaySettings(showLectureTags: false));
      final loaded = await repo.load();
      expect(loaded.showLectureTags, isFalse);
    });

    test('save(false) → save(true) して load: showLectureTags=true で上書きされる', () async {
      final repo = DisplaySettingsRepository();
      await repo.save(const DisplaySettings(showLectureTags: false));
      await repo.save(const DisplaySettings(showLectureTags: true));
      final loaded = await repo.load();
      expect(loaded.showLectureTags, isTrue);
    });
  });
}
