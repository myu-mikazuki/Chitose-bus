import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:kagi_bus/data/sources/schedule_remote_source.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';

class MockHttpClient extends Mock implements http.Client {}

/// GAS の v=4 応答（1便を1件、停留所と時刻の並び）
const _validJson = {
  'updatedAt': '2024-01-01',
  'stopMaster': [
    {'id': 'chitose', 'label': '千歳駅前'},
    {'id': 'honbuto', 'label': '科技大本部棟'},
  ],
  'current': {
    'validFrom': '2024-01-01',
    'validTo': '2024-03-31',
    'trips': [
      {
        'destination': '科技大',
        'routeLabel': '空港経由',
        'weekdayOnly': false,
        'weekendOnly': false,
        'academicOnly': false,
        'vacationOnly': false,
        'stops': [
          {'id': 'chitose', 'time': '09:30', 'platform': '5番'},
          {'id': 'honbuto', 'time': '09:55'},
        ],
      },
    ],
  },
  'upcoming': null,
};

/// GAS が未デプロイ・またはロールバックされたときに返る旧形式（v<=3）
const _legacyJson = {
  'updatedAt': '2026-08-01',
  'current': {
    'validFrom': '2026-04-01',
    'validTo': '2026-09-30',
    'schedules': [
      {
        'time': '07:20',
        'direction': 'from_minami_chitose',
        'destination': '科技大',
        'arrivals': {'honbuto': '07:45'},
      },
    ],
  },
};

void main() {
  late MockHttpClient mockClient;
  late ScheduleRemoteSource source;
  const endpointUrl = 'http://example.com/schedule';

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://example.com'));
  });

  setUp(() {
    mockClient = MockHttpClient();
    source = ScheduleRemoteSource(endpointUrl: endpointUrl, client: mockClient);
  });

  /// http.Response は既定で latin1 として扱うため、日本語を含む本文は
  /// バイト列で渡す（実際の GAS も UTF-8 で返す）
  void respondOk() {
    when(() => mockClient.get(any())).thenAnswer(
      (_) async =>
          http.Response.bytes(utf8.encode(jsonEncode(_validJson)), 200),
    );
  }

  group('ScheduleRemoteSource.fetchSchedule', () {
    test('returns ScheduleResponseModel on 200 response', () async {
      respondOk();

      final result = await source.fetchSchedule(StopSelection.initial);
      final model = (result as RemoteScheduleV4).model;
      expect(model.updatedAt, '2024-01-01');
      expect(model.current.trips.length, 1);
      expect(model.stopMaster.length, 2);
      expect(model.upcoming, isNull);
    });

    test('throws Exception on non-200 response', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('Not Found', 404),
      );

      expect(
          () => source.fetchSchedule(StopSelection.initial), throwsException);
    });

    test('throws Exception when body contains "error" key', () async {
      final errorJson = jsonEncode({'error': 'Something went wrong'});
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response(errorJson, 200),
      );

      expect(
          () => source.fetchSchedule(StopSelection.initial), throwsException);
    });

    test('throws FormatException on malformed JSON body', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('not-json', 200),
      );

      expect(
        () => source.fetchSchedule(StopSelection.initial),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws Exception on 500 response', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('Internal Server Error', 500),
      );

      expect(
          () => source.fetchSchedule(StopSelection.initial), throwsException);
    });

    test('v=4 と選択した停留所を付けて GET する', () async {
      respondOk();

      await source.fetchSchedule(StopSelection.initial);

      final uri =
          verify(() => mockClient.get(captureAny())).captured.single as Uri;
      expect(uri.queryParameters['v'], '4');
      expect(
        uri.queryParameters['stops'],
        'chitose,minamiChitose,kenkyuto,honbuto',
      );
    });

    test('選択を変えると stops も変わる', () async {
      respondOk();

      await source.fetchSchedule(
        const StopSelection(stopIds: ['chitose', 'morimoto']),
      );

      final uri =
          verify(() => mockClient.get(captureAny())).captured.single as Uri;
      expect(uri.queryParameters['stops'], 'chitose,morimoto');
    });

    test('既存のクエリパラメータを保持したまま v と stops を付与する', () async {
      final s = ScheduleRemoteSource(
        endpointUrl: 'http://example.com/schedule?foo=bar',
        client: mockClient,
      );
      respondOk();

      await s.fetchSchedule(StopSelection.initial);

      final uri =
          verify(() => mockClient.get(captureAny())).captured.single as Uri;
      expect(uri.queryParameters['foo'], 'bar');
      expect(uri.queryParameters['v'], '4');
      expect(uri.queryParameters['stops'], isNotNull);
    });
  });

  group('旧形式の応答を見分ける（#201）', () {
    void respondLegacy() {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async =>
            http.Response.bytes(utf8.encode(jsonEncode(_legacyJson)), 200),
      );
    }

    test('current.schedules があれば旧形式として解釈する', () async {
      respondLegacy();

      final result = await source.fetchSchedule(StopSelection.initial);

      final entity = (result as RemoteScheduleLegacy).entity;
      expect(entity.updatedAt, '2026-08-01');
      expect(entity.current.schedules.single.time, '07:20');
      expect(entity.current.schedules.single.boardingStopId, 'minamiChitose');
    });

    test('旧形式が持っているのは既定の4停留所だけと伝える', () async {
      respondLegacy();

      // 選択に無い停留所を渡しても、旧形式が持っているのは4停留所ぶん。
      // ここを選択で埋めると、足した停留所が「便が0本」として出てしまう
      final result = await source.fetchSchedule(
        const StopSelection(stopIds: ['chitose', 'morimoto']),
      );

      final entity = (result as RemoteScheduleLegacy).entity;
      expect(entity.covers('chitose'), isTrue);
      expect(entity.covers('morimoto'), isFalse);
    });

    test('当日の便が0本の v=4 応答は旧形式に倒さない', () async {
      // trips: [] だけを見て判定すると、正常な「便が0本」の応答まで
      // 旧形式扱いになり保存されなくなる
      final emptyJson = {
        'updatedAt': '2024-01-01',
        'current': {'validFrom': '', 'validTo': '', 'trips': <dynamic>[]},
      };
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response(jsonEncode(emptyJson), 200),
      );

      final result = await source.fetchSchedule(StopSelection.initial);

      expect(result, isA<RemoteScheduleV4>());
    });

    test('旧形式の形をしていて読めないなら、新形式に倒さず投げる', () async {
      // fromJson は schedules を無視して通ってしまう。ここで倒すと
      // 「便が0本」のキャッシュが保存されて #201 が再発する
      final brokenJson = {
        'updatedAt': '2026-08-01',
        'current': {
          'schedules': [
            {'time': 720, 'destination': '科技大'},
          ],
        },
      };
      when(() => mockClient.get(any())).thenAnswer(
        (_) async =>
            http.Response.bytes(utf8.encode(jsonEncode(brokenJson)), 200),
      );

      expect(
        () => source.fetchSchedule(StopSelection.initial),
        throwsException,
      );
    });
  });
}
