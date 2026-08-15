import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus_schedule_model.dart';
import '../../domain/entities/stop_selection.dart';

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
  Future<ScheduleResponseModel> fetchSchedule(StopSelection selection) async {
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

    return ScheduleResponseModel.fromJson(json);
  }
}
