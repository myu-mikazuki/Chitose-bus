import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/entities/bus_schedule.dart';

part 'bus_schedule_model.freezed.dart';
part 'bus_schedule_model.g.dart';

/// 便が通る停留所と、その時刻
@freezed
class StopTimeModel with _$StopTimeModel {
  const factory StopTimeModel({
    required String id,
    required String time,

    /// のりば。便ではなく停留所ごとの属性（`5番` は千歳駅のもの）
    String? platform,
  }) = _StopTimeModel;

  factory StopTimeModel.fromJson(Map<String, dynamic> json) =>
      _$StopTimeModelFromJson(json);
}

/// 1便。停留所と時刻の並びを持つ（GAS の `?v=4`）
@freezed
class TripModel with _$TripModel {
  const factory TripModel({
    @Default('') String destination,
    String? routeLabel,

    /// 終点（一般に降りられる最後の停留所）の ID。
    ///
    /// GAS が絞り込みの前に決めて返す。`stops` の末尾から導くと、選んだ停留所で
    /// 終点が変わってしまう。`terminus` を返さない GAS（未デプロイ・#177 以前の
    /// キャッシュ）もあるため null 許容。
    String? terminus,
    @Default(false) bool weekdayOnly,
    @Default(false) bool weekendOnly,
    @Default(false) bool academicOnly,
    @Default(false) bool vacationOnly,
    @Default(<StopTimeModel>[]) List<StopTimeModel> stops,
  }) = _TripModel;

  factory TripModel.fromJson(Map<String, dynamic> json) =>
      _$TripModelFromJson(json);
}

/// 停留所そのもの（表示名の供給元）
@freezed
class StopModel with _$StopModel {
  const factory StopModel({
    required String id,
    required String label,

    /// タブなど幅の狭い場所で使う短縮名。正式名と同じなら GAS は返さない
    String? shortLabel,

    /// 乗車地として選べるか。GAS は false のときだけ返す
    @Default(true) bool boardable,
  }) = _StopModel;

  factory StopModel.fromJson(Map<String, dynamic> json) =>
      _$StopModelFromJson(json);
}

@freezed
class BusTimetableModel with _$BusTimetableModel {
  const factory BusTimetableModel({
    @Default('') String validFrom,
    @Default('') String validTo,
    @Default('') String pdfUrl,
    @Default(<TripModel>[]) List<TripModel> trips,
  }) = _BusTimetableModel;

  factory BusTimetableModel.fromJson(Map<String, dynamic> json) =>
      _$BusTimetableModelFromJson(json);
}

@freezed
class ScheduleResponseModel with _$ScheduleResponseModel {
  const factory ScheduleResponseModel({
    required String updatedAt,
    @Default(<StopModel>[]) List<StopModel> stopMaster,
    required BusTimetableModel current,
    BusTimetableModel? upcoming,
  }) = _ScheduleResponseModel;

  factory ScheduleResponseModel.fromJson(Map<String, dynamic> json) =>
      _$ScheduleResponseModelFromJson(json);
}

// ---- 乗車地ごとの BusEntry への展開 ----
//
// GAS の応答は1便を1件だが、画面は「この停留所から乗るとどうなるか」を出すため、
// 便が通る停留所それぞれについて BusEntry を作る。
//
// 展開の大きさは選んだ停留所の数で決まる（既定の4停留所なら1便あたり3件）。
// GAS が選択で絞ってくれるので、ここが膨らむことはない。

extension TripModelMapper on TripModel {
  /// 便が通る各停留所について、そこから乗る場合の BusEntry を作る。
  /// **降りる先が1つも無い停留所は作らない。**
  ///
  /// [TripModel.terminus] では判定しない。終点は必ず `arrivals` が空になるので
  /// この条件に含まれており、terminus に変えると増えるのは「絞り込みで末尾に
  /// 来ただけの停留所も乗車地にする」ぶんだけになる。それは**選んだ停留所の
  /// 中に降り先が無い**便で、時刻を出しても発車時刻が並ぶだけになる。
  ///
  /// 既定の4停留所で長都行きを絞ると末尾が千歳駅前になり、終点（長都駅東口）と
  /// 一致しないため千歳駅前が乗車地として増える。設定を触っていない利用者の
  /// 千歳駅タブに行き先の切り替えが生えてしまう（#200 のレビュー）。
  ///
  /// 選んだ停留所が1つだけだと、この条件で全便が消える。画面側が
  /// `_StopHasNoBus` で受けるので、空白にはならない。
  List<BusEntry> toEntries() {
    final out = <BusEntry>[];
    for (var i = 0; i < stops.length; i++) {
      final arrivals = <String, String>{};
      // 通過順のまま入れる。表示順はこの順序に従う
      for (final s in stops.skip(i + 1)) {
        arrivals[s.id] = s.time;
      }
      if (arrivals.isEmpty) continue;

      out.add(BusEntry(
        time: stops[i].time,
        boardingStopId: stops[i].id,
        destination: destination,
        terminusStopId: terminus,
        arrivals: arrivals,
        routeLabel: routeLabel,
        platformNumber: stops[i].platform,
        weekdayOnly: weekdayOnly,
        weekendOnly: weekendOnly,
        academicOnly: academicOnly,
        vacationOnly: vacationOnly,
      ));
    }
    return out;
  }
}

extension StopModelMapper on StopModel {
  BusStop toEntity() => BusStop(
        id: id,
        label: label,
        shortLabel: shortLabel,
        boardable: boardable,
      );
}

extension BusTimetableModelMapper on BusTimetableModel {
  BusTimetable toEntity() => BusTimetable(
        validFrom: validFrom,
        validTo: validTo,
        schedules: [for (final t in trips) ...t.toEntries()],
        pdfUrl: pdfUrl,
      );
}

extension ScheduleResponseModelMapper on ScheduleResponseModel {
  /// [coveredStopIds] は取得時の `?stops=`。応答そのものには入っていないため
  /// 外から渡す（キャッシュなら保存時の記録、取得直後なら今の選択）。
  ///
  /// **必須にしてある。** 既定値を空にすると、渡し忘れた経路が
  /// 「全停留所を持っている」と申告してしまう（[ScheduleResponse.covers] は
  /// 空を「分からない = 全部」と読む）。空が要るのは #177 以前のキャッシュだけで、
  /// そちらは [ScheduleResponse] 側の既定値で足りる。
  ScheduleResponse toEntity({required List<String> coveredStopIds}) =>
      ScheduleResponse(
        updatedAt: updatedAt,
        stopMaster: stopMaster.map((s) => s.toEntity()).toList(),
        coveredStopIds: coveredStopIds,
        current: current.toEntity(),
        upcoming: upcoming?.toEntity(),
      );
}
