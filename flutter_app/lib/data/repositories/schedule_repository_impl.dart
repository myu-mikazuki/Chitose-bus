import '../../domain/entities/bus_schedule.dart';
import '../../domain/repositories/schedule_repository.dart';
import '../models/bus_schedule_model.dart';
import '../sources/schedule_remote_source.dart';
import '../sources/schedule_local_source.dart';

class ScheduleRepositoryImpl implements ScheduleRepository {
  ScheduleRepositoryImpl({
    required this.remoteSource,
    required this.localSource,
  });

  final ScheduleRemoteSource remoteSource;
  final ScheduleLocalSource localSource;

  @override
  Future<ScheduleResponse> fetchSchedule() async {
    try {
      final model = await remoteSource.fetchSchedule();
      await localSource.save(model);
      return model.toEntity();
    } catch (_) {
      final cached = await localSource.load();
      if (cached != null) return cached.toEntity().withIsFromCache(true);
      rethrow;
    }
  }

  @override
  Future<ScheduleResponse?> getCached() async {
    final cached = await localSource.load();
    return cached?.toEntity().withIsFromCache(true);
  }
}
