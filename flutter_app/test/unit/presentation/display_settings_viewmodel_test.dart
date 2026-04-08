import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/data/repositories/display_settings_repository.dart';
import 'package:kagi_bus/domain/entities/display_settings.dart';
import 'package:kagi_bus/presentation/viewmodels/display_settings_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeDisplaySettingsRepository implements DisplaySettingsRepository {
  DisplaySettings _stored;

  FakeDisplaySettingsRepository([DisplaySettings? initial])
      : _stored = initial ?? const DisplaySettings();

  @override
  Future<DisplaySettings> load() async => _stored;

  @override
  Future<void> save(DisplaySettings settings) async => _stored = settings;
}

ProviderContainer makeContainer([DisplaySettings? initial]) {
  final repo = FakeDisplaySettingsRepository(initial);
  return ProviderContainer(
    overrides: [
      displaySettingsRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DisplaySettingsNotifier', () {
    test('build: リポジトリから読み込んだ値を返す', () async {
      final container =
          makeContainer(const DisplaySettings(showLectureTags: false));
      addTearDown(container.dispose);

      final result = await container.read(displaySettingsProvider.future);
      expect(result.showLectureTags, isFalse);
    });

    test('build: 未設定のとき showLectureTags=true（デフォルト）', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(displaySettingsProvider.future);
      expect(result.showLectureTags, isTrue);
    });

    test('saveSettings(false): state が更新される', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(displaySettingsProvider.future);

      await container
          .read(displaySettingsProvider.notifier)
          .saveSettings(const DisplaySettings(showLectureTags: false));

      final result = container.read(displaySettingsProvider).value!;
      expect(result.showLectureTags, isFalse);
    });

    test('saveSettings(false) → saveSettings(true): state が正しく更新される', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(displaySettingsProvider.future);

      await container
          .read(displaySettingsProvider.notifier)
          .saveSettings(const DisplaySettings(showLectureTags: false));
      await container
          .read(displaySettingsProvider.notifier)
          .saveSettings(const DisplaySettings(showLectureTags: true));

      final result = container.read(displaySettingsProvider).value!;
      expect(result.showLectureTags, isTrue);
    });
  });
}
