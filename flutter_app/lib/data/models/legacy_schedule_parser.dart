import '../../domain/entities/bus_schedule.dart';

/// #177 以前（`v<=3`）の応答形式を読む。**移行用の一時的な経路**。
///
/// 読み手は2つある。どちらも「読めるデータを捨てない」ための保険で、
/// 形式が違うというだけの理由でバス停の前に立つ利用者を空振りさせない。
///
/// - `ScheduleLocalSource.loadLegacy` — 更新後の初回起動で、旧形式のまま
///   残っているキャッシュを読む
/// - `ScheduleRemoteSource.fetchSchedule` — 本番 GAS が未デプロイ、または
///   デプロイをロールバックしたときに旧形式が返ってくる（#201）
///
/// 新形式（`trips` を持つ）は扱わない。`current.schedules` が無ければ null。
///
/// **組み立てるのは `current` だけ。** 旧形式も `upcoming` を持ちうるが、
/// 今の GAS は `getHardcodedTimetable()` が `upcoming: null` 固定なので
/// 実際には返らない。落ちても「来週のダイヤ」が出ないだけで、そのシートは
/// [#202](https://github.com/myu-mikazuki/Chitose-bus/issues/202) の通り
/// 現状どのみち開けない。
///
/// **`stopMaster` も作らない。** 旧形式の応答には入っていないため、
/// 表示名はキャッシュに残っているものを `ScheduleRepositoryImpl` が引き継ぐ。
///
/// TODO(#186): **v1.4.0 で削除する。** 削除後、旧形式の応答は解釈せず
/// 例外にする（黙って空のキャッシュを書くよりは取得失敗のほうがましなため）。
abstract final class LegacyScheduleParser {
  /// 旧形式の**形をしている**か。中身が読めるかまでは見ない。
  ///
  /// [parse] の null は「旧形式でない」と「旧形式だが壊れている」の両方を
  /// 意味するため、この2つを区別したい呼び出し側はこちらで先に判定する。
  /// 混同すると、壊れた旧形式が新形式として保存されて #201 が再発する。
  static bool isLegacyShape(Map<String, dynamic> root) {
    final current = root['current'];
    return current is Map<String, dynamic> && current['schedules'] is List;
  }

  /// 旧形式の応答（またはキャッシュ）を [ScheduleResponse] にする。
  /// 旧形式として読めなければ null。
  static ScheduleResponse? parse(Map<String, dynamic> root) {
    try {
      final current = root['current'] as Map<String, dynamic>?;
      final schedules = current?['schedules'] as List<dynamic>?;
      // 新形式（trips を持つ）はここでは扱わない
      if (schedules == null) return null;

      return ScheduleResponse(
        updatedAt: root['updatedAt'] as String? ?? '',
        // 旧形式が持っているのはこの4停留所だけ。停留所を足していれば、
        // その分は「取得できていない」として出る
        coveredStopIds: coveredStopIds,
        current: BusTimetable(
          validFrom: current?['validFrom'] as String? ?? '',
          validTo: current?['validTo'] as String? ?? '',
          schedules:
              schedules.map((e) => _entry(e as Map<String, dynamic>)).toList(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// 旧形式が時刻を持っている停留所。**今の選択で置き換えてはいけない。**
  /// 置き換えると、足したばかりの停留所が「取得できていない」ではなく
  /// 「便が1本も無い」として出る。
  ///
  /// GAS 側の `LEGACY_STOPS`（`gas/Code.gs`）と同じ4件。**片方だけ動かさないこと。**
  /// 増やせば持っていない停留所を「取得済み」と申告し、減らせば持っている
  /// 停留所が「取得できていません」になる
  static const coveredStopIds = [
    'chitose',
    'minamiChitose',
    'kenkyuto',
    'honbuto',
  ];

  static BusEntry _entry(Map<String, dynamic> json) => BusEntry(
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
}
