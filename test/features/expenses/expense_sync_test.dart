import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/application/expense_controller.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/data/expense_repository.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_summary.dart';
import 'package:monitoraggio_personale_desktop/features/expenses/domain/expense_workbook.dart';
import 'expenses_test.dart' as xml;

Uint8List _withNewExpense() {
  final archive = Archive();
  for (final file in ZipDecoder().decodeBytes(xml.fixture()).files) {
    final bytes = file.name.endsWith('sheet1.xml')
        ? utf8.encode(
            utf8
                .decode(file.content as List<int>)
                .replaceFirst(xml.number('DT5', 30), xml.number('DT5', 130)),
          )
        : file.content as List<int>;
    archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

class _Repository implements ExpenseRepository {
  Uint8List bytes = xml.fixture();
  Completer<Uint8List>? pending;
  int downloads = 0;
  @override
  Future<ExpenseSettings> loadSettings() async =>
      const ExpenseSettings(sourceUrl: 'https://1drv.ms/x/test');
  @override
  Stream<ExpenseSettings> watchSettings() => const Stream.empty();
  @override
  Future<Uint8List> fetchWorkbook(String link) {
    downloads++;
    return pending?.future ?? Future.value(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not used');
}

void main() {
  test(
    'residue includes today even when the source was read yesterday, without counting tomorrow',
    () {
      final data = ExpenseData(
        accounts: const {},
        liquids: null,
        pensionFund: null,
        funds: const {},
        sharedFactor: .5,
        tables: const [],
        transactions: [
          ExpenseTransaction(
            DateTime(2026, 10, 15),
            'Casa',
            100,
            100,
            false,
            'A1',
          ),
          ExpenseTransaction(
            DateTime(2026, 10, 16, 14),
            'Spesa',
            40,
            20,
            true,
            'A2',
          ),
          ExpenseTransaction(
            DateTime(2026, 10, 17),
            'Spesa',
            900,
            900,
            false,
            'A3',
          ),
        ],
        availableMonths: {'2026-10'},
        warnings: const [],
        loadedAt: DateTime(2026, 10, 15),
        sourceName: 'Test',
      );
      final summary = ExpenseMonthSummary(
        data,
        DateTime(2026, 10),
        now: DateTime(2026, 10, 16),
      );
      expect(summary.spent, 120);
      expect(1900 - summary.spent!, 1780);
      expect(summary.cumulative.last, (DateTime(2026, 10, 16), 120));
    },
  );
  testWidgets(
    'syncs changed expenses within 20 seconds, skips unchanged rebuilds and joins in-flight requests',
    (tester) async {
      final repo = _Repository();
      final c = ExpenseController(repository: repo);
      addTearDown(c.dispose);
      await c.load();
      final original = c.data;
      var updates = 0;
      c.addListener(() => updates++);
      c.setActive(true);
      await tester.pump(ExpenseController.syncInterval);
      await tester.pump();
      expect(repo.downloads, 2);
      expect(identical(c.data, original), isTrue);
      expect(updates, 0);
      repo.bytes = _withNewExpense();
      await tester.pump(ExpenseController.syncInterval);
      await tester.pump();
      expect(repo.downloads, 3);
      expect(updates, 1);
      final summary = ExpenseMonthSummary(
        c.data,
        DateTime(2026, 10),
        now: DateTime(2026, 10, 16),
      );
      expect(summary.spent, 170);
      expect(c.settings.limitFor('2026-10') - summary.spent!, 1730);
      repo.pending = Completer<Uint8List>();
      final background = c.refresh(background: true);
      final manual = c.refresh();
      expect(c.loading, isTrue);
      await tester.pump(ExpenseController.syncInterval);
      expect(repo.downloads, 4);
      repo.pending!.complete(repo.bytes);
      await Future.wait([background, manual]);
      expect(c.loading, isFalse);
      c.setActive(false);
      await tester.pump(const Duration(seconds: 40));
      expect(repo.downloads, 4);
    },
  );
}
