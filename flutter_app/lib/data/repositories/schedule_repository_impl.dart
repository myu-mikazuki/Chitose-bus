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

    switch (await remoteSource.fetchSchedule(selection)) {
      case RemoteScheduleV4(:final model):
        // 保存する前に解釈できることを確かめる。先に保存すると、解釈できない応答が
        // 永続化されて以降のキャッシュ読み出しが毎回失敗するようになる
        final entity = model.toEntity(coveredStopIds: selection.stopIds);
        await localSource.save(model, selection.query);
        return entity;

      // 旧形式（GAS が未デプロイ、またはデプロイをロールバックした場合）。
      // **保存せずに返す。** 保存すると「便が0本」のキャッシュが読めていた
      // キャッシュを上書きし、移行経路も塞いで復旧しなくなる（#201）。
      //
      // 取得できた分は捨てずに出す。既定の4停留所ぶんの時刻は正しく、
      // 足した停留所は coveredStopIds に入らないので画面側が
      // 「取得できていない」として出す
      case RemoteScheduleLegacy(:final entity):
        return entity;
    }
  }

  /// **例外を投げてはいけない。** 呼び出し側（ScheduleViewModel.refresh）は
  /// 取得に失敗したあとの復帰手段としてこれを呼ぶため、ここで投げると
  /// refresh を突き抜けて AsyncLoading のまま固着する。
  ///
  /// **選択と食い違うキャッシュも返す。** オフラインで停留所を1つ足しただけで
  /// 時刻表が全く出せなくなるのを避けるため。持っている停留所は
  /// [ScheduleResponse.coveredStopIds] に載るので、足りない分は画面側が
  /// その停留所だけ「取得できていない」と出す（#177）。
  @override
  Future<ScheduleResponse?> getCached() async {
    // メソッド全体を包む。どこで失敗してもミス扱いにする。
    // 取得経路（fetchSchedule）は従来どおり loud に失敗する
    try {
      final cached = await localSource.load();
      if (cached != null) {
        return cached.model.toEntity(coveredStopIds: cached.stopIds);
      }
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
