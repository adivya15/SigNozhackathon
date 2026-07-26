import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';

/// Equipment Timeline — all documents (SOPs, maintenance records,
/// incidents, knowledge captures) linked to one equipment ID, in
/// reverse-chronological order, plus a computed Health Score.
///
/// The Health Score is a deliberately simple, stated heuristic rather
/// than anything presented as ML-derived — same philosophy
/// DashboardService already uses for its Knowledge Decay score
/// ("a metric you can explain in one sentence and defend under a
/// judge's question beats one that just sounds sophisticated"):
///
///   Health Score = 100
///     - up to 50 points for total incident count (12 pts/incident)
///     - 15 points if any incident was logged in the last 30 days
///     - 20 points if there's no SOP/manual/knowledge-capture on file
///
/// Reads the same `documents` Firestore collection every other Day 6
/// screen already reads — no new backend endpoint needed.
class EquipmentTimelineScreen extends StatelessWidget {
  final String equipmentId;
  const EquipmentTimelineScreen({super.key, required this.equipmentId});

  static const _coverageDocTypes = {'sop', 'manual', 'knowledge_capture'};

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('documents')
        .where('linkedEquipmentIds', arrayContains: equipmentId)
        .orderBy('uploadedAt', descending: true)
        .limit(100);

    return Scaffold(
      appBar: AppBar(title: Text('Equipment Timeline — $equipmentId')),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(message: snapshot.error.toString());
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const _EmptyState();
          }

          final health = _computeHealth(docs);

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: docs.length + 1, // +1 for the health score card
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _HealthScoreCard(health: health),
                );
              }
              final data = docs[i - 1].data() as Map<String, dynamic>;
              return _TimelineCard(data: data, isLast: i - 1 == docs.length - 1);
            },
          );
        },
      ),
    );
  }

  /// Real, explainable heuristic — see class doc comment for the
  /// exact point breakdown. Computed client-side from the same
  /// document metadata every other dashboard/timeline screen reads.
  _EquipmentHealth _computeHealth(List<QueryDocumentSnapshot> docs) {
    var incidentCount = 0;
    var hasRecentIncident = false;
    var hasCoverageDoc = false;
    final now = DateTime.now();

    for (final snap in docs) {
      final data = snap.data() as Map<String, dynamic>;
      final docType = data['docType'] as String? ?? 'general_document';
      final uploadedAt = (data['uploadedAt'] as Timestamp?)?.toDate();

      if (docType == 'incident') {
        incidentCount++;
        if (uploadedAt != null && now.difference(uploadedAt).inDays <= 30) {
          hasRecentIncident = true;
        }
      }
      if (_coverageDocTypes.contains(docType)) {
        hasCoverageDoc = true;
      }
    }

    final incidentPenalty = (incidentCount * 12).clamp(0, 50);
    final recencyPenalty = hasRecentIncident ? 15 : 0;
    final docGapPenalty = hasCoverageDoc ? 0 : 20;

    final score = (100 - incidentPenalty - recencyPenalty - docGapPenalty).clamp(0, 100);

    final reasons = <String>[];
    if (incidentCount > 0) {
      reasons.add('$incidentCount incident(s) on record (-$incidentPenalty)');
    }
    if (hasRecentIncident) {
      reasons.add('an incident in the last 30 days (-$recencyPenalty)');
    }
    if (!hasCoverageDoc) {
      reasons.add('no SOP/manual on file (-$docGapPenalty)');
    }
    if (reasons.isEmpty) {
      reasons.add('no incidents and documentation is on file');
    }

    return _EquipmentHealth(score: score.toDouble(), reasons: reasons);
  }
}

class _EquipmentHealth {
  final double score;
  final List<String> reasons;
  _EquipmentHealth({required this.score, required this.reasons});
}

class _HealthScoreCard extends StatelessWidget {
  final _EquipmentHealth health;
  const _HealthScoreCard({required this.health});

  Color get _color {
    if (health.score >= 70) return AppColors.success;
    if (health.score >= 40) return AppColors.warning;
    return AppColors.danger;
  }

  String get _label {
    if (health.score >= 70) return 'Healthy';
    if (health.score >= 40) return 'Needs Attention';
    return 'At Risk';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: _color.withOpacity(0.4)),
                ),
                child: Center(
                  child: Text(
                    health.score.toStringAsFixed(0),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _color),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Health Score', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      _label,
                      style: TextStyle(color: _color, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // The explainable part — same "state it plainly" philosophy
          // as the rest of Day 6: exactly why this number is what it
          // is, not a black-box score.
          ...health.reasons.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle, size: 5, color: AppColors.textFaint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isLast;
  const _TimelineCard({required this.data, required this.isLast});

  IconData _iconFor(String docType) {
    switch (docType) {
      case 'incident':
        return Icons.warning_amber_rounded;
      case 'sop':
      case 'manual':
        return Icons.menu_book_outlined;
      case 'maintenance_record':
        return Icons.build_outlined;
      case 'knowledge_capture':
        return Icons.record_voice_over_outlined;
      case 'compliance':
        return Icons.fact_check_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Color _colorFor(String docType) {
    if (docType == 'incident') return AppColors.warning;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final fileName = data['fileName'] as String? ?? 'Unknown document';
    final docType = data['docType'] as String? ?? 'general_document';
    final timestamp = data['uploadedAt'] as Timestamp?;
    final similarIncidents = List<dynamic>.from(data['similarIncidents'] ?? const []);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: _colorFor(docType), shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_iconFor(docType), size: 16, color: _colorFor(docType)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(fileName, style: Theme.of(context).textTheme.titleMedium),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        docType.replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textFaint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (timestamp != null) ...[
                        const SizedBox(height: 4),
                        Text(_formatTimestamp(timestamp), style: Theme.of(context).textTheme.bodySmall),
                      ],
                      if (docType == 'incident' && similarIncidents.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Matched ${similarIncidents.length} similar past incident(s)',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp ts) {
    final dt = ts.toDate();
    return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_outlined, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No documents linked to this equipment yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load timeline.\n$message',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This may need a Firestore composite index (linkedEquipmentIds + uploadedAt) — check the debug console for a direct link to create it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}