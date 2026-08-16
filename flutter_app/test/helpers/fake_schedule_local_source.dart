import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/data/sources/schedule_local_source.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';

class FakeScheduleLocalSource implements ScheduleLocalSource {
  ScheduleResponseModel? stored;

  /// 保存時に渡された停留所の選択。読み出したキャッシュに添えて返す
  String? storedStops;
  int saveCallCount = 0;

  /// 読み出しが失敗する状況を作る（キャッシュ破損など）
  bool failOnLoad = false;

  /// キャッシュを事前に置く。停留所の選択を指定しなければ既定の4停留所として扱う
  void preload(ScheduleResponseModel model, {String? stopsKey}) {
    stored = model;
    storedStops = stopsKey ?? StopSelection.initial.query;
  }

  @override
  Future<CachedSchedule?> load() async {
    if (failOnLoad) throw const FormatException('壊れたキャッシュ');
    final model = stored;
    final stops = storedStops;
    if (model == null || stops == null) return null;
    return CachedSchedule(
      model: model,
      stopIds: stops.isEmpty ? const [] : stops.split(','),
    );
  }

  @override
  Future<void> save(ScheduleResponseModel model, String stopsKey) async {
    stored = model;
    storedStops = stopsKey;
    saveCallCount++;
  }

  /// 移行用の旧キャッシュ。テストで明示的に置いたときだけ返す
  ScheduleResponse? legacy;

  @override
  Future<ScheduleResponse?> loadLegacy() async =>
      storedStops == null ? legacy : null;

  @override
  Future<DateTime?> loadCachedAt() async =>
      stored != null ? DateTime.now() : null;
}
