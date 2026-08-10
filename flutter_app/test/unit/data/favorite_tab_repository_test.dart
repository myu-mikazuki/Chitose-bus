import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kagi_bus/data/repositories/favorite_tab_repository.dart';
import 'package:kagi_bus/domain/entities/favorite_tab.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FavoriteTabRepository', () {
    test('load: 未設定のとき stopId=null を返す', () async {
      final repo = FavoriteTabRepository();
      final result = await repo.load();
      expect(result.stopId, isNull);
      expect(result.hasFavorite, isFalse);
    });

    test("save('kenkyuto') → load: 同じ停留所が返る", () async {
      final repo = FavoriteTabRepository();
      await repo.save(const FavoriteTab(stopId: 'kenkyuto'));
      expect((await repo.load()).stopId, 'kenkyuto');
    });

    test('save(null) → load: null が返る', () async {
      final repo = FavoriteTabRepository();
      await repo.save(const FavoriteTab());
      expect((await repo.load()).stopId, isNull);
    });

    test('設定 → 解除 → load: null が返る', () async {
      final repo = FavoriteTabRepository();
      await repo.save(const FavoriteTab(stopId: 'minamiChitose'));
      await repo.save(const FavoriteTab());
      expect((await repo.load()).stopId, isNull);
    });

    test('上書きできる', () async {
      final repo = FavoriteTabRepository();
      await repo.save(const FavoriteTab(stopId: 'chitose'));
      await repo.save(const FavoriteTab(stopId: 'honbuto'));
      expect((await repo.load()).stopId, 'honbuto');
    });

    test('現行4停留所以外も保存できる', () async {
      final repo = FavoriteTabRepository();
      await repo.save(const FavoriteTab(stopId: 'morimoto'));
      expect((await repo.load()).stopId, 'morimoto');
    });
  });

  group('#177 以前のお気に入り（タブ番号）からの移行', () {
    // 旧: favorite_tab_index に 0〜3 を保存していた。
    // 番号のままだと停留所を並べ替えた瞬間に別の停留所を指してしまう
    Future<void> putLegacy(int index) async {
      SharedPreferences.setMockInitialValues({'favorite_tab_index': index});
    }

    test('0 → chitose', () async {
      await putLegacy(0);
      expect((await FavoriteTabRepository().load()).stopId, 'chitose');
    });

    test('1 → minamiChitose', () async {
      await putLegacy(1);
      expect((await FavoriteTabRepository().load()).stopId, 'minamiChitose');
    });

    test('2 → kenkyuto', () async {
      await putLegacy(2);
      expect((await FavoriteTabRepository().load()).stopId, 'kenkyuto');
    });

    test('3 → honbuto', () async {
      await putLegacy(3);
      expect((await FavoriteTabRepository().load()).stopId, 'honbuto');
    });

    test('移行後は旧キーを消す（二度と参照しない）', () async {
      await putLegacy(2);
      await FavoriteTabRepository().load();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('favorite_tab_index'), isNull);
      expect(prefs.getString('favorite_tab_stop'), 'kenkyuto');
    });

    test('範囲外の番号は移行しない（お気に入り未設定として扱う）', () async {
      await putLegacy(9);
      expect((await FavoriteTabRepository().load()).stopId, isNull);
    });

    test('新形式が既にあれば旧キーより優先する', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_tab_index': 0,
        'favorite_tab_stop': 'morimoto',
      });
      expect((await FavoriteTabRepository().load()).stopId, 'morimoto');
    });
  });
}
