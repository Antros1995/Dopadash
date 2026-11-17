import 'package:flutter/material.dart';
import '../../../../app/theme.dart';
import '../../../../core/presentation/app_card.dart';
import '../../../../core/presentation/mac_widgets.dart';
import 'home_components.dart';
import '../../../../core/utils/external_url_launcher.dart';
import '../../../calendar/application/calendar_controller.dart';
import '../../../calendar/data/calendar_repository.dart';
import '../../../calendar/domain/calendar_event.dart';
import '../../../../core/i18n/i18n.dart';

class DashboardCalendarCard extends StatefulWidget {
  const DashboardCalendarCard({required this.controller, super.key});

  final CalendarController controller;

  @override
  State<DashboardCalendarCard> createState() => DashboardCalendarCardState();
}

class DashboardCalendarCardState extends State<DashboardCalendarCard> {
  final _scrollController = ScrollController();
  bool _isConnecting = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeading(
            title: DateUtils.isSameDay(controller.selectedDate, DateTime.now())
                ? tr('Calendario di oggi', 'Today’s calendar')
                : tr('Calendario del giorno', 'Day’s calendar'),
            icon: Icons.calendar_month,
            color: const Color(0xFF249FFE),
            action: IconButton(
              onPressed: controller.isConfigured && !controller.isLoading
                  ? controller.load
                  : null,
              tooltip: tr('Aggiorna calendario', 'Refresh calendar'),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _calendarBody(controller)),
        ],
      ),
    );
  }

  Widget _calendarBody(CalendarController controller) {
    if (!controller.isConfigured) {
      return _CalendarMessage(
        icon: Icons.link_off_rounded,
        text: tr('Calendario non collegato.', 'Calendar not connected.'),
      );
    }
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    final failure = controller.failure;
    if (failure != null) {
      final canConnect =
          failure.kind == CalendarFailureKind.outlookNotConnected;
      final canReconnect = failure.kind == CalendarFailureKind.unavailable;
      return _CalendarMessage(
        icon: Icons.event_busy_rounded,
        text: _calendarFailureMessage(failure.kind),
        action: canConnect
            ? TextButton(
                onPressed: _isConnecting
                    ? null
                    : () => _connectOutlook(controller),
                child: Text(
                  _isConnecting
                      ? tr('Apertura…', 'Opening…')
                      : tr('Collega Outlook', 'Connect Outlook'),
                ),
              )
            : canReconnect
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: controller.load,
                    child: Text(tr('Riprova', 'Try again')),
                  ),
                  TextButton(
                    onPressed: _isConnecting
                        ? null
                        : () => _connectOutlook(controller),
                    child: Text(
                      _isConnecting
                          ? tr('Apertura...', 'Opening...')
                          : tr('Ricollega Outlook', 'Reconnect Outlook'),
                    ),
                  ),
                ],
              )
            : TextButton(
                onPressed: controller.load,
                child: Text(tr('Riprova', 'Try again')),
              ),
      );
    }
    final events = controller.events;
    if (events.isEmpty) {
      return _CalendarMessage(
        icon: Icons.event_available_rounded,
        text: tr(
          'Nessun evento Outlook per questo giorno.',
          'No Outlook events on this day.',
        ),
      );
    }
    return ScrollbarTheme(
      data: _quietScrollbarTheme,
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: false,
        interactive: true,
        thickness: 8,
        radius: const Radius.circular(8),
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          itemCount: events.length,
          separatorBuilder: (_, _) => const MacDivider(indent: 62),
          itemBuilder: (context, index) =>
              _CalendarEventRow(event: events[index]),
        ),
      ),
    );
  }

  Future<void> _connectOutlook(CalendarController controller) async {
    setState(() => _isConnecting = true);
    try {
      final authorizationUrl = await controller.beginOutlookConnect();
      final launched = await launchExternalUrl(authorizationUrl);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Impossibile aprire il browser.',
                'Couldn’t open the browser.',
              ),
            ),
          ),
        );
        return;
      }

      // OAuth is completed in a separate browser window. Poll the protected
      // calendar endpoint so this card updates as soon as the callback stores
      // the Microsoft tokens, without requiring a manual page refresh.
      for (var attempt = 0; attempt < 150; attempt += 1) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        await controller.load();
        if (!mounted) return;
        if (controller.failure == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  'Outlook collegato e aggiornato.',
                  'Outlook connected and refreshed.',
                ),
              ),
            ),
          );
          return;
        }
        if (controller.failure?.kind !=
            CalendarFailureKind.outlookNotConnected) {
          return;
        }
      }
    } on CalendarFailure {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Connessione Outlook non disponibile.',
                'Outlook connection unavailable.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }
}

const _quietScrollbarTheme = ScrollbarThemeData(
  thumbColor: WidgetStatePropertyAll(Color(0x3D9A9AA0)),
  trackColor: WidgetStatePropertyAll(Colors.transparent),
  trackBorderColor: WidgetStatePropertyAll(Colors.transparent),
);

class _CalendarEventRow extends StatelessWidget {
  const _CalendarEventRow({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.startLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                if (!event.isAllDay)
                  Text(
                    event.endLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 10),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
                if (event.location.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  MacChip(event.location, maxWidth: 240),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarMessage extends StatelessWidget {
  const _CalendarMessage({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textFaint),
          const SizedBox(height: AppSpacing.xs),
          Text(text, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    );
  }
}

String _calendarFailureMessage(CalendarFailureKind kind) {
  return switch (kind) {
    CalendarFailureKind.outlookNotConnected => tr(
      'Outlook non è ancora collegato.',
      'Outlook isn’t connected yet.',
    ),
    CalendarFailureKind.sessionExpired => tr(
      'Sessione scaduta. Esci e accedi nuovamente.',
      'Session expired. Sign out and sign in again.',
    ),
    CalendarFailureKind.notAllowed => tr(
      'Questo account non è autorizzato per il calendario personale.',
      'This account isn’t allowed to use the personal calendar.',
    ),
    CalendarFailureKind.invalidResponse => tr(
      'Il calendario ha restituito dati non validi.',
      'The calendar returned invalid data.',
    ),
    CalendarFailureKind.unavailable => tr(
      'La mailbox Outlook collegata non \u00e8 disponibile.',
      'The connected Outlook mailbox is unavailable.',
    ),
  };
}
