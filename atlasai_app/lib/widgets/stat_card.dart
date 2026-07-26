import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;
  final String? subtitle;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // LAYOUT CHANGE: mainAxisSize.min tells this Column to size
        // itself to the height its children actually need, instead
        // of trying to fill all available vertical space (the
        // Column's default). Combined with removing Spacer below,
        // this makes the card's height purely a function of its
        // content — which is exactly what lets it grow when a
        // subtitle wraps to a second line on a narrow screen, instead
        // of relying on an external fixed-height/aspect-ratio
        // constraint from the parent grid.
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          // LAYOUT CHANGE: replaced `const Spacer()` with a fixed
          // SizedBox. Spacer expands to fill whatever bounded height
          // its parent Column is given — that only worked previously
          // because GridView.count's fixed childAspectRatio: 1.5 gave
          // this Column a fixed height to expand into. Now that the
          // card is allowed to grow to fit its content (see
          // manager_home.dart's _ResponsiveStatGrid), there's no
          // guaranteed bounded height for Spacer to expand into, so a
          // fixed gap is used instead — visually similar spacing
          // between the label row and the value, but content-driven
          // instead of space-filling.
          const SizedBox(height: AppSpacing.sm),

          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),

          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              // LAYOUT CHANGE: maxLines raised from 2 to 3 and
              // overflow left as ellipsis as a safety net — but since
              // the card can now grow vertically (no fixed aspect
              // ratio forcing a clip), a wrapped 2-3 line subtitle on
              // a narrow phone displays in full instead of relying on
              // truncation to hide what used to overflow the fixed
              // box.
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}