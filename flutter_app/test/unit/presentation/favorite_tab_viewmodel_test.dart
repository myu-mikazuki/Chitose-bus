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
      final container =
          makeContainer(const FavoriteTab(stopId: 'minamiChitose'));
      addTearDown(container.dispose);

      final result = await container.read(favoriteTabProvider.future);
      expect(result.stopId, equals('minamiChitose'));
    });

    test('build: 未設定のとき stopId=null を返す', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(favoriteTabProvider.future);
      expect(result.stopId, isNull);
    });

    test('toggleFavorite(kenkyuto): 未設定 → stopId=kenkyuto が保存・返される', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(favoriteTabProvider.future);

      await container
          .read(favoriteTabProvider.notifier)
          .toggleFavorite('kenkyuto');

      final result = container.read(favoriteTabProvider).value!;
      expect(result.stopId, equals('kenkyuto'));
    });

    test('toggleFavorite(kenkyuto) × 2回: 設定 → 解除（null）', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(favoriteTabProvider.future);

      await container
          .read(favoriteTabProvider.notifier)
          .toggleFavorite('kenkyuto');
      await container
          .read(favoriteTabProvider.notifier)
          .toggleFavorite('kenkyuto');

      final result = container.read(favoriteTabProvider).value!;
      expect(result.stopId, isNull);
    });

    test('toggleFavorite(minamiChitose) → toggleFavorite(kenkyuto): 別タブで上書き登録',
        () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(favoriteTabProvider.future);

      await container
          .read(favoriteTabProvider.notifier)
          .toggleFavorite('minamiChitose');
      await container
          .read(favoriteTabProvider.notifier)
          .toggleFavorite('kenkyuto');

      final result = container.read(favoriteTabProvider).value!;
      expect(result.stopId, equals('kenkyuto'));
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

      await container
          .read(favoriteTabProvider.notifier)
          .toggleFavorite('honbuto');

      final state = container.read(favoriteTabProvider);
      expect(state, isA<AsyncLoading>());
    });
  });
}
