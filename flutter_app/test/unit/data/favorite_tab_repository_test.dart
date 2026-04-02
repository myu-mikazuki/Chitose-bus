import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kagi_bus/data/repositories/favorite_tab_repository.dart';
import 'package:kagi_bus/domain/entities/favorite_tab.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FavoriteTabRepository', () {
    test('load: 未設定のとき tabIndex=null を返す', () async {
      final repo = FavoriteTabRepository();
      final result = await repo.load();
      expect(result.tabIndex, isNull);
      expect(result.hasFavorite, isFalse);
    });

    test('save(tabIndex: 2) → load: tabIndex=2 が返る', () async {
      final repo = FavoriteTabRepository();
      await repo.save(const FavoriteTab(tabIndex: 2));
      final loaded = await repo.load();
      expect(loaded.tabIndex, equals(2));
    });

    test('save(tabIndex: null) → load: null が返る', () async {
      final repo = FavoriteTabRepository();
      await repo.save(const FavoriteTab());
      final loaded = await repo.load();
      expect(loaded.tabIndex, isNull);
    });

    test('save(tabIndex: 1) → save(tabIndex: null) → load: null が返る', () async {
      final repo = FavoriteTabRepository();
      await repo.save(const FavoriteTab(tabIndex: 1));
      await repo.save(const FavoriteTab());
      final loaded = await repo.load();
      expect(loaded.tabIndex, isNull);
    });

    test('save(tabIndex: 0) → save(tabIndex: 3) → load: 3 が返る（上書き）', () async {
      final repo = FavoriteTabRepository();
      await repo.save(const FavoriteTab(tabIndex: 0));
      await repo.save(const FavoriteTab(tabIndex: 3));
      final loaded = await repo.load();
      expect(loaded.tabIndex, equals(3));
    });
  });
}
