import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'confidence_badge.dart';
import 'citation_chips.dart';

/// Day 6: the "Explainable AI panel" the plan calls for across all
/// screens — confidence score, source citations, reasoning trace.
/// Extracted from chat_screen.dart's inline block (unchanged visuals,
/// same three pieces: ConfidenceBadge, CitationChips, reasoning text)
/// so the Dashboard's AI Recommendations and Action Engine output can
/// show the same explainability, not a second, different-looking one.
class ExplainableAiPanel extends StatelessWidget {
  final double confidence;
  final List<String> sources;
  final String? reasoning;

  const ExplainableAiPanel({
    super.key,
    required this.confidence,
    this.sources = const [],
    this.reasoning,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [ConfidenceBadge(confidence: confidence)]),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          CitationChips(sources: sources),
        ],
        if (reasoning != null && reasoning!.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline, size: 13, color: AppColors.textFaint),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  reasoning!,
                  style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textFaint, fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}