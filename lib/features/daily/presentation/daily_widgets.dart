import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/presentation/app_card.dart';
import '../../../core/presentation/mac_widgets.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../routines/domain/routine.dart' show shiftDays;
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/date_formatters.dart';

/// Elementi condivisi dalle schede Quotidianità e Sport.

const dailyPageTitle = TextStyle(
  fontSize: 28,
  height: 1.15,
  fontWeight: FontWeight.w700,
  letterSpacing: -.56,
  color: AppColors.text,
);

const dailyPurple = Color(0xFF7A5AF8);
const dailyBlue = Color(0xFF2F7BF6);

/// "lunedì 16 novembre" / "Monday 16 November".
String weekdayDate(DateTime d) =>
    '${weekdayName(d)} ${d.day} ${monthName(d.month)}';

String clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Intestazione di pagina: titolo, giorno e frecce per cambiare data.
class DailyHeader extends StatelessWidget {
  const DailyHeader({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.today,
    required this.onSelectDate,
    super.key,
  });
  final String title, subtitle;
  final DateTime date, today;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(date, today);
    final label = isToday
        ? tr('Oggi', 'Today')
        : DateUtils.isSameDay(date, shiftDays(today, -1))
        ? tr('Ieri', 'Yesterday')
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    Widget arrow(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      onPressed: onTap,
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20),
    );
    final picker = Container(
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(
            Icons.chevron_left,
            tr('Giorno precedente', 'Previous day'),
            () => onSelectDate(shiftDays(date, -1)),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2026),
                lastDate: today,
              );
              if (picked != null) onSelectDate(picked);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
          arrow(
            Icons.chevron_right,
            tr('Giorno successivo', 'Next day'),
            isToday ? null : () => onSelectDate(shiftDays(date, 1)),
          ),
        ],
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: dailyPageTitle),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        ),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: text),
        const SizedBox(width: 12),
        Padding(padding: const EdgeInsets.only(top: 2), child: picker),
        if (!isToday && !usesPhoneLayout(context)) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: () => onSelectDate(today),
              child: Text(tr('Torna a oggi', 'Back to today')),
            ),
          ),
        ],
      ],
    );
  }
}

/// Scheda bianca con titolo, stato a destra e contenuto.
class DailySection extends StatelessWidget {
  const DailySection({
    required this.icon,
    required this.title,
    required this.child,
    this.color = AppColors.green,
    this.status,
    this.action,
    super.key,
  });
  final IconData icon;
  final String title;
  final Color color;
  final Widget? status, action;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
            ?status,
            if (action != null) ...[const SizedBox(width: 6), action!],
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

/// Etichetta di stato: verde con spunta se fatto, grigia se da compilare.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.done, required this.label, super.key});
  final bool done;
  final String label;
  @override
  Widget build(BuildContext context) =>
      MacChip(done ? '✓ $label' : label, tone: done ? AppColors.green : null);
}

/// Scala da 1 a 5: cinque cerchi grandi, quello scelto si riempie.
class LevelScale extends StatelessWidget {
  const LevelScale({
    required this.value,
    required this.onSelected,
    this.color = AppColors.green,
    this.labels = const {},
    super.key,
  });
  final int? value;
  final ValueChanged<int> onSelected;
  final Color color;
  final Map<int, String> labels;

  @override
  Widget build(BuildContext context) {
    final size = usesPhoneLayout(context) ? 46.0 : 40.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (var i = 1; i <= 5; i++)
              Semantics(
                button: true,
                selected: value == i,
                label: tr(
                  '$i su 5${labels[i] == null ? '' : ', ${labels[i]}'}',
                  '$i of 5${labels[i] == null ? '' : ', ${labels[i]}'}',
                ),
                child: InkWell(
                  onTap: () => onSelected(i),
                  customBorder: const CircleBorder(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value == null
                          ? AppColors.fill
                          : i <= value!
                          ? color.withValues(alpha: i == value ? 1 : .22)
                          : AppColors.fill,
                    ),
                    child: Text(
                      '$i',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: value == i ? Colors.white : AppColors.text,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (value != null && labels[value] != null) ...[
          const SizedBox(height: 6),
          Text(
            labels[value]!,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ],
    );
  }
}

/// Scelta a pillola: grigia, oppure tinta quando è selezionata.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.green,
    this.leading,
    super.key,
  });
  final String label;
  final String? leading;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: usesPhoneLayout(context) ? 9 : 7,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .16) : AppColors.fill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null && leading!.isNotEmpty) ...[
              Text(leading!, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Avviso di errore con "Riprova", uguale in tutte le sezioni.
class DailyErrorBanner extends StatelessWidget {
  const DailyErrorBanner({required this.onRetry, super.key});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, size: 17, color: AppColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            tr(
              'Non riesco a leggere o salvare i dati. Controlla la connessione.',
              'I can’t read or save the data. Check the connection.',
            ),
            style: TextStyle(fontSize: 12.5, color: AppColors.danger),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(tr('Riprova', 'Try again'))),
      ],
    ),
  );
}

/// Due colonne affiancate sugli schermi larghi, una sotto l'altra sul telefono.
class TwoColumns extends StatelessWidget {
  const TwoColumns({required this.left, required this.right, super.key});
  final Widget left, right;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth >= 720
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: left),
                const SizedBox(width: 12),
                Expanded(child: right),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 12), right],
          ),
  );
}
