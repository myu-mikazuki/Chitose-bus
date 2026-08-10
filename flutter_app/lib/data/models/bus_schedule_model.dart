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
  /// 後に停留所が無い（＝終点）ものは乗車地にならないので作らない。
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
  ScheduleResponse toEntity() => ScheduleResponse(
        updatedAt: updatedAt,
        stopMaster: stopMaster.map((s) => s.toEntity()).toList(),
        current: current.toEntity(),
        upcoming: upcoming?.toEntity(),
      );
}
