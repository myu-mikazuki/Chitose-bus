import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/data/repositories/favorite_tab_repository.dart';
import 'package:kagi_bus/domain/entities/favorite_tab.dart';
import 'package:kagi_bus/presentation/viewmodels/favorite_tab_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// build() が永遠に完了しないリポジトリ（AsyncLoading テスト用）
class _HangingFavoriteTabRepository implements FavoriteTabRepository {
  @override
  Future<FavoriteTab> load() => Completer<FavoriteTab>().future;

  @override
  Future<void> save(FavoriteTab tab) async {}
}

class FakeFavoriteTabRepository implements FavoriteTabRepository {
  FavoriteTab _stored;

  FakeFavoriteTabRepository([FavoriteTab? initial])
      : _stored = initial ?? const FavoriteTab();

  @override
  Future<FavoriteTab> load() async => _stored;

  @override
  Future<void> save(FavoriteTab tab) async => _stored = tab;
}

ProviderContainer makeContainer([FavoriteTab? initial]) {
  final repo = FakeFavoriteTabRepository(initial);
  return ProviderContainer(
    overrides: [
      favoriteTabRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FavoriteTabNotifier', () {
    test('build: リポジトリから読み込んだ値を返す', () async {
      final container = makeContainer(const FavoriteTab(tabIndex: 1));
      addTearDown(container.dispose);

      final result = await container.read(favoriteTabProvider.future);
      expect(result.tabIndex, equals(1));
    });

    test('build: 未設定のとき tabIndex=null を返す', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(favoriteTabProvider.future);
      expect(result.tabIndex, isNull);
    });

    test('toggleFavorite(2): 未設定 → tabIndex=2 が保存・返される', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(favoriteTabProvider.future);

      await container.read(favoriteTabProvider.notifier).toggleFavorite(2);

      final result = container.read(favoriteTabProvider).value!;
      expect(result.tabIndex, equals(2));
    });

    test('toggleFavorite(2) × 2回: 設定 → 解除（null）', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(favoriteTabProvider.future);

      await container.read(favoriteTabProvider.notifier).toggleFavorite(2);
      await container.read(favoriteTabProvider.notifier).toggleFavorite(2);

      final result = container.read(favoriteTabProvider).value!;
      expect(result.tabIndex, isNull);
    });

    test('toggleFavorite(1) → toggleFavorite(2): 別タブで上書き登録', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(favoriteTabProvider.future);

      await container.read(favoriteTabProvider.notifier).toggleFavorite(1);
      await container.read(favoriteTabProvider.notifier).toggleFavorite(2);

      final result = container.read(favoriteTabProvider).value!;
      expect(result.tabIndex, equals(2));
    });

    test('state が AsyncLoading のとき toggleFavorite は何もしない', () async {
      // load() が完了しないリポジトリで常に AsyncLoading を維持する
      final container = ProviderContainer(
        overrides: [
          favoriteTabRepositoryProvider
              .overrideWithValue(_HangingFavoriteTabRepository()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(favoriteTabProvider.notifier).toggleFavorite(3);

      final state = container.read(favoriteTabProvider);
      expect(state, isA<AsyncLoading>());
    });
  });
}
