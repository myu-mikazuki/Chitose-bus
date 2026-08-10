import '../entities/bus_schedule.dart';

abstract interface class ScheduleRepository {
  /// 時刻表を取得する。失敗したら例外を投げる（呼び出し側がエラー表示に使う）。
  Future<ScheduleResponse> fetchSchedule();

  /// 保存済みの時刻表を返す。無ければ null。
  ///
  /// **例外を投げないこと。** 取得に失敗したあとの復帰手段として呼ばれるため、
  /// ここで投げると呼び出し側の catch を突き抜けて画面が固まる。
  /// 読めないキャッシュは null として扱う。
  Future<ScheduleResponse?> getCached();
}
