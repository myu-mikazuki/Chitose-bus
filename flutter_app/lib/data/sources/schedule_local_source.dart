import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_schedule_model.dart';

class ScheduleLocalSource {
  static const _keyJson = 'schedule_cache_json';
  static const _keyAt = 'schedule_cache_at';
  static const _keyStops = 'schedule_cache_stops';

  /// [stopsKey] は保存時に選んでいた停留所（`StopSelection.query`）。
  ///
  /// 応答は選んだ停留所に依存するため、選択が変わったキャッシュは使えない。
  /// 一致しなければミス扱いにして取り直す。オフラインで選択を変えた直後は
  /// 時刻表が出せなくなるが、中途半端に別の停留所を出すよりは良い。
  ///
  /// 記録が無いキャッシュ（#177 以前のもの）も形式が違うのでミス扱いにする。
  Future<ScheduleResponseModel?> load(String stopsKey) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyStops) != stopsKey) return null;

    final json = prefs.getString(_keyJson);
    if (json == null) return null;
    try {
      return ScheduleResponseModel.fromJson(
          jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ScheduleResponseModel model, String stopsKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyJson, jsonEncode(model.toJson()));
    await prefs.setString(_keyStops, stopsKey);
    await prefs.setString(_keyAt, DateTime.now().toIso8601String());
  }

  // TODO(#71): 「最終更新: X分前」などの UI 表示に使用する予定
  Future<DateTime?> loadCachedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_keyAt);
    return ts != null ? DateTime.tryParse(ts) : null;
  }
}
