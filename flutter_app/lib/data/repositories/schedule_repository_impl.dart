import '../../domain/entities/bus_schedule.dart';
import '../../domain/repositories/schedule_repository.dart';
import '../sources/schedule_remote_source.dart';
import '../models/bus_schedule_model.dart';

class ScheduleRepositoryImpl implements ScheduleRepository {
  ScheduleRepositoryImpl({required this.remoteSource});

  final ScheduleRemoteSource remoteSource;

  @override
  Future<ScheduleResponse> fetchSchedule() async {
    final model = await remoteSource.fetchSchedule();
    return model.toEntity();
  }
}
