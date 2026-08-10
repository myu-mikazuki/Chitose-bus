import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/data/sources/schedule_local_source.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';

class FakeScheduleLocalSource implements ScheduleLocalSource {
  ScheduleResponseModel? stored;

  /// 保存時に渡された停留所の選択。キャッシュのキーが一致しなければミスにする
  String? storedStops;
  int saveCallCount = 0;

  /// キャッシュを事前に置く。停留所の選択を指定しなければ既定の4停留所として扱う
  void preload(ScheduleResponseModel model, {String? stopsKey}) {
    stored = model;
    storedStops = stopsKey ?? StopSelection.initial.query;
  }

  @override
  Future<ScheduleResponseModel?> load(String stopsKey) async =>
      storedStops == stopsKey ? stored : null;

  @override
  Future<void> save(ScheduleResponseModel model, String stopsKey) async {
    stored = model;
    storedStops = stopsKey;
    saveCallCount++;
  }

  @override
  Future<DateTime?> loadCachedAt() async =>
      stored != null ? DateTime.now() : null;
}
