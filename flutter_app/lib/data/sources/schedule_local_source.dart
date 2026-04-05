import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_schedule_model.dart';

class ScheduleLocalSource {
  static const _keyJson = 'schedule_cache_json';
  static const _keyAt = 'schedule_cache_at';

  Future<ScheduleResponseModel?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyJson);
    if (json == null) return null;
    try {
      return ScheduleResponseModel.fromJson(
          jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ScheduleResponseModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyJson, jsonEncode(model.toJson()));
    await prefs.setString(_keyAt, DateTime.now().toIso8601String());
  }

  Future<DateTime?> loadCachedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_keyAt);
    return ts != null ? DateTime.tryParse(ts) : null;
  }
}
