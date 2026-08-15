import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/bus_schedule.dart';
import '../models/bus_schedule_model.dart';
import '../models/legacy_schedule_parser.dart';

/// 保存されているキャッシュと、それが時刻を持っている停留所。
class CachedSchedule {
  const CachedSchedule({required this.model, required this.stopIds});

  final ScheduleResponseModel model;

  /// 保存時に選ばれていた停留所（`StopSelection.query` を分解したもの）
  final List<String> stopIds;
}

class ScheduleLocalSource {
  static const _keyJson = 'schedule_cache_json';
  static const _keyAt = 'schedule_cache_at';
  static const _keyStops = 'schedule_cache_stops';

  /// 保存されているキャッシュを読む。**選択と一致しなくても返す。**
  ///
  /// 一致を条件にすると、オフラインで停留所を1つ足しただけで時刻表が全く
  /// 出せなくなる。持っている停留所（保存時の `?stops=`）を添えて返し、
  /// 足りない分は画面側でその停留所だけ「取得できていない」と出す（#177）。
  ///
  /// 記録が無いキャッシュ（#177 以前のもの）は形式が違うのでミス扱いにする。
  /// そちらは [loadLegacy] が読む。
  Future<CachedSchedule?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stops = prefs.getString(_keyStops);
    if (stops == null) return null;

    final json = prefs.getString(_keyJson);
    if (json == null) return null;
    try {
      return CachedSchedule(
        model: ScheduleResponseModel.fromJson(
            jsonDecode(json) as Map<String, dynamic>),
        stopIds: stops.isEmpty ? const [] : stops.split(','),
      );
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

  /// #177 以前（`v=3`）のキャッシュを読む。**移行用の一時的な経路**。
  ///
  /// 応答の形式が変わるため、これが無いと既存ユーザー全員が更新後の初回起動で
  /// ネットワークを必要とし、圏外ならエラー画面になる。バス停で開くアプリなので、
  /// 形式が変わったというだけの理由で読めるデータを捨てたくない。
  ///
  /// 停留所の選択が記録されていないキャッシュだけが対象。一度でも取得に成功すれば
  /// 新形式で保存され、この経路は二度と使われない。
  ///
  /// TODO(#186): **v1.4.0 で削除する。** #177 を出す v1.3.0 の次のリリース。
  /// 1リリース分あれば大半の端末が新形式へ移行しきる。
  Future<ScheduleResponse?> loadLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyStops) != null) return null;

    final json = prefs.getString(_keyJson);
    if (json == null) return null;

    try {
      return LegacyScheduleParser.parse(
          jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // TODO(#71): 「最終更新: X分前」などの UI 表示に使用する予定
  Future<DateTime?> loadCachedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_keyAt);
    return ts != null ? DateTime.tryParse(ts) : null;
  }
}
