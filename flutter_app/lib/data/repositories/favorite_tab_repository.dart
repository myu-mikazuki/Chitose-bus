import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/favorite_tab.dart';

class FavoriteTabRepository {
  static const _key = 'favorite_tab_index';

  Future<FavoriteTab> load() async {
    final prefs = await SharedPreferences.getInstance();
    return FavoriteTab(tabIndex: prefs.getInt(_key));
  }

  Future<void> save(FavoriteTab tab) async {
    final prefs = await SharedPreferences.getInstance();
    if (tab.tabIndex == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setInt(_key, tab.tabIndex!);
    }
  }
}
