import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus_schedule_model.dart';
import '../models/legacy_schedule_parser.dart';
import '../../domain/entities/bus_schedule.dart';
import '../../domain/entities/stop_selection.dart';

/// GAS から返ってきた応答。**形式は2通りある。**
///
/// `?v=4` を送っても、本番 GAS が未デプロイだったりデプロイをロールバック
/// されていれば旧形式（`current.schedules`）が返る。呼び出し側に
/// switch を書かせて、どちらの形式かを取り違えられないようにする（#201）。
sealed class RemoteSchedule {
  const RemoteSchedule();
}

/// `?v=4` の応答。そのまま保存してよい
final class RemoteScheduleV4 extends RemoteSchedule {
  const RemoteScheduleV4(this.model);

  final ScheduleResponseModel model;
}

/// 旧形式（`v<=3`）の応答。**保存してはいけない。**
///
/// [ScheduleResponseModel] としても解釈できてしまうが、`trips` が既定値の
/// 空配列になるため「便が0本」のキャッシュになる。保存すると
/// `schedule_cache_stops` が入って [ScheduleLocalSource.loadLegacy] も塞がり、
/// 再インストールするまで復旧しない（#201）。
final class RemoteScheduleLegacy extends RemoteSchedule {
  const RemoteScheduleLegacy(this.entity);

  /// 旧形式のまま解釈した結果。持っているのは既定の4停留所だけ
  final ScheduleResponse entity;
}

class ScheduleRemoteSource {
  ScheduleRemoteSource({required this.endpointUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// リクエストする GAS のスキーマバージョン。
  ///
  /// これはレスポンスの形式ではなく、**アプリが持つ判定ロジックの世代**を表す。
  /// GAS は古い v に対して、そのアプリが判定できない分をサーバ側で絞ってから返す。
  ///
  ///   v=1 … 期別も祝日も判定できない（v1.1.0 以前）
  ///   v=2 … 期別は判定できるが祝日は判定できない（v1.2.0）
  ///   v=3 … 期別・祝日ともに判定できる
  ///   v=4 … 任意の停留所を扱える（現在）。応答の構造が変わり、?stops= で絞れる
  ///
  /// **アプリ側に新しい判定ロジックを足したら、この値を上げること。**
  /// 上げ忘れると、GAS はサーバ側で絞った結果を返し続けるため当日の表示は
  /// 正しいままだが、「当日以外のダイヤ」の表示が絞り込み済みの便に限られる。
  static const int schemaVersion = 4;

  final String endpointUrl;
  final http.Client _client;

  /// [selection] で選んだ停留所だけを取得する。
  /// 全停留所を返させると応答が数倍になるため、必ず絞る。
  Future<RemoteSchedule> fetchSchedule(StopSelection selection) async {
    final base = Uri.parse(endpointUrl);
    final uri = base.replace(queryParameters: {
      ...base.queryParameters,
      'v': '$schemaVersion',
      'stops': selection.query,
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('GAS API error: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw Exception('Server error: ${json['error']}');
    }

    // 旧形式かどうかは `trips` の有無では決まらない。当日の便が0本という
    // 応答も `trips: []` になるため、旧形式の目印である `current.schedules`
    // そのものを見る（#201）
    if (LegacyScheduleParser.isLegacyShape(json)) {
      final legacy = LegacyScheduleParser.parse(json);
      // 旧形式の形をしているのに読めない。**新形式として扱ってはいけない。**
      // fromJson は `schedules` を無視して通ってしまうため、そのまま進むと
      // 「便が0本」のキャッシュが保存されて #201 が再発する。
      // ここは取得経路なので、投げれば呼び出し側がキャッシュに退避する
      if (legacy == null) {
        throw Exception('Legacy response could not be parsed');
      }
      return RemoteScheduleLegacy(legacy);
    }

    return RemoteScheduleV4(ScheduleResponseModel.fromJson(json));
  }
}
