import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/services/error_reporter.dart';
import '../models/bus_schedule_model.dart';

class ScheduleRemoteSource {
  ScheduleRemoteSource({
    required this.endpointUrl,
    http.Client? client,
    ErrorReporter? errorReporter,
  }) : _client = client ?? http.Client(),
       _errorReporter = errorReporter;

  final String endpointUrl;
  final http.Client _client;
  final ErrorReporter? _errorReporter;

  Future<ScheduleResponseModel> fetchSchedule() async {
    final uri = Uri.parse(endpointUrl);
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('GAS API error: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        throw Exception('Server error: ${json['error']}');
      }

      return ScheduleResponseModel.fromJson(json);
    } catch (e, stack) {
      await _errorReporter?.recordError(e, stack);
      rethrow;
    }
  }
}
