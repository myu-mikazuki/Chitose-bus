import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus_schedule_model.dart';

class ScheduleRemoteSource {
  ScheduleRemoteSource({required this.endpointUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String endpointUrl;
  final http.Client _client;

  Future<ScheduleResponseModel> fetchSchedule() async {
    final uri = Uri.parse(endpointUrl);
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
