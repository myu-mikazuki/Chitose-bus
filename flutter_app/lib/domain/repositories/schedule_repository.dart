import '../entities/bus_schedule.dart';

abstract interface class ScheduleRepository {
  Future<ScheduleResponse> fetchSchedule();
  Future<ScheduleResponse?> getCached();
}
