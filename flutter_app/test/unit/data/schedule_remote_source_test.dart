import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:chitose_bus/data/sources/schedule_remote_source.dart';

class MockHttpClient extends Mock implements http.Client {}

const _validJson = {
  'updatedAt': '2024-01-01',
  'current': {
    'validFrom': '2024-01-01',
    'validTo': '2024-03-31',
    'pdfUrl': '',
    'schedules': [
      {
        'time': '09:30',
        'direction': 'from_chitose',
        'destination': 'Chitose',
        'arrivals': <String, String>{},
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

  group('ScheduleRemoteSource.fetchSchedule', () {
    test('returns ScheduleResponseModel on 200 response', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response(jsonEncode(_validJson), 200),
      );

      final result = await source.fetchSchedule();
      expect(result.updatedAt, '2024-01-01');
      expect(result.current.schedules.length, 1);
      expect(result.upcoming, isNull);
    });

    test('throws Exception on non-200 response', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('Not Found', 404),
      );

      expect(() => source.fetchSchedule(), throwsException);
    });

    test('throws Exception when body contains "error" key', () async {
      final errorJson = jsonEncode({'error': 'Something went wrong'});
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response(errorJson, 200),
      );

      expect(() => source.fetchSchedule(), throwsException);
    });

    test('throws FormatException on malformed JSON body', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('not-json', 200),
      );

      expect(() => source.fetchSchedule(), throwsA(isA<FormatException>()));
    });

    test('throws Exception on 500 response', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('Internal Server Error', 500),
      );

      expect(() => source.fetchSchedule(), throwsException);
    });

    test('sends GET to the correct endpoint URL', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response(jsonEncode(_validJson), 200),
      );

      await source.fetchSchedule();

      verify(() => mockClient.get(Uri.parse(endpointUrl))).called(1);
    });
  });
}
