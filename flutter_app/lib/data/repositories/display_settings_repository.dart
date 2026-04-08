import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/display_settings.dart';

class DisplaySettingsRepository {
  static const _keyShowLectureTags = 'display_show_lecture_tags';

  Future<DisplaySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final show = prefs.getBool(_keyShowLectureTags) ?? true;
    return DisplaySettings(showLectureTags: show);
  }

  Future<void> save(DisplaySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowLectureTags, settings.showLectureTags);
  }
}
