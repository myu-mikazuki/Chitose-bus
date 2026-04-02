import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/favorite_tab_repository.dart';
import '../../domain/entities/favorite_tab.dart';

final favoriteTabRepositoryProvider = Provider<FavoriteTabRepository>(
  (ref) => FavoriteTabRepository(),
);

final favoriteTabProvider =
    AsyncNotifierProvider<FavoriteTabNotifier, FavoriteTab>(
  FavoriteTabNotifier.new,
);

class FavoriteTabNotifier extends AsyncNotifier<FavoriteTab> {
  @override
  Future<FavoriteTab> build() async {
    final repo = ref.read(favoriteTabRepositoryProvider);
    return repo.load();
  }

  /// 現在表示中のタブをお気に入り登録/解除する。
  /// 同じ [tabIndex] なら解除、異なれば上書き登録。
  Future<void> toggleFavorite(int tabIndex) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final repo = ref.read(favoriteTabRepositoryProvider);
    final next = current.tabIndex == tabIndex
        ? const FavoriteTab()
        : FavoriteTab(tabIndex: tabIndex);
    await repo.save(next);
    state = AsyncData(next);
  }
}
