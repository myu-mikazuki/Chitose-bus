import 'dart:convert';

import 'package:http/http.dart' as http;

class BugReportRemoteSource {
  BugReportRemoteSource({required this.endpointUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String endpointUrl;
  final http.Client _client;

  Future<void> sendReport({
    required String description,
    required String steps,
  }) async {
    final request = http.Request('POST', Uri.parse(endpointUrl))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'description': description, 'steps': steps})
      ..followRedirects = false;

    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 30));
    var response = await http.Response.fromStream(streamed);

    if (response.statusCode == 302) {
      final location = response.headers['location'];
      if (location != null) {
        response = await _client
            .get(Uri.parse(location))
            .timeout(const Duration(seconds: 30));
      }
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw Exception(body['error'] ?? '送信に失敗しました');
    }
  }
}
