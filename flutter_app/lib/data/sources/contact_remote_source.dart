import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ContactRemoteSource {
  ContactRemoteSource({required this.endpointUrl});

  final String endpointUrl;

  Future<void> sendReport({
    required String category,
    required String description,
    String steps = '',
    @visibleForTesting http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final request = http.Request('POST', Uri.parse(endpointUrl))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'category': category, 'description': description, 'steps': steps})
        ..followRedirects = false;

      final streamed =
          await c.send(request).timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamed);

      if (response.statusCode == 302) {
        final location = response.headers['location'];
        if (location != null) {
          response = await c
              .get(Uri.parse(location))
              .timeout(const Duration(seconds: 30));
        }
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] != true) {
        throw Exception(body['error'] ?? '送信に失敗しました');
      }
    } finally {
      c.close();
    }
  }
}
