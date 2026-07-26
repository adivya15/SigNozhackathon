import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the Knowledge Capture Agent's dedicated endpoints
/// (separate from /query — this is a scripted interview flow, not a
/// chat exchange). Same baseUrl convention as OrchestratorService:
/// 10.0.2.2 for Android emulator, adjust for other targets.
class CaptureService {
  final String baseUrl;
  CaptureService({this.baseUrl = 'https://ethack-genai.onrender.com'});

  Future<List<String>> fetchQuestions({String? equipmentId}) async {
    final uri = Uri.parse('$baseUrl/capture/questions').replace(
      queryParameters: equipmentId != null ? {'equipment_id': equipmentId} : null,
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to load questions: ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return List<String>.from(body['questions'] ?? []);
  }

  Future<Map<String, dynamic>> submitAnswers({
    String? equipmentId,
    String? technicianId,
    required List<Map<String, String>> answers,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/capture/submit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'equipment_id': equipmentId,
        'technician_id': technicianId,
        'answers': answers,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to submit: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
