import 'dart:convert';
import 'package:http/http.dart' as http;

/// Day 6: talks to POST /actions/generate — same base URL pattern as
/// OrchestratorService, kept as a separate small client rather than
/// merged into it since it's a distinct backend concern (action
/// generation vs. query answering), matching how /capture endpoints
/// got their own capture_service.dart on Day 5.
class ActionEngineService {
  final String baseUrl;

  ActionEngineService({
    // Keep this in sync with OrchestratorService's baseUrl — same
    // backend machine.
    this.baseUrl = 'https://ethack-genai.onrender.com',
  });

  Future<Map<String, dynamic>> generate({
    required String actionType, // rca_report | maintenance_checklist | inspection_schedule | audit_report
    String? query,
    String? equipmentId,
    String userRole = 'technician',
  }) async {
    final url = Uri.parse('$baseUrl/actions/generate');

    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action_type': actionType,
        'query': query,
        'equipment_id': equipmentId,
        'user_role': userRole,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Action Engine error: ${res.statusCode}\n${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}