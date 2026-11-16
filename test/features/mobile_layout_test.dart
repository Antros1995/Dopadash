import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/app/theme.dart';
import 'package:monitoraggio_personale_desktop/core/presentation/modular_board.dart';
import 'package:monitoraggio_personale_desktop/features/shell/presentation/dashboard_frame.dart';
import 'package:monitoraggio_personale_desktop/features/dashboard/presentation/dashboard_page.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/application/calendar_controller.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/data/calendar_repository.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/application/fitbit_controller.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/domain/fitbit_day.dart';
import 'package:monitoraggio_personale_desktop/features/routines/application/routine_controller.dart';
import 'package:monitoraggio_personale_desktop/features/routines/data/routine_repository.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/application/task_controller.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/data/task_repository.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/domain/dashboard_task.dart';
import 'package:monitoraggio_personale_desktop/features/tasks/presentation/todo_page.dart';
import 'package:monitoraggio_personale_desktop/features/markets/application/market_controller.dart';
import 'package:monitoraggio_personale_desktop/features/markets/data/local_market_repository.dart';
import 'package:monitoraggio_personale_desktop/features/markets/presentation/markets_page.dart';
import 'package:monitoraggio_personale_desktop/features/investments/portfolio.dart';
import 'package:monitoraggio_personale_desktop/features/investments/investments_page.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/application/expense_controller.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/data/expense_repository.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_workbook.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expenses_page.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/presentation/expense_transactions.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/application/body_statistics_controller.dart';
import 'package:monitoraggio_personale_desktop/features/statistics/presentation/body_statistics_page.dart';
import 'investments/portfolio_test.dart' show MemoryStore, NoPrices;
import 'expenses/expenses_test.dart' show fixture;
import 'statistics/body_statistics_test.dart'
    show MemoryStatisticsRepository, experiment;
import 'statistics/heart_rate_statistics_test.dart' show heartDay, point;

class _Routines implements RoutineRepository {
  @override
  Future<RoutineDayRemoteState> fetchDay(DateTime date) async =>
      const RoutineDayRemoteState(
        history: [],
        entries: {},
        effectiveScreenTimeMinutes: null,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Fitbit implements FitbitRepository {
  @override
  bool get isConfigured => true;
  @override
  Future<FitbitStatus> fetchDay(DateTime date) async => FitbitStatus(
    configured: true,
    connection: 'CONNECTED',
    deviceName: 'Charge 6',
    day: FitbitDay(
      date: '2026-10-17',
      finalized: false,
      syncedAt: DateTime.utc(2026, 10, 17),
      steps: 9000,
      distanceKm: 6.5,
      calories: 2200,
      activeMinutes: 30,
      restingHeartRate: 59,
      sleepMinutes: 441,
      sleepEfficiency: 92,
      heartRateVariabilityMs: 44,
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Calendar implements CalendarRepository {
  @override
  bool get isConfigured => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Tasks implements TaskRepository {
  @override
  Future<List<DashboardTask>> load() async => [
    for (final group in DashboardTaskGroup.values)
      DashboardTask(
        id: group.name,
        title:
            'Un’attività con un titolo abbastanza lungo da andare a capo sul telefono',
        group: group,
        scheduledDate: DateTime(2026, 10, 17),
        createdAt: DateTime(2026, 10, 16),
        completedAt: null,
        color: DashboardTaskColor.blue,
      ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Expenses implements ExpenseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  for (final setting in [
    (const Size(375, 812), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(430, 932), 1.3),
    (const Size(844, 390), 1.0),
  ]) {
    testWidgets(
      'phone navigation and every workspace fit ${setting.$1} text ${setting.$2}',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = setting.$1;
        tester.view.devicePixelRatio = 1;
        final landscape = setting.$1.width > setting.$1.height;
        final insets = landscape
            ? const FakeViewPadding(left: 47, right: 47, bottom: 21)
            : const FakeViewPadding(top: 47, bottom: 34);
        tester.view.padding = insets;
        tester.view.viewPadding = insets;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetViewInsets);
        final routines = RoutineController(repository: _Routines());
        await routines.load();
        final fitbit = FitbitController(repository: _Fitbit());
        await fitbit.load();
        final calendar = CalendarController(repository: _Calendar());
        final tasks = TaskController(repository: _Tasks());
        await tasks.load();
        final store = MemoryStore(), prices = NoPrices()..available = true;
        final market = LocalMarketRepository(prices, store, 'phone-test');
        final markets = MarketController(repository: market);
        final portfolio = PortfolioController(
          store: store,
          market: market,
          scope: 'phone-test',
        );
        await tester.runAsync(() => portfolio.load());
        final expenses = ExpenseController(repository: _Expenses())
          ..data = readExpenseData(ExpenseWorkbook.decode(fixture()));
        final statistics = BodyStatisticsController(
          repository: MemoryStatisticsRepository()
            ..days = [
              heartDay('2026-10-17', [point('2026-10-17T08:00:00Z', 70)]),
            ]
            ..experiments = [experiment()],
        );
        final pages = <Widget>[
          DashboardPage(
            routines: routines,
            fitbit: fitbit,
            calendar: calendar,
            tasks: tasks,
          ),
          TodoPage(controller: tasks),
          MarketsPage(controller: markets),
          ExpensesPage(controller: expenses, portfolio: portfolio),
          InvestmentsPage(controller: portfolio),
          const Text('Export'),
          BodyStatisticsPage(controller: statistics, fitbit: fitbit),
        ];
        var selected = 0, section = 'Panoramica';
        await tester.pumpWidget(
          MaterialApp(
            theme: buildDesktopTheme(),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('it')],
            locale: const Locale('it'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(setting.$2)),
              child: child!,
            ),
            home: StatefulBuilder(
              builder: (context, update) => DashboardFrame(
                fitbit: fitbit,
                routines: routines,
                selectedPage: selected,
                section: section,
                onPage: (p) => update(() {
                  selected = p;
                  section = 'Panoramica';
                }),
                onSection: (s) => update(() => section = s),
                onSearch: () {},
                onStatus: () {},
                onSettings: () {},
                child: pages[selected],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('phone-frame')), findsOneWidget);
        expect(
          tester.getSize(find.byType(DashboardPage)).width,
          setting.$1.width - insets.left - insets.right,
        );
        expect(find.text('Modifica layout'), findsNothing);
        expect(tester.takeException(), isNull, reason: 'Home');
        Future<void> bottom(String label) async {
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey('phone-bottom-navigation')),
              matching: find.text(label),
            ),
          );
          await tester.pumpAndSettle();
        }

        // Spese e Statistiche stanno nel menu "Altro": la barra in basso
        // ospita Quotidianità, Sport e Organizzatore.
        Future<void> fromMenu(String name) async {
          await bottom('Altro');
          final target = find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.text(name),
          );
          for (
            var i = 0;
            i < 12 && target.hitTestable().evaluate().isEmpty;
            i++
          ) {
            await tester.drag(
              find.byType(DraggableScrollableSheet),
              const Offset(0, -120),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(target.hitTestable().first);
          await tester.pumpAndSettle();
        }

        await bottom('To Do');
        expect(tester.takeException(), isNull, reason: 'To Do');
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('phone-bottom-navigation')),
          findsNothing,
        );
        expect(tester.takeException(), isNull, reason: 'Keyboard');
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await fromMenu('Spese');
        expect(tester.takeException(), isNull, reason: 'Spese');
        if (setting.$1.width == 375) {
          final filter = find.widgetWithText(OutlinedButton, 'Filtra');
          await tester.ensureVisible(filter);
          await tester.tap(filter);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButtonFormField<int>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Condiviso C').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Applica'));
          await tester.pumpAndSettle();
          expect(find.byType(ExpenseTransactions), findsOneWidget);
          expect(find.byType(InputChip), findsWidgets);
          expect(
            tester.takeException(),
            isNull,
            reason: 'Phone transaction filters',
          );
        }
        await fromMenu('Statistiche');
        expect(tester.takeException(), isNull, reason: 'Statistiche');
        await tester.tap(find.byTooltip('Apri sezioni'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sonno').last);
        await tester.pumpAndSettle();
        expect(section, 'Sonno');
        Future<void> menuPage(String name) async {
          await bottom('Altro');
          final target = find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.text(name),
          );
          for (
            var i = 0;
            i < 12 && target.hitTestable().evaluate().isEmpty;
            i++
          ) {
            await tester.drag(
              find.byType(DraggableScrollableSheet),
              const Offset(0, -120),
            );
            await tester.pumpAndSettle();
          }
          expect(target.hitTestable(), findsOneWidget);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        await menuPage('Borsa');
        expect(selected, 2);
        expect(tester.takeException(), isNull, reason: 'Borsa');
        await menuPage('Investimenti');
        expect(selected, 4);
        expect(tester.takeException(), isNull, reason: 'Investimenti');
        await tester.pumpWidget(const SizedBox());
        statistics.dispose();
        expenses.dispose();
        portfolio.dispose();
        markets.dispose();
        tasks.dispose();
        calendar.dispose();
        fitbit.dispose();
        routines.dispose();
      },
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }

  testWidgets(
    'desktop geometry survives a phone layout and return without saving any coordinates',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryStore()
        ..data['dashboard.layout.v1.local.unchanged'] = jsonEncode({
          'version': 2,
          'order': ['a', 'b'],
          'rects': {
            'a': [30, 20, 600, 200],
            'b': [700, 20, 400, 200],
          },
        });
      final original = Map.of(store.data);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModularBoard(
                area: 'unchanged',
                store: store,
                modules: const [
                  BoardModule('a', 'A', Text('Alpha')),
                  BoardModule('b', 'B', Text('Beta')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.widget<Positioned>(
        find.byKey(const ValueKey('position-a')),
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-board')), findsOneWidget);
      expect(find.text('Modifica layout'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Beta')).dy,
        greaterThan(tester.getTopLeft(find.text('Alpha')).dy),
      );
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      final after = tester.widget<Positioned>(
        find.byKey(const ValueKey('position-a')),
      );
      expect(
        [after.left, after.top, after.width, after.height],
        [before.left, before.top, before.width, before.height],
      );
      expect(store.data, original);
      expect(tester.takeException(), isNull);
    },
  );
}
