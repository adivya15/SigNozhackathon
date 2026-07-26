import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/dashboard_stats.dart';

/// Day 6: computes Plant Intelligence Dashboard metrics from the
/// `documents` collection. Deliberately simple, stated heuristics
/// rather than anything presented as ML-derived — same philosophy as
/// the backend's Compliance Agent (Day 6): a metric you can explain in
/// one sentence and defend under a judge's question beats one that
/// just sounds sophisticated.
class DashboardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // NOTE: _coverageDocTypes previously restricted "covered" equipment
  // to those with an SOP/manual/knowledge_capture doc. Per the fix
  // below, coverage is now "any linked document at all", so that
  // filter is no longer used.

  /// Decay score heuristic: average document age in days, scaled so
  /// 90+ days average age reads as fully "stale" (100). Adjust
  /// _decayWindowDays to match your plant's actual review cadence.
  static const _decayWindowDays = 90;

  Future<DashboardStats> loadStats() async {
    final snapshot = await _db.collection('documents').get();
    final docs = snapshot.docs.map((d) => d.data()).toList();

    if (docs.isEmpty) return DashboardStats.empty();

    final equipmentDocTypes = <String, Set<String>>{};
    final incidentCounts = <String, int>{};
    final incidentLastDate = <String, DateTime>{};
    final alerts = <RecentAlert>[];
    var totalAgeDays = 0.0;
    var agedDocCount = 0;

    for (final doc in docs) {
      final docType = doc['docType'] as String? ?? 'general_document';
      final linkedIds = List<String>.from(doc['linkedEquipmentIds'] ?? const []);
      final uploadedAtTs = doc['uploadedAt'] as Timestamp?;
      final uploadedAt = uploadedAtTs?.toDate();

      for (final eq in linkedIds) {
        equipmentDocTypes.putIfAbsent(eq, () => {}).add(docType);
      }

      if (docType == 'incident') {
        for (final eq in linkedIds) {
          incidentCounts[eq] = (incidentCounts[eq] ?? 0) + 1;
          if (uploadedAt != null) {
            final existing = incidentLastDate[eq];
            if (existing == null || uploadedAt.isAfter(existing)) {
              incidentLastDate[eq] = uploadedAt;
            }
          }
        }
      }

      if (uploadedAt != null) {
        totalAgeDays += DateTime.now().difference(uploadedAt).inDays;
        agedDocCount++;
      }

      final alertSent = doc['alertSent'] as bool? ?? false;
      if (alertSent) {
        final similarIncidentsRaw = List<Map<String, dynamic>>.from(
          (doc['similarIncidents'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map)),
        );

        // CHANGE: previously only `similarIncidents.length` was kept
        // (matchCount), discarding the actual match content the
        // backend already computed and stored (fileName, equipmentId,
        // similarity, snippet — see lessons_learned_service.py). That
        // discarded detail is exactly what turned the dashboard's "AI
        // Recommendations" into a generic templated line instead of a
        // real insight. Now the full match list is kept so the UI can
        // show the actual matched incident text.
        final matches = similarIncidentsRaw.map((m) {
          return SimilarIncidentMatch(
            fileName: m['fileName'] as String? ?? 'unknown',
            equipmentId: m['equipmentId'] as String?,
            similarity: (m['similarity'] as num?)?.toDouble() ?? 0.0,
            snippet: m['snippet'] as String? ?? '',
          );
        }).toList()
          ..sort((a, b) => b.similarity.compareTo(a.similarity));

        alerts.add(RecentAlert(
          fileName: doc['fileName'] as String? ?? 'unknown',
          equipmentId: linkedIds.isNotEmpty ? linkedIds.first : null,
          uploadedAt: uploadedAt,
          matches: matches,
        ));
      }
    }

    final totalEquipment = equipmentDocTypes.length;
    // FIX: previously this only counted equipment whose linked docs
    // intersected _coverageDocTypes (SOP/manual/knowledge_capture),
    // which meant equipment with only e.g. maintenance_record or
    // incident docs counted as "uncovered" even though something is
    // clearly documented about them — driving Knowledge Coverage to
    // 0% whenever no SOP/manual had been ingested yet. Per the fix
    // requested: any equipment with at least one linked document of
    // any type counts as covered.
    final coveredEquipment = equipmentDocTypes.length;

    final avgAgeDays = agedDocCount == 0 ? 0.0 : totalAgeDays / agedDocCount;
    final decayScore = (avgAgeDays / _decayWindowDays * 100).clamp(0, 100).toDouble();

    final criticalAssets = incidentCounts.entries
        .map((e) => CriticalAsset(
              equipmentId: e.key,
              incidentCount: e.value,
              lastIncidentDate: incidentLastDate[e.key],
            ))
        .toList()
      ..sort((a, b) => b.incidentCount.compareTo(a.incidentCount));

    alerts.sort((a, b) => (b.uploadedAt ?? DateTime(2000)).compareTo(a.uploadedAt ?? DateTime(2000)));

    // FIX: previously, if no ingested document ever had alertSent ==
    // true (i.e. nothing matched a past incident closely enough to
    // trigger the ingestion-time alert), `alerts` stayed empty and
    // the Manager Dashboard always showed "No pattern alerts yet",
    // even when the same equipment clearly had a repeated-failure
    // trend sitting right there in `incidentCounts`. Now, only when
    // there are no real alertSent alerts, synthesize recommendations
    // straight from incident counts using the three priority tiers
    // requested. This reuses RecentAlert/SimilarIncidentMatch exactly
    // as they already exist — no new models — by carrying the
    // priority title in SimilarIncidentMatch.fileName and the
    // message in SimilarIncidentMatch.snippet, which is what
    // ManagerHome's existing card already renders for a "best match".
    if (alerts.isEmpty) {
      final synthesized = <RecentAlert>[];

      for (final entry in incidentCounts.entries) {
        final equipmentId = entry.key;
        final incidentCount = entry.value;

        String title;
        String message;
        double severity; // stand-in "match strength" so the existing
                          // UI's percentage read still makes sense —
                          // higher tier = higher displayed strength.

        if (incidentCount >= 8) {
          title = 'High Priority Recommendation';
          message = '$equipmentId has $incidentCount recorded incidents. '
              'Perform Root Cause Analysis immediately and schedule preventive maintenance.';
          severity = 1.0;
        } else if (incidentCount >= 5) {
          title = 'Medium Priority Recommendation';
          message = '$equipmentId is showing repeated failures. '
              'Increase inspection frequency and review maintenance procedures.';
          severity = 0.7;
        } else if (incidentCount >= 3) {
          title = 'Low Priority Recommendation';
          message = 'Continue monitoring $equipmentId. '
              'Consider preventive inspection if the trend continues.';
          severity = 0.4;
        } else {
          continue; // below the lowest tier — no recommendation yet.
        }

        synthesized.add(RecentAlert(
          fileName: title,
          equipmentId: equipmentId,
          uploadedAt: incidentLastDate[equipmentId],
          matches: [
            SimilarIncidentMatch(
              fileName: title,
              equipmentId: equipmentId,
              similarity: severity,
              snippet: message,
            ),
          ],
        ));
      }

      // Highest incident count first, so High Priority recommendations
      // surface before Medium/Low ones.
      synthesized.sort((a, b) =>
          (incidentCounts[b.equipmentId] ?? 0).compareTo(incidentCounts[a.equipmentId] ?? 0));

      alerts.addAll(synthesized);
    }

    return DashboardStats(
      totalDocuments: docs.length,
      totalEquipment: totalEquipment,
      coveredEquipment: coveredEquipment,
      decayScore: decayScore,
      criticalAssets: criticalAssets.take(5).toList(),
      recentAlerts: alerts.take(5).toList(),
    );
  }
}