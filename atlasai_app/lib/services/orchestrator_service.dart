import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the FastAPI Multi-Agent Orchestrator.
class OrchestratorService {
  final String baseUrl;

  // Replace with your Ubuntu machine's IP address
  OrchestratorService({
    this.baseUrl = 'https://ethack-genai.onrender.com',
  });

  Future<bool> ping() async {
    try {
      final url = Uri.parse('$baseUrl/ping');

      print("=================================");
      print("Calling backend...");
      print("URL: $url");

      final res = await http.get(url);

      print("Status Code: ${res.statusCode}");
      print("Response Body: ${res.body}");
      print("=================================");

      return res.statusCode == 200;
    } catch (e, stackTrace) {
      print("=================================");
      print("PING FAILED");
      print("Error: $e");
      print("StackTrace:");
      print(stackTrace);
      print("=================================");

      return false;
    }
  }

  /// Sends a query to the orchestrator's /query endpoint.
  ///
  /// CHANGE: added an optional `agents` parameter (List<String>?),
  /// defaulting to `null`. This is purely additive — every existing
  /// call site (chat screen, manager dashboard, action engine, etc.)
  /// that calls `query(...)` without `agents` behaves exactly as
  /// before, since `agents` is omitted from the request body when
  /// it's null. Only callers that explicitly pass `agents: [...]`
  /// (like the Auditor screen, restricting to compliance_agent) get
  /// the new field added to the JSON body.
  Future<Map<String, dynamic>> query(
    String userQuery, {
    String userRole = 'technician',
    String? equipmentId,
    List<String>? agents,
  }) async {
    final url = Uri.parse('$baseUrl/query');

    print("Sending query to: $url");

    // Build the request body. `agents` is only included when non-null,
    // so callers that don't pass it get the same body shape as before
    // (query, user_role, equipment_id) — no behavior change for them.
    final requestBody = {
      'query': userQuery,
      'user_role': userRole,
      'equipment_id': equipmentId,
      if (agents != null) 'agents': agents,
    };

    // Debug: log the exact outgoing request body so we can confirm
    // the Auditor screen (or any caller) is actually sending
    // agents: ["compliance_agent"] and not silently dropping it.
    print("===== Outgoing Request Body =====");
    print(jsonEncode(requestBody));

    final res = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    print("Query Status: ${res.statusCode}");
    print("Query Response: ${res.body}");

    if (res.statusCode != 200) {
      throw Exception(
        'Orchestrator error: ${res.statusCode}\n${res.body}',
      );
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;

    // Debug: log the fully decoded response so we can confirm the
    // "results" list shape (agent/answer/confidence/sources/reasoning)
    // matches what each screen expects to parse.
    print("===== Decoded Response =====");
    print(decoded);

    return decoded;
  }
}