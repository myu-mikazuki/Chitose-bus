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
      (_) async => http.Response.bytes(utf8.encode(jsonEncode(_validJson)), 200),
    );
  }

  group('ScheduleRemoteSource.fetchSchedule', () {
    test('returns ScheduleResponseModel on 200 response', () async {
      respondOk();

      final result = await source.fetchSchedule(StopSelection.initial);
      expect(result.updatedAt, '2024-01-01');
      expect(result.current.trips.length, 1);
      expect(result.stopMaster.length, 2);
      expect(result.upcoming, isNull);
    });

    test('throws Exception on non-200 response', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('Not Found', 404),
      );

      expect(() => source.fetchSchedule(StopSelection.initial), throwsException);
    });

    test('throws Exception when body contains "error" key', () async {
      final errorJson = jsonEncode({'error': 'Something went wrong'});
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response(errorJson, 200),
      );

      expect(() => source.fetchSchedule(StopSelection.initial), throwsException);
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

      expect(() => source.fetchSchedule(StopSelection.initial), throwsException);
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
}
