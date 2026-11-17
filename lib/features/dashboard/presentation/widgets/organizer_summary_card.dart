import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/presentation/app_card.dart';
import '../../../organizer/application/organizer_controller.dart';
import '../../../organizer/domain/organizer_summary.dart';
import 'home_components.dart';
import '../../../../core/i18n/i18n.dart';

/// Visione d'insieme dell'Organizzatore nella Home: quattro numeri e le cose
/// da non perdere, in ordine di urgenza. Si legge soltanto; per modificare si
/// apre l'Organizzatore.
class OrganizerSummaryCard extends StatefulWidget {
  const OrganizerSummaryCard({
    required this.controller,
    required this.onOpen,
    super.key,
  });
  final OrganizerController controller;
  final VoidCallback onOpen;
  @override
  State<OrganizerSummaryCard> createState() => _OrganizerSummaryCardState();
}

class _OrganizerSummaryCardState extends State<OrganizerSummaryCard> {
  final _scroll = ScrollController();
  static const _orange = Color(0xFFE08600), _purple = Color(0xFF9B51C9);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final s = widget.controller.summary;
      final stats = [
        _Stat(
          tr('Oggi', 'Today'),
          s.focus,
          AppColors.green,
          Icons.wb_sunny_outlined,
        ),
        _Stat(
          tr('Tocca a me', 'My move'),
          s.mine,
          _orange,
          Icons.person_outline,
        ),
        _Stat(tr('In attesa', 'Waiting'), s.waiting, _purple, Icons.schedule),
        _Stat(
          tr('In scadenza', 'Due'),
          s.due,
          AppColors.danger,
          Icons.event_outlined,
        ),
      ];
      final list = s.items.isEmpty
          ? Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  s.open == 0
                      ? tr(
                          'Nessuna casella aperta. Apri l’Organizzatore per scrivere la prima.',
                          'No open boxes. Open the Organizer to write the first one.',
                        )
                      : tr(
                          'Niente di urgente: nessuna scadenza e nessun sollecito.',
                          'Nothing urgent: no deadlines and no nudges.',
                        ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            )
          : Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              thickness: 6,
              radius: const Radius.circular(8),
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.only(right: 10),
                itemCount: s.items.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) =>
                    _Row(item: s.items[i], onTap: widget.onOpen),
              ),
            );
      return AppCard(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeHeading(
              title: tr('Organizzatore', 'Organizer'),
              icon: Icons.sticky_note_2_outlined,
              action: HomeLink(
                label: tr('Apri ›', 'Open ›'),
                onTap: widget.onOpen,
              ),
            ),
            if (widget.controller.hasRemote && !widget.controller.synced)
              Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  tr(
                    'Solo su questo dispositivo · sincronizzazione non attiva',
                    'Only on this device · sync is off',
                  ),
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ),
            if (s.milestones.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  itemCount: s.milestones.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _MilestoneChip(
                    milestone: s.milestones[i],
                    onTap: widget.onOpen,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  if (box.maxWidth >= 640) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 250,
                          child: Column(
                            children: [
                              for (var r = 0; r < 2; r++) ...[
                                if (r > 0) const SizedBox(height: 8),
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: stats[r * 2]),
                                      const SizedBox(width: 8),
                                      Expanded(child: stats[r * 2 + 1]),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(child: list),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 62,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < stats.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              Expanded(child: stats[i]),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(child: list),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _MilestoneChip extends StatelessWidget {
  const _MilestoneChip({required this.milestone, required this.onTap});
  final OrganizerMilestone milestone;
  final VoidCallback onTap;

  /// Tempo mancante in giorni, mesi o anni, come nell'Organizzatore:
  /// "5 giorni", "3 mesi", "oggi", "2 giorni fa".
  static String countdown(int days) {
    if (days == 0) return tr('oggi', 'today');
    final a = days.abs();
    final months = (a / 30.44).round().clamp(1, 12);
    final years = (a / 365).round().clamp(1, 999);
    final text = a < 31
        ? '$a ${a == 1 ? tr('giorno', 'day') : tr('giorni', 'days')}'
        : a < 365
        ? '$months ${months == 1 ? tr('mese', 'month') : tr('mesi', 'months')}'
        : '$years ${years == 1 ? tr('anno', 'year') : tr('anni', 'years')}';
    return days < 0 ? tr('$text fa', '$text ago') : text;
  }

  @override
  Widget build(BuildContext context) {
    final m = milestone;
    final tone = m.daysLeft < 0
        ? AppColors.danger
        : m.daysLeft <= 3
        ? const Color(0xFFE08600)
        : Color(m.color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                countdown(m.daysLeft),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tone,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                m.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${m.due.substring(8, 10)}/${m.due.substring(5, 7)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color, this.icon);
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 100 || box.maxHeight < 70;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 10,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: value == 0 ? .05 : .10),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (!compact) ...[
                  Icon(icon, size: 17, color: color),
                  const Spacer(),
                ],
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: compact ? 19 : 24,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: value == 0 ? AppColors.textFaint : AppColors.text,
                  ),
                ),
              ],
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.onTap});
  final OrganizerItem item;
  final VoidCallback onTap;

  static String _date(String ymd) =>
      ymd.length >= 10 ? '${ymd.substring(8, 10)}/${ymd.substring(5, 7)}' : ymd;

  @override
  Widget build(BuildContext context) {
    final color = Color(item.color);
    final (String label, Color tone) = switch (item.reason) {
      OrganizerReason.focus => (tr('Oggi', 'Today'), AppColors.green),
      OrganizerReason.due => (
        item.late
            ? tr('Scaduta ${_date(item.due)}', 'Overdue ${_date(item.due)}')
            : tr('Scade oggi', 'Due today'),
        AppColors.danger,
      ),
      OrganizerReason.nudge => (
        tr('Sollecita ${item.who}', 'Nudge ${item.who}'),
        const Color(0xFFE08600),
      ),
      OrganizerReason.next => (
        tr('Prossimo passo', 'Next step'),
        AppColors.textMuted,
      ),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .18),
                shape: BoxShape.circle,
              ),
              child: Text(item.emoji, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    item.reason != OrganizerReason.nudge && item.who.isNotEmpty
                        ? tr(
                            '${item.project} · aspetto ${item.who}',
                            '${item.project} · waiting for ${item.who}',
                          )
                        : item.project,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(maxWidth: 150),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tone,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
