/// Represents one turn in the Knowledge Agent chat.
/// Assistant messages carry the extra fields the backend now returns:
/// merged_answer, per-agent confidence, and source citations —
/// this is what the Explainable AI panel (badge + chips) renders from.
class ChatMessage {
  final String text;
  final bool isUser;
  final double? confidence; // null for user messages
  final List<String> sources;
  final String? reasoning;
  final bool isError;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.confidence,
    this.sources = const [],
    this.reasoning,
    this.isError = false,
  });

  /// Builds the assistant message straight from the /query response body.
  ///
  /// FIX: previously this pooled `sources` from every agent that ran
  /// (via `sources.addAll(...)` across all `results`) and always took
  /// `reasoning` from `results.first`. But `merged_answer` — the text
  /// actually shown to the user — is the orchestrator's *preferred*
  /// agent's answer (knowledge_agent if it ran, per orchestrator.py's
  /// `_route`/merge logic; otherwise whichever ran). When a query
  /// triggers more than one agent (e.g. a maintenance-flavored
  /// question also matches knowledge_agent), the citation chips and
  /// reasoning text were silently mixing in a *different* agent's
  /// sources/reasoning than the one backing the displayed answer —
  /// so citation numbers and the confidence badge didn't reliably
  /// correspond to the text on screen.
  ///
  /// Now this mirrors the backend's own selection: pick the same
  /// single "primary" result (knowledge_agent if present, else the
  /// first result) and take confidence/sources/reasoning from that
  /// one result only, in its original order — consistent with what's
  /// actually displayed.
  factory ChatMessage.fromOrchestratorResponse(Map<String, dynamic> json) {
    final results = List<Map<String, dynamic>>.from(
      (json['results'] as List? ?? const []).map((r) => Map<String, dynamic>.from(r)),
    );

    Map<String, dynamic>? primary;
    if (results.isNotEmpty) {
      primary = results.firstWhere(
        (r) => r['agent'] == 'knowledge_agent',
        orElse: () => results.first,
      );
    }

    final sources = primary != null
        ? List<String>.from(primary['sources'] ?? const [])
        : <String>[];
    final reasoning = primary?['reasoning'] as String?;
    final confidence = primary != null
        ? (primary['confidence'] as num?)?.toDouble() ?? 0.0
        : (json['overall_confidence'] as num?)?.toDouble() ?? 0.0;

    return ChatMessage(
      text: json['merged_answer'] as String? ?? '',
      isUser: false,
      confidence: confidence,
      sources: sources,
      reasoning: reasoning,
    );
  }
}