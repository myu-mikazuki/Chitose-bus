import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/stop_selection.dart';

class StopSelectionRepository {
  static const _key = 'stop_selection_ids';

  Future<StopSelection> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key);
    // 停留所が0個だと時刻表が全く出せなくなるので初期値に戻す
    if (ids == null || ids.isEmpty) return StopSelection.initial;
    return StopSelection(stopIds: ids);
  }

  Future<void> save(StopSelection selection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, selection.stopIds);
  }
}
