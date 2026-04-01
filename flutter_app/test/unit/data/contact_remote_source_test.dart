import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:kagi_bus/data/sources/contact_remote_source.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockClient;
  late ContactRemoteSource source;
  const endpointUrl = 'http://example.com/contact';

  setUpAll(() {
    registerFallbackValue(http.Request('POST', Uri.parse('http://example.com')));
    registerFallbackValue(Uri.parse('http://example.com'));
  });

  setUp(() {
    mockClient = MockHttpClient();
    when(() => mockClient.close()).thenReturn(null);
    source = ContactRemoteSource(endpointUrl: endpointUrl);
  });

  group('ContactRemoteSource.sendReport', () {
    test('succeeds when response has success: true', () async {
      when(() => mockClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'success': true}))),
          200,
        ),
      );

      await expectLater(
        source.sendReport(
          category: 'バグ報告',
          description: 'テスト内容',
          client: mockClient,
        ),
        completes,
      );
    });

    test('throws Exception when success is false', () async {
      when(() => mockClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'success': false, 'error': 'bad request'}))),
          200,
        ),
      );

      await expectLater(
        source.sendReport(
          category: 'バグ報告',
          description: 'テスト内容',
          client: mockClient,
        ),
        throwsException,
      );
    });

    test('includes category in request body', () async {
      http.Request? capturedRequest;
      when(() => mockClient.send(any())).thenAnswer((invocation) async {
        capturedRequest = invocation.positionalArguments[0] as http.Request;
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'success': true}))),
          200,
        );
      });

      await source.sendReport(
        category: '機能要望',
        description: 'テスト内容',
        client: mockClient,
      );

      final body = jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
      expect(body['category'], '機能要望');
    });

    test('includes description in request body', () async {
      http.Request? capturedRequest;
      when(() => mockClient.send(any())).thenAnswer((invocation) async {
        capturedRequest = invocation.positionalArguments[0] as http.Request;
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'success': true}))),
          200,
        );
      });

      await source.sendReport(
        category: 'その他',
        description: '詳細な説明',
        client: mockClient,
      );

      final body = jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
      expect(body['description'], '詳細な説明');
    });

    test('follows 302 redirect and parses redirected response', () async {
      when(() => mockClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode('')),
          302,
          headers: {'location': 'http://example.com/redirected'},
        ),
      );
      when(() => mockClient.get(Uri.parse('http://example.com/redirected')))
          .thenAnswer(
        (_) async => http.Response(jsonEncode({'success': true}), 200),
      );

      await expectLater(
        source.sendReport(
          category: 'バグ報告',
          description: 'テスト内容',
          client: mockClient,
        ),
        completes,
      );
    });
  });
}
