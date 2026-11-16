import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../../core/utils/external_url_launcher.dart';
import '../../investments/portfolio.dart';
import '../../markets/presentation/finance_widgets.dart';
import '../application/expense_controller.dart';
import '../domain/expense_workbook.dart';
import '../domain/expense_summary.dart';
import 'expense_dashboard_widgets.dart';
import 'expense_spending_chart.dart';
import 'expense_transactions.dart';
import 'expense_wealth_history.dart';
import 'expense_annual_report.dart';

part 'expense_page_content.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({
    required this.controller,
    required this.portfolio,
    this.scope = 'local',
    super.key,
  });
  final ExpenseController controller;
  final PortfolioController portfolio;
  final String scope;
  @override
  State<ExpensesPage> createState() => ExpensesPageState();
}

class ExpensesPageState extends State<ExpensesPage> {
  final _scroll = ScrollController();
  final _anchors = {
    for (final name in [
      'Budget mensile',
      'Conti e fondi',
      'Riepilogo annuale',
      'Patrimonio',
    ])
      name: GlobalKey(),
  };
  final _transactionAnchor = GlobalKey();
  final _transactions = GlobalKey<ExpenseTransactionsState>();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _year = DateTime.now().year;
  bool _sourceOpen = false, _connectingMicrosoft = false;
  bool _categoriesExpanded = false, _accountsExpanded = false;
  void _update(VoidCallback action) {
    if (mounted) setState(action);
  }

  void _changeMonth(DateTime month) => _update(() {
    _month = month;
    _year = month.year;
  });
  void _reveal(GlobalKey? key) {
    FocusScope.of(context).unfocus();
    final target = key?.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: .02,
      );
    }
  }

  void showSection(String section) {
    FocusScope.of(context).unfocus();
    if (section == 'Fonte Excel') {
      _sourceDialog();
    } else if (section == 'Panoramica') {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    } else {
      _reveal(_anchors[section]);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _sourceDialog() async {
    if (_sourceOpen) return;
    setState(() => _sourceOpen = true);
    final c = widget.controller;
    final link = TextEditingController(text: c.sourceUrl);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fonte Excel'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Il file originale viene letto da OneDrive e verificato automaticamente ogni 20 secondi mentre Spese è aperta. Puoi sostituire il link quando lo rigeneri.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: link,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Link OneDrive',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Collega una volta l’account Microsoft che contiene il file. Il nuovo permesso OneDrive è Files.Read (sola lettura). L’Excel non viene modificato; link e budget sono salvati nel tuo account, senza servizi intermedi.',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud_outlined),
                label: Text(
                  _connectingMicrosoft
                      ? 'Collegamento in corso…'
                      : 'Collega OneDrive',
                ),
                onPressed: _connectingMicrosoft
                    ? null
                    : () {
                        final value = link.text.trim();
                        Navigator.pop(ctx);
                        unawaited(_connectOneDrive(value));
                      },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
          OutlinedButton(
            onPressed: () {
              final value = link.text.trim();
              Navigator.pop(ctx);
              c.refresh(link: value);
            },
            child: const Text('Prova il link'),
          ),
          FilledButton(
            onPressed: () async {
              final value = link.text.trim(),
                  url = Uri.tryParse(link.text.trim());
              if (url == null ||
                  url.scheme != 'https' ||
                  !(url.host == '1drv.ms' ||
                      url.host == 'onedrive.live.com' ||
                      url.host.endsWith('.sharepoint.com'))) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Inserisci un link HTTPS OneDrive o SharePoint.',
                    ),
                  ),
                );
                return;
              }
              if (await c.save(sourceUrl: value)) {
                if (ctx.mounted) Navigator.pop(ctx);
                await c.refresh();
              } else if (ctx.mounted) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text(c.settingsError!)));
              }
            },
            child: const Text('Salva link sul server'),
          ),
        ],
      ),
    );
    link.dispose();
    if (mounted) setState(() => _sourceOpen = false);
  }

  Future<void> _connectOneDrive(String link) async {
    final c = widget.controller;
    final source = Uri.tryParse(link);
    if (source == null ||
        source.scheme != 'https' ||
        !(source.host == '1drv.ms' ||
            source.host == 'onedrive.live.com' ||
            source.host.endsWith('.sharepoint.com'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci prima un link HTTPS OneDrive valido.'),
        ),
      );
      return;
    }
    setState(() => _connectingMicrosoft = true);
    try {
      if (!await c.save(sourceUrl: link)) throw StateError(c.settingsError!);
      final authorization = await c.repository.beginMicrosoftConnect();
      if (!mounted) return;
      final opened = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Collega OneDrive'),
          content: const Text(
            'Apri Microsoft, scegli l’account che contiene l’Excel e consenti Files.Read. Poi torna qui: la pagina si aggiorna da sola.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () async {
                // Open on a direct click so mobile popup protection permits it.
                final launched = await launchExternalUrl(authorization);
                if (ctx.mounted) Navigator.pop(ctx, launched);
              },
              child: const Text('Apri Microsoft'),
            ),
          ],
        ),
      );
      if (opened != true || !mounted) return;
      // Only the user opens the Microsoft consent page. No credentials are
      // collected here; the existing Worker callback encrypts the tokens.
      for (var attempt = 0; attempt < 60; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        if (!mounted) return;
        if (c.loading) continue;
        await c.refresh();
        if (!mounted) return;
        if (c.error == null && c.data != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'OneDrive collegato: Excel aggiornato automaticamente.',
              ),
            ),
          );
          return;
        }
        if (!(c.error ?? '').contains('Collega OneDrive') &&
            !(c.error ?? '').contains('Ricollega OneDrive')) {
          return;
        }
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Bad state: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingMicrosoft = false);
    }
  }

  Future<void> _budgetDialog() async {
    final c = widget.controller;
    final field = TextEditingController(
      text: c.settings
          .limitFor(expenseMonthKey(_month))
          .toStringAsFixed(2)
          .replaceAll('.', ','),
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Massimale ${expenseMonths[_month.month - 1]} ${_month.year}',
        ),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: field,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Massimale mensile EUR',
              helperText: 'Salvato su Supabase, condiviso tra i dispositivi.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () async {
              final limit = expenseNumber(field.text);
              if (limit == null || limit < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Inserisci un importo valido.')),
                );
                return;
              }
              if (await c.save(month: expenseMonthKey(_month), limit: limit)) {
                if (ctx.mounted) Navigator.pop(ctx);
              } else if (ctx.mounted) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text(c.settingsError!)));
              }
            },
            child: const Text('Salva sul server'),
          ),
        ],
      ),
    );
    field.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: const TextStyle(
      fontFamily: 'Segoe UI Variable',
      fontFamilyFallback: ['Segoe UI', 'Arial', 'sans-serif'],
    ),
    child: ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.portfolio]),
      builder: (context, _) => _buildDashboard(context),
    ),
  );
}
