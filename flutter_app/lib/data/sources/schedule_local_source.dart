import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/bus_schedule.dart';
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
      final root = jsonDecode(json) as Map<String, dynamic>;
      final current = root['current'] as Map<String, dynamic>?;
      final schedules = current?['schedules'] as List<dynamic>?;
      // 新形式（trips を持つ）はここでは扱わない
      if (schedules == null) return null;

      return ScheduleResponse(
        updatedAt: root['updatedAt'] as String? ?? '',
        current: BusTimetable(
          validFrom: current?['validFrom'] as String? ?? '',
          validTo: current?['validTo'] as String? ?? '',
          schedules: schedules
              .map((e) => _legacyEntry(e as Map<String, dynamic>))
              .toList(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  BusEntry _legacyEntry(Map<String, dynamic> json) => BusEntry(
        time: json['time'] as String,
        // 旧形式の direction は「乗車地 × 行き先」の組。乗車地だけを取り出す
        boardingStopId: switch (json['direction'] as String?) {
          'from_minami_chitose' => 'minamiChitose',
          'from_kenkyuto_to_honbuto' => 'kenkyuto',
          'from_kenkyuto_to_station' => 'kenkyuto',
          'from_honbuto' => 'honbuto',
          _ => 'chitose',
        },
        destination: json['destination'] as String? ?? '',
        arrivals: (json['arrivals'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v as String)),
        routeLabel: json['routeLabel'] as String?,
        platformNumber: json['platformNumber'] as String?,
        weekdayOnly: json['weekdayOnly'] as bool? ?? false,
        weekendOnly: json['weekendOnly'] as bool? ?? false,
        academicOnly: json['academicOnly'] as bool? ?? false,
        vacationOnly: json['vacationOnly'] as bool? ?? false,
      );

  // TODO(#71): 「最終更新: X分前」などの UI 表示に使用する予定
  Future<DateTime?> loadCachedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_keyAt);
    return ts != null ? DateTime.tryParse(ts) : null;
  }
}
