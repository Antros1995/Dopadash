import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/presentation/app_card.dart';

class EmptyModuleCard extends StatelessWidget {
  const EmptyModuleCard({
    required this.title,
    required this.message,
    required this.icon,
    this.statusLabel = 'Non collegato',
    this.minHeight = 180,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final String statusLabel;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SizedBox(
        height: minHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
              title: title,
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  statusLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 24, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
