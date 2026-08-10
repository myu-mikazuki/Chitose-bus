import '../../domain/entities/bus_schedule.dart';
import '../../domain/repositories/schedule_repository.dart';
import '../models/bus_schedule_model.dart';
import '../sources/schedule_remote_source.dart';
import '../sources/schedule_local_source.dart';
import 'stop_selection_repository.dart';

class ScheduleRepositoryImpl implements ScheduleRepository {
  ScheduleRepositoryImpl({
    required this.remoteSource,
    required this.localSource,
    required this.stopSelectionRepository,
  });

  final ScheduleRemoteSource remoteSource;
  final ScheduleLocalSource localSource;

  /// どの停留所を取得するかは利用者の選択で決まる。
  /// 画面側は選択を意識せずに済むよう、ここで読み取る。
  final StopSelectionRepository stopSelectionRepository;

  @override
  Future<ScheduleResponse> fetchSchedule() async {
    final selection = await stopSelectionRepository.load();
    final model = await remoteSource.fetchSchedule(selection);
    await localSource.save(model, selection.query);
    return model.toEntity();
  }

  @override
  Future<ScheduleResponse?> getCached() async {
    final selection = await stopSelectionRepository.load();
    final cached = await localSource.load(selection.query);
    return cached?.toEntity();
  }
}
