import 'dart:async';
import 'dashboard_frame.dart';
import '../../../core/storage/key_value_store_factory.dart';
import '../../../core/sync/app_sync_coordinator.dart';
import '../../markets/data/local_market_repository.dart';
import '../../investments/portfolio.dart';
import '../../investments/investments_page.dart';

import 'package:flutter/material.dart';

import '../../../app/dependencies.dart';
import '../../auth/presentation/mfa_settings_dialog.dart';
import '../../tasks/domain/dashboard_task.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../../data_export/data/diet_export.dart';
import '../../statistics/data/compare_sources.dart';
import '../../data_export/presentation/data_export_page.dart';
import '../../calendar/application/calendar_controller.dart';
import '../../fitbit/application/fitbit_controller.dart';
import '../../markets/application/market_controller.dart';
import '../../markets/presentation/markets_page.dart';
import '../../routines/application/routine_controller.dart';
import '../../tasks/application/task_controller.dart';
import '../../tasks/application/posta_calendar_sync.dart';
import '../../tasks/presentation/todo_page.dart';
import '../../calendar/data/calendar_repository.dart';
import '../../expenses/application/expense_controller.dart';
import '../../expenses/data/expense_repository.dart';
import '../../expenses/presentation/expenses_page.dart';
import '../../fitbit/data/fitbit_repository.dart';
import '../../statistics/application/body_statistics_controller.dart';
import '../../statistics/data/body_statistics_repository.dart';
import '../../statistics/presentation/body_statistics_page.dart';
import '../../daily/application/daily_controller.dart';
import '../../daily/data/daily_repository.dart';
import '../../../core/config/app_config.dart';
import '../../nutrition/nutrition_host.dart';
import '../../wardrobe/wardrobe_page.dart';
import '../../wardrobe/wardrobe_repository.dart';
import '../../daily/presentation/daily_page.dart';
import '../../daily/presentation/recap_view.dart';
import '../../daily/presentation/sport_page.dart';
import '../../organizer/application/organizer_controller.dart';
import '../../organizer/data/organizer_local_store.dart';
import '../../organizer/data/organizer_remote.dart';
import '../../organizer/presentation/organizer_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late final RoutineController _routines;
  late final CalendarController _calendar;
  late final FitbitController _fitbit;
  late final MarketController _markets;
  late final TaskController _tasks;
  late final PostaCalendarSync _postaSync;
  late final PortfolioController _portfolio;
  late final ExpenseController _expenses;
  late final BodyStatisticsController _bodyStatistics;
  late final AppSyncCoordinator _sync;
  bool _expensesLoaded = false;
  bool _statisticsOpened = false;
  bool _organizerOpened = false;
  late final OrganizerController _organizer;
  late final DailyController _daily;
  final _dailyKey = GlobalKey<DailyPageState>();
  final _sportKey = GlobalKey<SportPageState>();
  final _wardrobeKey = GlobalKey<WardrobePageState>();
  bool _wardrobeOpened = false;
  final _expenseKey = GlobalKey<ExpensesPageState>();
  late final String _scope;
  final _todoKey = GlobalKey<TodoPageState>();
  final _marketKey = GlobalKey<MarketsPageState>();
  final _portfolioKey = GlobalKey<InvestmentsPageState>();
  late final List<Widget> _pages;
  int _selectedIndex = 0;
  String _section = 'Panoramica';
  final _dashboardKey = GlobalKey<DashboardPageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _routines = RoutineController(
      repository: widget.dependencies.routineRepository,
    );
    _scope =
        widget.dependencies.supabaseClientService.client.auth.currentUser?.id ??
        'local';
    final store = createKeyValueStore();
    final market = LocalMarketRepository(
      widget.dependencies.marketRepository,
      store,
      _scope,
    );
    _markets = MarketController(repository: market);
    _portfolio = PortfolioController(
      store: store,
      market: market,
      scope: _scope,
    );
    unawaited(_portfolio.load());
    final calendarSource = widget.dependencies.calendarRepository;
    _expenses = ExpenseController(
      repository: SupabaseExpenseRepository(
        widget.dependencies.supabaseClientService.client,
        calendarSource is PersonalAgentCalendarRepository
            ? calendarSource.apiBaseUrl
            : null,
      ),
    );
    _calendar = CalendarController(
      repository: widget.dependencies.calendarRepository,
      initialDate: _routines.selectedDate,
    );
    _fitbit = FitbitController(
      repository: widget.dependencies.fitbitRepository,
      initialDate: _routines.selectedDate,
    );
    final fitbitRepository = widget.dependencies.fitbitRepository;
    _bodyStatistics = BodyStatisticsController(
      repository: SupabaseBodyStatisticsRepository(
        widget.dependencies.supabaseClientService.client,
        historySource: fitbitRepository is PersonalAgentFitbitRepository
            ? fitbitRepository.fetchStatisticsHistory
            : null,
        daySource: fitbitRepository is PersonalAgentFitbitRepository
            ? fitbitRepository.fetchStatisticsDay
            : null,
      ),
    );
    _tasks = TaskController(
      repository: widget.dependencies.taskRepository,
      initialDate: _routines.selectedDate,
      cacheStore: store,
      cacheScope: _scope,
    );
    _postaSync = PostaCalendarSync(calendar: _calendar, tasks: _tasks);
    final account = widget.dependencies.supabaseClientService.client;
    _organizer = OrganizerController(
      store: createOrganizerLocalStore(),
      remote: account.auth.currentUser == null
          ? null
          : SupabaseOrganizerRemote(account),
    )..start();
    _daily = DailyController(
      repository: SupabaseDailyRepository(account),
      initialDate: _routines.selectedDate,
      onScreenTimeChanged: () => unawaited(_routines.refreshSilently()),
    )..start();
    // La data scelta nella Home vale anche per Quotidianità e Sport.
    _routines.addListener(_followRoutineDate);
    _pages = [
      DashboardPage(
        key: _dashboardKey,
        routines: _routines,
        calendar: _calendar,
        fitbit: _fitbit,
        tasks: _tasks,
        onMarkets: () => _selectPage(4),
        portfolio: _portfolio,
        organizer: _organizer,
        onOrganizer: () => _selectPage(7),
        scope: _scope,
      ),
      TodoPage(key: _todoKey, controller: _tasks, scope: _scope),
      MarketsPage(key: _marketKey, controller: _markets, scope: _scope),
      ExpensesPage(
        key: _expenseKey,
        controller: _expenses,
        portfolio: _portfolio,
        scope: _scope,
      ),
      InvestmentsPage(
        key: _portfolioKey,
        controller: _portfolio,
        scope: _scope,
      ),
      DataExportPage(
        routines: _routines,
        fitbitRepository: widget.dependencies.fitbitRepository,
        dietRepository: SupabaseDietStateRepository(
          widget.dependencies.supabaseClientService.client,
        ),
      ),
      const SizedBox.shrink(),
      // 7: Organizzatore, caricato alla prima apertura.
      const SizedBox.shrink(),
      DailyPage(
        key: _dailyKey,
        routines: _routines,
        daily: _daily,
        onSelectDate: _selectDay,
        nutrition: NutritionHost(
          client: account,
          config: AppConfig.fromEnvironment(),
        ),
      ),
      SportPage(
        key: _sportKey,
        routines: _routines,
        daily: _daily,
        fitbit: _fitbit,
        onSelectDate: _selectDay,
        photos: ProgressPhotoRepository(account),
      ),
      // 10: Vestiti, caricata alla prima apertura.
      const SizedBox.shrink(),
    ];
    unawaited(_routines.load());
    unawaited(_calendar.load());
    unawaited(_fitbit.load());
    unawaited(
      _tasks.load().then((_) {
        if (mounted) _postaSync.start();
      }),
    );
    _routines.startAutoRefresh();
    _tasks.startAutoRollover();
    _fitbit.startAutoRefresh();
    _sync = AppSyncCoordinator(
      ensureSession: widget.dependencies.supabaseClientService.ensureSession,
      synchronize: _synchronize,
    )..start();
  }

  void _followRoutineDate() {
    if (_routines.selectedDate != _daily.date) {
      unawaited(_daily.selectDate(_routines.selectedDate));
    }
  }

  /// Cambia giorno ovunque: abitudini, check-in, orologio, calendario.
  void _selectDay(DateTime date) {
    _tasks.selectDate(date);
    unawaited(
      Future.wait([
        _routines.selectDate(date),
        _daily.selectDate(date),
        _fitbit.selectDate(date),
        _calendar.selectDate(date),
      ]),
    );
  }

  Future<void> _synchronize() async {
    if (!mounted) return;
    await Future.wait([
      _routines.refreshSilently(),
      _tasks.load(background: true),
      _fitbit.load(background: true),
      _calendar.load(background: true),
      _organizer.synchronize(),
      _daily.refresh(),
      if (_selectedIndex == 2) _markets.refreshAll(),
      if (!_portfolio.loading &&
          (_selectedIndex == 0 || _selectedIndex == 3 || _selectedIndex == 4))
        _portfolio.refresh(),
      if (_expensesLoaded && _selectedIndex == 3)
        _expenses.load(background: true),
      if (_statisticsOpened && _selectedIndex == 6)
        _bodyStatistics.synchronize(),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync.dispose();
    _postaSync.dispose();
    unawaited(_routines.flushPendingSaves());
    unawaited(_tasks.flushPendingSaves());
    _routines.removeListener(_followRoutineDate);
    _daily.dispose();
    _organizer.dispose();
    _markets.dispose();
    _portfolio.dispose();
    _expenses.dispose();
    _bodyStatistics.dispose();
    _calendar.dispose();
    _fitbit.dispose();
    _tasks.dispose();
    _routines.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    _bodyStatistics.setActive(index == 6);
    if (index == 6 && !_statisticsOpened) {
      _statisticsOpened = true;
      _pages[6] = BodyStatisticsPage(
        controller: _bodyStatistics,
        fitbit: _fitbit,
        recapBuilder: (section) => RecapView(
          key: ValueKey('recap-$section'),
          section: section,
          routines: _routines,
          repository: _daily.repository,
        ),
        compareSources: CompareSources(
          client: widget.dependencies.supabaseClientService.client,
          daily: _daily.repository,
          routines: _routines.repository,
          diet: SupabaseDietStateRepository(
            widget.dependencies.supabaseClientService.client,
          ),
        ),
      );
    }
    if (index == 10 && !_wardrobeOpened) {
      _wardrobeOpened = true;
      _pages[10] = WardrobePage(
        key: _wardrobeKey,
        repository: WardrobeRepository(
          widget.dependencies.supabaseClientService.client,
        ),
      );
    }
    if (index == 7 && !_organizerOpened) {
      _organizerOpened = true;
      _pages[7] = buildOrganizerFrame();
    }
    _expenses.setActive(index == 3);
    if (index == 3 && !_expensesLoaded) {
      _expensesLoaded = true;
      unawaited(_expenses.load());
    }
    setState(() {
      _selectedIndex = index;
      _section = 'Panoramica';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _bodyStatistics.setActive(
      state == AppLifecycleState.resumed && _selectedIndex == 6,
    );
    _expenses.setActive(
      state == AppLifecycleState.resumed && _selectedIndex == 3,
    );
  }

  void _selectSection(String section) {
    if (_selectedIndex == 0 && section == 'Statistiche') {
      _selectPage(6);
      return;
    }
    if (_selectedIndex == 6) {
      _bodyStatistics.change(() => _bodyStatistics.section = section);
      return;
    }
    setState(() {
      _section = section;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (_selectedIndex) {
        case 0:
          _dashboardKey.currentState?.showSection(section);
        case 1:
          _todoKey.currentState?.showSection(section);
        case 2:
          _marketKey.currentState?.showSection(section);
        case 3:
          _expenseKey.currentState?.showSection(section);
        case 4:
          _portfolioKey.currentState?.showSection(section);
        case 8:
          _dailyKey.currentState?.showSection(section);
        case 9:
          _sportKey.currentState?.showSection(section);
        case 10:
          _wardrobeKey.currentState?.showSection(section);
      }
    });
  }

  /// Sopra l'Organizzatore i clic andrebbero alla pagina incorporata.
  Widget _overFrame(Widget dialog) => _selectedIndex == 7 || _selectedIndex == 8
      ? shieldFromEmbeddedFrame(dialog)
      : dialog;

  void _status() => showDialog<void>(
    context: context,
    builder: (context) => _overFrame(
      AlertDialog(
        title: const Text('Stato sincronizzazione'),
        content: ListenableBuilder(
          listenable: Listenable.merge([_fitbit, _routines, _calendar, _tasks]),
          builder: (_, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Salute: ${_fitbit.isLoading
                    ? 'aggiornamento in corso'
                    : _fitbit.failure != null
                    ? 'aggiornamento non riuscito'
                    : _fitbit.isConnected
                    ? 'collegata'
                    : 'non collegata'}',
              ),
              if (_fitbit.day != null)
                Text(
                  'Ultimo aggiornamento: ${_fitbit.day!.syncedAt.toLocal()}',
                ),
              const SizedBox(height: 12),
              Text(
                'Routine: ${_routines.isSaving
                    ? 'salvataggio in corso'
                    : _routines.syncError != null || _routines.loadError != null
                    ? 'verifica connessione'
                    : 'caricate'}',
              ),
              Text(
                'Calendario: ${_calendar.failure != null ? 'verifica connessione Outlook' : '${_calendar.events.length} eventi'}',
              ),
              Text(
                'Attività: ${_tasks.error != null ? 'verifica connessione' : 'caricate'}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _fitbit.load();
              _calendar.load();
              _routines.load();
              _tasks.load();
            },
            child: const Text('Aggiorna'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    ),
  );
  void _settings() => showDialog<void>(
    context: context,
    builder: (context) => _overFrame(
      AlertDialog(
        title: const Text('Account e impostazioni'),
        content: Text(
          widget
                  .dependencies
                  .supabaseClientService
                  .client
                  .auth
                  .currentUser
                  ?.email ??
              'Account',
        ),
        actions: [
          if (widget.dependencies.authController.mfa case final mfa?)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                showDialog<void>(
                  context: this.context,
                  barrierDismissible: false,
                  builder: (_) =>
                      _overFrame(MfaSettingsDialog(controller: mfa)),
                );
              },
              child: const Text('Sicurezza e 2FA'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _selectPage(5);
            },
            child: const Text('Esporta dati'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.dependencies.authController.signOut();
            },
            child: const Text('Esci dall’account'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    ),
  );
  Future<void> _search() async {
    await showSearch<void>(context: context, delegate: _TaskSearch(_tasks));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _bodyStatistics,
    builder: (context, _) => DashboardFrame(
      fitbit: _fitbit,
      routines: _routines,
      selectedPage: _selectedIndex,
      section: _selectedIndex == 6 ? _bodyStatistics.section : _section,
      onPage: _selectPage,
      onSection: _selectSection,
      onSearch: _search,
      onStatus: _status,
      onSettings: _settings,
      child: IndexedStack(index: _selectedIndex, children: _pages),
    ),
  );
}

class _TaskSearch extends SearchDelegate<void> {
  _TaskSearch(this.controller)
    : super(searchFieldLabel: 'Cerca nelle attività');
  final TaskController controller;
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildResults(BuildContext context) => _results();
  @override
  Widget buildSuggestions(BuildContext context) => _results();
  Widget _results() => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final results = controller.overviewTasks
          .where((t) => t.title.toLowerCase().contains(query.toLowerCase()))
          .toList();
      if (results.isEmpty) {
        return const Center(child: Text('Nessuna attività trovata.'));
      }
      return ListView(
        children: [
          for (final task in results)
            CheckboxListTile(
              value: task.isCompleted,
              onChanged: (_) => controller.toggle(task.id),
              title: Text(task.title),
              subtitle: Text(switch (task.group) {
                DashboardTaskGroup.personal => 'Personale',
                DashboardTaskGroup.work => 'Lavoro',
                DashboardTaskGroup.personalWork => 'Lavoro personale',
                DashboardTaskGroup.posta => 'Posta',
              }),
            ),
        ],
      );
    },
  );
}
