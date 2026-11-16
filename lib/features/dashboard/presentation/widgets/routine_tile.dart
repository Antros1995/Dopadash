import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../routines/domain/routine.dart';

class RoutineTile extends StatelessWidget {
  const RoutineTile({
    required this.definition,
    required this.entry,
    required this.onToggle,
    super.key,
  });

  final RoutineDefinition definition;
  final RoutineEntry entry;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active = entry.status == RoutineStatus.ok;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: Colors.transparent),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    routineIcon(definition.iconKey),
                    size: 19,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    definition.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 46,
                  height: 28,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch(
                      value: active,
                      onChanged: (_) => onToggle(),
                      thumbColor: WidgetStatePropertyAll(
                        active ? Colors.white : AppColors.textFaint,
                      ),
                      trackColor: WidgetStatePropertyAll(
                        active ? AppColors.green : AppColors.surfaceMuted,
                      ),
                      trackOutlineColor: const WidgetStatePropertyAll(
                        Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData routineIcon(String key) => switch (key) {
  'meditation' || 'mind' => Icons.self_improvement_rounded,
  'gym' => Icons.fitness_center_rounded,
  'food' => Icons.restaurant_rounded,
  'language' || 'cards' || 'study' => Icons.translate_rounded,
  'book' => Icons.menu_book_rounded,
  'wellness' => Icons.spa_rounded,
  'journal' => Icons.edit_note_rounded,
  'medication' => Icons.medication_rounded,
  'walking' => Icons.directions_walk_rounded,
  'career' => Icons.work_outline_rounded,
  _ => Icons.check_circle_outline_rounded,
};
