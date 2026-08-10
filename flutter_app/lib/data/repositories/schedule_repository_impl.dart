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

    // 保存する前に解釈できることを確かめる。先に保存すると、解釈できない応答が
    // 永続化されて以降のキャッシュ読み出しが毎回失敗するようになる
    final entity = model.toEntity();
    await localSource.save(model, selection.query);
    return entity;
  }

  /// **例外を投げてはいけない。** 呼び出し側（ScheduleViewModel.refresh）は
  /// 取得に失敗したあとの復帰手段としてこれを呼ぶため、ここで投げると
  /// refresh を突き抜けて AsyncLoading のまま固着する。
  @override
  Future<ScheduleResponse?> getCached() async {
    final selection = await stopSelectionRepository.load();

    // 読み出しも変換もまとめて包む。どこで失敗してもミス扱いにして下へ落とす。
    // 取得経路（fetchSchedule）は従来どおり loud に失敗する
    try {
      final cached = await localSource.load(selection.query);
      if (cached != null) return cached.toEntity();
    } catch (_) {
      // 次の経路へ
    }

    // #177 以前のキャッシュがあれば読む（移行用・v1.4.0 で削除 / #186）
    try {
      return await localSource.loadLegacy();
    } catch (_) {
      return null;
    }
  }
}
