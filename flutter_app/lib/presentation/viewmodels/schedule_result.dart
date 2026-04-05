import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/entities/bus_schedule.dart';

part 'schedule_result.freezed.dart';

@freezed
class ScheduleResult with _$ScheduleResult {
  const factory ScheduleResult({
    required ScheduleResponse data,
    @Default(false) bool isFromCache,
  }) = _ScheduleResult;
}
