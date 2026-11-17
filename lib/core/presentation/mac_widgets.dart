import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../i18n/i18n.dart';

/// Elementi di elenco condivisi, con lo stesso aspetto dell'Organizzatore:
/// casella tonda, etichette piccole, controllo a segmenti.

const macOrange = Color(0xFFE08600);

/// Casella tonda: bordo sottile nel colore dell'attività, pallino pieno
/// quando è fatta.
class MacCheck extends StatelessWidget {
  const MacCheck({
    required this.checked,
    required this.onTap,
    this.color = AppColors.textMuted,
    this.size = 20,
    this.label = 'Completa',
    super.key,
  });
  final bool checked;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: checked,
    button: true,
    label: label,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: checked ? 1 : .75),
              width: 1.5,
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: checked ? size * .58 : 0,
            height: checked ? size * .58 : 0,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    ),
  );
}

/// Etichetta piccola: grigia se [tone] manca, altrimenti tinta.
class MacChip extends StatelessWidget {
  const MacChip(this.label, {this.tone, this.maxWidth = 190, super.key});
  final String label;
  final Color? tone;
  final double maxWidth;

  /// Scadenza di un'attività: rossa se passata, arancione se è oggi.
  factory MacChip.due(
    DateTime date,
    DateTime today, {
    DateTime? dueAt,
    bool completed = false,
  }) {
    final day = DateUtils.dateOnly(date), now = DateUtils.dateOnly(today);
    final short =
        '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
    final time = dueAt != null && (dueAt.hour != 0 || dueAt.minute != 0)
        ? ' ${dueAt.hour.toString().padLeft(2, '0')}:${dueAt.minute.toString().padLeft(2, '0')}'
        : '';
    if (completed) return MacChip('$short$time');
    final days = day.difference(now).inDays;
    return days < 0
        ? MacChip(
            tr('scaduta $short', 'overdue $short'),
            tone: AppColors.danger,
          )
        : days == 0
        ? MacChip(tr('scade oggi$time', 'due today$time'), tone: macOrange)
        : MacChip(
            days == 1
                ? tr('scade domani$time', 'due tomorrow$time')
                : tr('scade $short$time', 'due $short$time'),
          );
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(maxWidth: maxWidth),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
    decoration: BoxDecoration(
      color: tone == null ? AppColors.fill : tone!.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: tone ?? AppColors.textMuted,
      ),
    ),
  );
}

/// Controllo a segmenti in stile Mac: fondo grigio, voce scelta bianca.
class MacSegmented<T> extends StatelessWidget {
  const MacSegmented({
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
    super.key,
  });
  final List<T> values;
  final T selected;
  final String Function(T) labelFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: AppColors.fill,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final value in values)
          Flexible(
            child: Semantics(
              selected: value == selected,
              button: true,
              child: InkWell(
                onTap: () => onSelected(value),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? AppColors.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: value == selected
                        ? const [
                            BoxShadow(
                              color: Color(0x2E000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labelFor(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: value == selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Riga sottile tra le voci di un elenco, rientrata sotto la casella.
class MacDivider extends StatelessWidget {
  const MacDivider({this.indent = 34, super.key});
  final double indent;
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, indent: indent, color: AppColors.border);
}
