import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/data/sources/schedule_local_source.dart';

class FakeScheduleLocalSource implements ScheduleLocalSource {
  ScheduleResponseModel? stored;
  int saveCallCount = 0;

  @override
  Future<ScheduleResponseModel?> load() async => stored;

  @override
  Future<void> save(ScheduleResponseModel model) async {
    stored = model;
    saveCallCount++;
  }

  @override
  Future<DateTime?> loadCachedAt() async =>
      stored != null ? DateTime.now() : null;
}
