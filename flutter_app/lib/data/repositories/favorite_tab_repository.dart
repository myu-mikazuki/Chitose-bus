import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/favorite_tab.dart';

class FavoriteTabRepository {
  static const _key = 'favorite_tab_stop';

  /// #177 以前のキー。タブ番号（0〜3）を保存していた
  static const _legacyKey = 'favorite_tab_index';

  /// **#177 以前のタブ順**。過去の事実なので凍結する。
  ///
  /// StopSelection.defaultStopIds は「現在の既定選択」で、将来並びを変えうる。
  /// それを参照すると、変えた瞬間に旧番号 0 が別の停留所へ移行されてしまう。
  static const _legacyTabOrder = [
    'chitose',
    'minamiChitose',
    'kenkyuto',
    'honbuto'
  ];

  Future<FavoriteTab> load() async {
    final prefs = await SharedPreferences.getInstance();

    final stopId = prefs.getString(_key);
    if (stopId != null) return FavoriteTab(stopId: stopId);

    return _migrateFromTabIndex(prefs);
  }

  Future<void> save(FavoriteTab tab) async {
    final prefs = await SharedPreferences.getInstance();
    final stopId = tab.stopId;
    if (stopId == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, stopId);
    }
  }

  /// タブ番号で保存されていたお気に入りを停留所 ID に移す。
  ///
  /// 番号は #177 以前の並び（千歳駅・南千歳・研究棟・本部棟）に対応する。
  /// 移行したら旧キーを消し、二度と参照しないようにする。
  ///
  /// TODO(#186): 旧キャッシュの経路と一緒に v1.4.0 で削除する。
  Future<FavoriteTab> _migrateFromTabIndex(SharedPreferences prefs) async {
    final index = prefs.getInt(_legacyKey);
    if (index == null) return const FavoriteTab();

    await prefs.remove(_legacyKey);

    const order = _legacyTabOrder;
    if (index < 0 || index >= order.length) return const FavoriteTab();

    final stopId = order[index];
    await prefs.setString(_key, stopId);
    return FavoriteTab(stopId: stopId);
  }
}
