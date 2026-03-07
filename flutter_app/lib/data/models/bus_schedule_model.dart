import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/entities/bus_schedule.dart';

part 'bus_schedule_model.freezed.dart';
part 'bus_schedule_model.g.dart';

@freezed
class BusEntryModel with _$BusEntryModel {
  const factory BusEntryModel({
    required String time,
    required String direction,
    required String destination,
    @Default(<String, String>{}) Map<String, String> arrivals,
  }) = _BusEntryModel;

  factory BusEntryModel.fromJson(Map<String, dynamic> json) =>
      _$BusEntryModelFromJson(json);
}

@freezed
class BusTimetableModel with _$BusTimetableModel {
  const factory BusTimetableModel({
    @Default('') String validFrom,
    @Default('') String validTo,
    @Default('') String pdfUrl,
    required List<BusEntryModel> schedules,
  }) = _BusTimetableModel;

  factory BusTimetableModel.fromJson(Map<String, dynamic> json) =>
      _$BusTimetableModelFromJson(json);
}

@freezed
class ScheduleResponseModel with _$ScheduleResponseModel {
  const factory ScheduleResponseModel({
    required String updatedAt,
    required BusTimetableModel current,
    BusTimetableModel? upcoming,
  }) = _ScheduleResponseModel;

  factory ScheduleResponseModel.fromJson(Map<String, dynamic> json) =>
      _$ScheduleResponseModelFromJson(json);
}

extension BusEntryModelMapper on BusEntryModel {
  BusEntry toEntity() => BusEntry(
        time: time,
        direction: switch (direction) {
          'from_chitose' => BusDirection.fromChitose,
          'from_minami_chitose' => BusDirection.fromMinamiChitose,
          'from_kenkyuto_to_honbuto' => BusDirection.fromKenkyutoToHonbuto,
          'from_kenkyuto_to_station' => BusDirection.fromKenkyutoToStation,
          'from_honbuto' => BusDirection.fromHonbuto,
          _ => BusDirection.fromChitose,
        },
        destination: destination,
        arrivals: arrivals,
      );
}

extension BusTimetableModelMapper on BusTimetableModel {
  BusTimetable toEntity() => BusTimetable(
        validFrom: validFrom,
        validTo: validTo,
        schedules: schedules.map((e) => e.toEntity()).toList(),
        pdfUrl: pdfUrl,
      );
}

extension ScheduleResponseModelMapper on ScheduleResponseModel {
  ScheduleResponse toEntity() => ScheduleResponse(
        updatedAt: updatedAt,
        current: current.toEntity(),
        upcoming: upcoming?.toEntity(),
      );
}
