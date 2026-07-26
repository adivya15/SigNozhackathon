import 'package:flutter/material.dart';

/// Small colored badge showing an agent's confidence score, with a
/// short filled bar alongside the percentage so it reads at a glance
/// without requiring the person to parse the number. Green >= 0.7,
/// amber 0.4-0.69, red < 0.4 — matches the Explainable AI panel
/// described in the plan (confidence score, sources, reasoning).
class ConfidenceBadge extends StatelessWidget {
  final double confidence;
  const ConfidenceBadge({super.key, required this.confidence});

  Color get _color {
    if (confidence >= 0.7) return Colors.green;
    if (confidence >= 0.4) return Colors.amber.shade800;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).toStringAsFixed(0);
    final clamped = confidence.clamp(0.0, 1.0);
    return Tooltip(
      message: 'Confidence is based on how closely the retrieved documents '
          'matched the question (green ≥ 70%, amber 40-69%, red < 40%).',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights, size: 13, color: _color),
            const SizedBox(width: 4),
            Text(
              'Confidence $pct%',
              style: TextStyle(fontSize: 11, color: _color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            // NEW: a small filled bar as a quick visual read of the
            // same number, so the badge isn't purely text.
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                width: 32,
                height: 4,
                child: Stack(
                  children: [
                    Container(color: _color.withOpacity(0.15)),
                    FractionallySizedBox(
                      widthFactor: clamped,
                      child: Container(color: _color),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}