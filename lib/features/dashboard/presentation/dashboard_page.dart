import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/app_card.dart';
import '../../../core/presentation/modular_board.dart';
import '../../investments/portfolio.dart';
import '../../markets/presentation/finance_widgets.dart';
import '../../../core/utils/date_formatters.dart';
import '../../calendar/application/calendar_controller.dart';
import '../../fitbit/application/fitbit_controller.dart';
import '../../organizer/application/organizer_controller.dart';
import '../../routines/application/routine_controller.dart';
import '../../tasks/application/task_controller.dart';
import '../../tasks/domain/dashboard_task.dart';
import 'widgets/calendar_card.dart';
import 'widgets/health_overview.dart';
import 'widgets/home_components.dart';
import 'widgets/organizer_summary_card.dart';
import 'widgets/task_card.dart';
import '../../../core/i18n/i18n.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.routines,
    required this.calendar,
    required this.fitbit,
    required this.tasks,
    this.onMarkets,
    this.portfolio,
    this.organizer,
    this.onOrganizer,
    this.scope = 'local',
    super.key,
  });
  final RoutineController routines;
  final CalendarController calendar;
  final FitbitController fitbit;
  final TaskController tasks;
  final VoidCallback? onMarkets;
  final PortfolioController? portfolio;
  final OrganizerController? organizer;
  final VoidCallback? onOrganizer;
  final String scope;
  @override
  State<DashboardPage> createState() => DashboardPageState();
}

class DashboardPageState extends State<DashboardPage> {
  final _scroll = ScrollController();
  final _board = GlobalKey<ModularBoardState>();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void showSection(String section) {
    if (section == 'Panoramica') {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _board.currentState?.showSection(section == 'Salute' ? 'Sonno' : section);
    }
  }

  Future<void> _selectDate(DateTime date) async {
    widget.tasks.selectDate(date);
    await Future.wait([
      widget.routines.selectDate(date),
      widget.calendar.selectDate(date),
      widget.fitbit.selectDate(date),
    ]);
  }

  void _openTasks(DashboardTaskGroup group) {
    final title = switch (group) {
      DashboardTaskGroup.personal => tr('Attività personali', 'Personal tasks'),
      DashboardTaskGroup.work => tr('Attività lavorative', 'Work tasks'),
      DashboardTaskGroup.personalWork => tr(
        'Attività Lavoro Personale',
        'Side-project tasks',
      ),
      DashboardTaskGroup.posta => tr('Posta', 'Mail'),
    };
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 700,
          height: 620,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: tr('Chiudi', 'Close'),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.tasks,
                  builder: (_, _) => DashboardTaskCard(
                    title: title,
                    icon: Icons.checklist,
                    group: group,
                    controller: widget.tasks,
                    fillAvailable: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.routines,
      widget.calendar,
      widget.fitbit,
      widget.tasks,
      if (widget.portfolio != null) widget.portfolio!,
    ]),
    builder: (context, _) {
      final day = widget.fitbit.day, date = widget.routines.selectedDate;
      final today = DateUtils.isSameDay(date, DateTime.now());
      final portfolio = widget.portfolio;
      return SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeHero(date: date, day: day, onSelectDate: _selectDate),
            ModularBoard(
              key: _board,
              area: 'monitoraggio',
              scope: widget.scope,
              modules: [
                if (day == null)
                  BoardModule(
                    'Sonno',
                    'Salute',
                    HealthOverview(controller: widget.fitbit, isToday: today),
                    height: 200,
                  )
                else ...[
                  BoardModule(
                    'Sonno',
                    'Sonno',
                    HealthOverview(
                      controller: widget.fitbit,
                      isToday: today,
                      panel: 'sleep',
                    ),
                    columns: 5,
                    height: 282,
                    minHeight: 282,
                    mobileHeight: 356,
                    scroll: false,
                  ),
                  BoardModule(
                    'Stato del corpo',
                    'Stato del corpo',
                    HealthOverview(
                      controller: widget.fitbit,
                      isToday: today,
                      panel: 'body',
                    ),
                    columns: 3,
                    height: 282,
                    minHeight: 282,
                    mobileHeight: 310,
                    scroll: false,
                  ),
                  BoardModule(
                    'Insight',
                    'Insight di oggi',
                    HealthOverview(
                      controller: widget.fitbit,
                      isToday: today,
                      panel: 'insight',
                    ),
                    columns: 4,
                    height: 282,
                    minHeight: 282,
                    mobileHeight: 350,
                    scroll: false,
                  ),
                  BoardModule(
                    'Parametri',
                    'Parametri salute',
                    HealthOverview(
                      controller: widget.fitbit,
                      isToday: today,
                      panel: 'metrics',
                    ),
                    height: 205,
                  ),
                ],
                if (widget.organizer != null)
                  BoardModule(
                    'Organizzatore',
                    'Organizzatore',
                    OrganizerSummaryCard(
                      controller: widget.organizer!,
                      onOpen: widget.onOrganizer ?? () {},
                    ),
                    height: 290,
                    minHeight: 220,
                    mobileHeight: 440,
                    scroll: false,
                  ),
                BoardModule(
                  'Routine',
                  'Routine',
                  HomeRoutineCard(controller: widget.routines),
                  columns: 4,
                  height: 270,
                  minHeight: 260,
                  mobileHeight: 360,
                  scroll: false,
                ),
                BoardModule(
                  'Calendario',
                  'Calendario',
                  DashboardCalendarCard(controller: widget.calendar),
                  columns: 4,
                  height: 430,
                  mobileHeight: 430,
                  minHeight: 260,
                  scroll: false,
                ),
                BoardModule(
                  'Attività personali',
                  'Attività personali',
                  HomeTaskPreview(
                    title: tr('Attività personali', 'Personal tasks'),
                    group: DashboardTaskGroup.personal,
                    controller: widget.tasks,
                    onOpen: () => _openTasks(DashboardTaskGroup.personal),
                  ),
                  columns: 4,
                  height: 138,
                  mobileHeight: 190,
                  minHeight: 120,
                  scroll: false,
                ),
                BoardModule(
                  'Attività lavorative',
                  'Attività lavorative',
                  HomeTaskPreview(
                    title: tr('Attività lavorative', 'Work tasks'),
                    group: DashboardTaskGroup.work,
                    controller: widget.tasks,
                    onOpen: () => _openTasks(DashboardTaskGroup.work),
                  ),
                  columns: 4,
                  height: 138,
                  mobileHeight: 190,
                  minHeight: 120,
                  scroll: false,
                ),
                BoardModule(
                  'Attività lavoro personale',
                  'Attività lavoro personale',
                  HomeTaskPreview(
                    title: tr(
                      'Attività lavoro personale',
                      'Side-project tasks',
                    ),
                    group: DashboardTaskGroup.personalWork,
                    controller: widget.tasks,
                    onOpen: () => _openTasks(DashboardTaskGroup.personalWork),
                  ),
                  columns: 4,
                  height: 138,
                  mobileHeight: 190,
                  minHeight: 120,
                  scroll: false,
                ),
                BoardModule(
                  'Investimenti',
                  'Investimenti',
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HomeHeading(
                          title: tr('Investimenti', 'Investments'),
                          icon: Icons.trending_up,
                          action: widget.onMarkets == null
                              ? null
                              : HomeLink(
                                  label: tr(
                                    'Apri Investimenti',
                                    'Open Investments',
                                  ),
                                  onTap: widget.onMarkets!,
                                ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          portfolio == null || portfolio.loading
                              ? tr(
                                  'Portafoglio non caricato',
                                  'Portfolio not loaded',
                                )
                              : amount(portfolio.totalValue),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        if (portfolio != null && !portfolio.loading)
                          Text(
                            '${portfolio.complete ? tr('Risultato', 'Result') : tr('Valore parziale EUR', 'Partial value EUR')} · ${portfolio.complete ? amount(portfolio.profit) : tr('quotazioni mancanti', 'missing quotes')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (portfolio != null && !portfolio.loading) ...[
                          const SizedBox(height: 10),
                          // Ultimi sei mesi: valore del portafoglio e capitale versato.
                          Builder(
                            builder: (context) {
                              final end = DateTime.now();
                              final history = portfolio.historyFor(
                                DateTime(end.year, end.month - 6, end.day),
                                end,
                              );
                              return history.length < 2
                                  ? Text(
                                      tr(
                                        'Andamento non disponibile: mancano le quotazioni storiche.',
                                        'Trend unavailable: historical quotes are missing.',
                                      ),
                                      style: TextStyle(fontSize: 11),
                                    )
                                  : FinanceChart(
                                      points: [
                                        for (final p in history)
                                          TimeValue(p.date, p.value),
                                      ],
                                      second: [
                                        for (final p in history)
                                          TimeValue(p.date, p.capital),
                                      ],
                                      label: tr('Portafoglio', 'Portfolio'),
                                      secondLabel: tr(
                                        'Capitale netto',
                                        'Net capital',
                                      ),
                                      height: 170,
                                      connectGaps: false,
                                    );
                            },
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          tr(
                            'Ultimi 6 mesi · prezzi con data e fonte nel portafoglio.',
                            'Last 6 months · prices with date and source in the portfolio.',
                          ),
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  columns: 4,
                  height: 400,
                ),
                BoardModule(
                  'Posta',
                  'Posta',
                  HomeTaskPreview(
                    title: tr('Posta', 'Mail'),
                    group: DashboardTaskGroup.posta,
                    controller: widget.tasks,
                    onOpen: () => _openTasks(DashboardTaskGroup.posta),
                  ),
                  columns: 4,
                  height: 240,
                  mobileHeight: 260,
                  minHeight: 140,
                  scroll: false,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${capitalize(formatLongDate(date))} · ${tr('Dati delle integrazioni collegate', 'Data from connected services')}',
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
          ],
        ),
      );
    },
  );
}
