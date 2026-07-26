/// Day 6: Plant Intelligence Dashboard data shapes.
/// All computed client-side from the `documents` Firestore collection
/// (fields written by storage_service.dart since Day 5: fileName,
/// uploadedBy, uploadedAt, status, linkedEquipmentIds, docType,
/// similarIncidents, alertSent) — no new backend endpoint needed, same
/// pattern the Lessons Learned Timeline already uses to read Firestore
/// directly.
library;

class CriticalAsset {
  final String equipmentId;
  final int incidentCount;
  final DateTime? lastIncidentDate;

  CriticalAsset({
    required this.equipmentId,
    required this.incidentCount,
    this.lastIncidentDate,
  });
}

/// A single matched past-incident record, as returned by
/// lessons_learned_service.find_similar_incidents() and persisted onto
/// the ingested document's `similarIncidents` field. Carries the real
/// substance of the match (snippet + similarity score + source file)
/// rather than just a count, so the dashboard can show what the AI
/// actually found instead of a generic "N similar incidents" line.
class SimilarIncidentMatch {
  final String fileName;
  final String? equipmentId;
  final double similarity;
  final String snippet;

  SimilarIncidentMatch({
    required this.fileName,
    this.equipmentId,
    required this.similarity,
    required this.snippet,
  });
}

class RecentAlert {
  final String fileName;
  final String? equipmentId;
  final DateTime? uploadedAt;
  // The actual matched past incidents behind this alert (snippet,
  // similarity, source file) — this is the real insight. Kept as a
  // list (already sorted by similarity descending upstream) so the
  // UI can show the single best match, or all of them.
  final List<SimilarIncidentMatch> matches;

  RecentAlert({
    required this.fileName,
    this.equipmentId,
    this.uploadedAt,
    this.matches = const [],
  });

  // Kept for backward compatibility with any existing call site that
  // only wants the count (e.g. "N similar incident(s)" copy) — now
  // derived from the real match list instead of being a separately
  // passed-in number.
  int get matchCount => matches.length;

  // The single most relevant match, if any — used to surface one
  // concrete, real insight sentence on the dashboard instead of just
  // a count.
  SimilarIncidentMatch? get bestMatch => matches.isEmpty ? null : matches.first;
}

class DashboardStats {
  final int totalDocuments;
  final int totalEquipment;
  final int coveredEquipment; // has an SOP/manual on file
  final double decayScore; // 0-100, higher = staler documentation
  final List<CriticalAsset> criticalAssets;
  final List<RecentAlert> recentAlerts;

  DashboardStats({
    required this.totalDocuments,
    required this.totalEquipment,
    required this.coveredEquipment,
    required this.decayScore,
    required this.criticalAssets,
    required this.recentAlerts,
  });

  double get coveragePercent =>
      totalEquipment == 0 ? 0 : (coveredEquipment / totalEquipment) * 100;

  factory DashboardStats.empty() => DashboardStats(
        totalDocuments: 0,
        totalEquipment: 0,
        coveredEquipment: 0,
        decayScore: 0,
        criticalAssets: [],
        recentAlerts: [],
      );
}