import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';

/// Day 5 deliverable: visualizes recurring failure patterns by listing
/// incident-classified documents in reverse-chronological order, with
/// a badge showing how many historical incidents each one matched
/// (from the similarIncidents field storage_service.dart now persists).
class LessonsLearnedTimelineScreen extends StatelessWidget {
  const LessonsLearnedTimelineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('documents')
        .where('docType', isEqualTo: 'incident')
        .orderBy('uploadedAt', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(title: const Text('Lessons Learned Timeline')),
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
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              return _TimelineCard(data: data, isLast: i == docs.length - 1);
            },
          );
        },
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isLast;
  const _TimelineCard({required this.data, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final fileName = data['fileName'] as String? ?? 'Unknown document';
    final equipmentIds = List<String>.from(data['linkedEquipmentIds'] ?? []);
    final similarIncidents = List<dynamic>.from(data['similarIncidents'] ?? []);
    final timestamp = data['uploadedAt'] as Timestamp?;
    final matchCount = similarIncidents.length;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12, height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: matchCount > 0 ? AppColors.warning : AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppColors.border),
                ),
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
                          Expanded(
                            child: Text(fileName, style: Theme.of(context).textTheme.titleMedium),
                          ),
                          if (matchCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.warningBg,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                '$matchCount match${matchCount > 1 ? 'es' : ''}',
                                style: const TextStyle(
                                  fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (timestamp != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(timestamp),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (equipmentIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: equipmentIds.map((id) => Chip(
                            label: Text(id, style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.precision_manufacturing_outlined, size: 13),
                          )).toList(),
                        ),
                      ],
                      if (similarIncidents.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Text(
                          'Matched historical incidents:',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        ...similarIncidents.map((m) {
                          final match = Map<String, dynamic>.from(m as Map);
                          final similarity = (match['similarity'] as num?)?.toDouble() ?? 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.link, size: 13, color: AppColors.textFaint),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${match['fileName'] ?? 'document'} — ${(similarity * 100).toStringAsFixed(0)}% similar',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
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
              'No incidents reported yet.\nUpload an incident report to see it appear here.',
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
              'This may need a Firestore composite index (docType + uploadedAt) — check the debug console for a direct link to create it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
