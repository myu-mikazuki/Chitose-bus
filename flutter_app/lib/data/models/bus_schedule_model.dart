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

// ---- 旧形式（BusDirection ごとの1件）への展開 ----
//
// GAS の応答は1便を1件だが、アプリの画面はまだ「乗車地ごとの1件」を前提に
// できている。表示を変えずにデータ層だけ差し替えるため、ここで展開して
// 従来と同じ BusEntry の並びを作る。
//
// **この展開は乗車地選択の UI を入れる際に削除する。** 画面が停留所の並びを
// 直接扱えるようになれば、BusDirection ごと不要になる。

/// 旧形式で乗車地として出す停留所と、対応する BusDirection。
/// GAS 側の LEGACY_BOARDING と同じ内容（片方だけ変えると表示が食い違う）。
const _legacyBoarding = <String, List<(String, BusDirection)>>{
  '科技大': [
    ('chitose', BusDirection.fromChitose),
    ('minamiChitose', BusDirection.fromMinamiChitose),
    ('kenkyuto', BusDirection.fromKenkyutoToHonbuto),
  ],
  '千歳駅': [
    ('honbuto', BusDirection.fromHonbuto),
    ('kenkyuto', BusDirection.fromKenkyutoToStation),
  ],
};

/// 旧形式が扱える4停留所。arrivals はこれだけに絞る
const _legacyStops = {'chitose', 'minamiChitose', 'kenkyuto', 'honbuto'};

extension TripModelMapper on TripModel {
  /// 乗車地ごとの BusEntry に展開する（通らない乗車地は作らない）
  List<BusEntry> toEntries() {
    final boarding = _legacyBoarding[destination];
    if (boarding == null) return const [];

    final out = <BusEntry>[];
    for (final (stopId, direction) in boarding) {
      final index = stops.indexWhere((s) => s.id == stopId);
      if (index < 0) continue;

      // 乗車地より後にある停留所のうち、旧形式が扱える4つだけを到着として持つ
      final arrivals = <String, String>{};
      for (final s in stops.skip(index + 1)) {
        if (_legacyStops.contains(s.id)) arrivals[s.id] = s.time;
      }
      if (arrivals.isEmpty) continue;

      out.add(BusEntry(
        time: stops[index].time,
        direction: direction,
        destination: destination,
        arrivals: arrivals,
        routeLabel: routeLabel,
        platformNumber: stops[index].platform,
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
  BusStop toEntity() =>
      BusStop(id: id, label: label, boardable: boardable);
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
