import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Tappable chips for each source document cited in an answer.
/// The chip's number corresponds to the [n] citation markers the
/// Knowledge Agent / Action Engine actually use inline in the answer
/// text — sources are passed straight through from a single agent's
/// result in their original retrieval order (see chat_message.dart's
/// fix), so chip #1 really is [1] in the text above it.
class CitationChips extends StatelessWidget {
  final List<String> sources;
  const CitationChips({super.key, required this.sources});

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: sources.asMap().entries.map((entry) {
        final i = entry.key + 1;
        final source = entry.value;
        return ActionChip(
          avatar: CircleAvatar(
            backgroundColor: Colors.blueGrey.shade100,
            child: Text('$i', style: const TextStyle(fontSize: 11)),
          ),
          label: Text(
            // CHANGE: was truncated to 24 chars, which cut off most
            // "filename.pdf (page N)" style source strings mid-word.
            // Widened to 40 chars — still bounded so a very long
            // filename can't blow out the chip row, but shows enough
            // to actually be useful before opening the detail sheet.
            source.length > 40 ? '${source.substring(0, 40)}…' : source,
            style: const TextStyle(fontSize: 11),
          ),
          onPressed: () => _showSourceDetail(context, index: i, source: source),
        );
      }).toList(),
    );
  }

  // CHANGE: replaced the old SnackBar (which flashed briefly and
  // still truncated long source text off-screen) with a proper modal
  // bottom sheet — shows the citation number matching the answer's
  // [n] marker, the full un-truncated source string, and stays open
  // until dismissed so it's actually readable.
  void _showSourceDetail(BuildContext context, {required int index, required String source}) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.primary.withOpacity(0.12),
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Citation $index',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                source,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                'Referenced as [$index] in the answer above.',
                style: const TextStyle(fontSize: 12, color: AppColors.textFaint, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        );
      },
    );
  }
}