part of 'expenses_page.dart';

extension _ExpensePageContent on ExpensesPageState {
  Widget _buildDashboard(BuildContext context) {
    final c = widget.controller, data = c.data, portfolio = widget.portfolio;
    final summary = ExpenseMonthSummary(data, _month);
    final limit = c.settings.limitFor(expenseMonthKey(_month));
    final invested = portfolio.loading || !portfolio.complete
        ? null
        : portfolio.totalValue;
    final wealth =
        data?.liquids == null || data?.pensionFund == null || invested == null
        ? null
        : data!.liquids! + data.pensionFund! + invested;
    final months = {
      if (data != null) ...data.availableMonths,
      expenseMonthKey(_month),
    }.toList()..sort();
    final ratio = summary.spent == null || limit <= 0
        ? null
        : summary.spent! / limit;
    final residue = summary.spent == null ? null : limit - summary.spent!;
    final accounts = <String, double?>{
      ...data?.accounts ??
          const {
            'Conto principale': null,
            'Sottoconto': null,
            'Conto deposito': null,
            'Portafoglio digitale': null,
            'Conto investimenti': null,
            'Conto secondario': null,
          },
      ...data?.funds ?? const {'Fondo Spese': null, 'Fondo Risparmi': null},
    };
    Widget picker({bool arrows = false}) => ExpenseMonthPicker(
      month: _month,
      months: months,
      onChanged: _changeMonth,
      arrows: arrows,
    );
    return LayoutBuilder(
      builder: (context, viewport) {
        final narrow = viewport.maxWidth < 700;
        return SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(
            narrow ? 14 : 24,
            22,
            narrow ? 14 : 24,
            30,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Spese',
                        style: TextStyle(
                          fontSize: 29,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Monitora il tuo budget e tieni sotto controllo le tue spese',
                        style: TextStyle(
                          fontSize: narrow ? 11 : 13,
                          color: expenseMuted,
                        ),
                      ),
                    ],
                  );
                  final controls = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      picker(arrows: true),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: 'Opzioni Spese',
                        icon: const Icon(
                          Icons.more_horiz,
                          color: AppColors.text,
                        ),
                        onSelected: (v) {
                          if (v == 'source') _sourceDialog();
                          if (v == 'refresh') c.refresh();
                          if (v == 'budget') _budgetDialog();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'source',
                            child: Text('Fonte Excel'),
                          ),
                          PopupMenuItem(
                            value: 'refresh',
                            enabled: !c.loading,
                            child: const Text('Aggiorna Excel'),
                          ),
                          const PopupMenuItem(
                            value: 'budget',
                            child: Text('Massimale mensile'),
                          ),
                        ],
                      ),
                    ],
                  );
                  return box.maxWidth > 750
                      ? Row(
                          children: [
                            Expanded(child: title),
                            controls,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: 12),
                            controls,
                          ],
                        );
                },
              ),
              if (c.loading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _notice(c.error!, error: true),
                ),
              if (c.settingsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _notice(c.settingsError!, error: true),
                ),
              if (data == null &&
                  !c.loading &&
                  c.error == null &&
                  c.settingsError == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _notice(
                    'Collega l’Excel da Fonte Excel per visualizzare i tuoi dati reali.',
                  ),
                ),
              const SizedBox(height: 12),
              _stats(summary, limit, ratio, residue),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _anchors['Budget mensile'],
                child: ExpensePair(
                  height: usesPhoneLayout(context)
                      ? 360 * MediaQuery.textScalerOf(context).scale(1)
                      : narrow
                      ? 285
                      : 258,
                  left: ExpensePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, box) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ExpenseHeading(
                                'Andamento spese',
                                Icons.trending_up,
                                subtitle: 'Confronto spese mensili e budget',
                                action: box.maxWidth > 650
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _legend(),
                                          const SizedBox(width: 22),
                                          picker(),
                                        ],
                                      )
                                    : box.maxWidth > 430
                                    ? picker()
                                    : null,
                              ),
                              if (box.maxWidth <= 650)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 15,
                                    runSpacing: 8,
                                    children: [
                                      _legend(),
                                      if (box.maxWidth <= 430) ...[picker()],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Expanded(
                          child: RepaintBoundary(
                            child: ExpenseSpendingChart(
                              summary: summary,
                              limit: limit,
                            ),
                          ),
                        ),
                        if (summary.undated.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              onTap: () {
                                _transactions.currentState?.showUndated();
                                _reveal(_transactionAnchor);
                              },
                              child: Text(
                                '${summary.undated.length} operazioni senza data (${amount(summary.undatedTotal)}): incluse nel totale, escluse dal grafico giornaliero. Vedi operazioni ›',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  right: ExpenseBudgetControl(
                    summary: summary,
                    limit: limit,
                    onEdit: _budgetDialog,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ExpensePair(
                left: ExpenseCategories(
                  summary: summary,
                  expanded: _categoriesExpanded,
                  onToggle: () =>
                      _update(() => _categoriesExpanded = !_categoriesExpanded),
                  monthPicker: picker(),
                  onCategory: (category) {
                    _transactions.currentState?.selectCategory(category);
                    _reveal(_transactionAnchor);
                  },
                ),
                right: KeyedSubtree(
                  key: _anchors['Conti e fondi'],
                  child: ExpenseAccounts(
                    values: accounts,
                    expanded: _accountsExpanded,
                    onToggle: () =>
                        _update(() => _accountsExpanded = !_accountsExpanded),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _transactionAnchor,
                child: ExpenseTransactions(
                  key: _transactions,
                  transactions: data?.transactions ?? const [],
                  month: _month,
                  factor: data?.sharedFactor,
                ),
              ),
              const SizedBox(height: 18),
              KeyedSubtree(
                key: _anchors['Patrimonio'],
                child: ExpensePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ExpenseHeading(
                        'Patrimonio e composizione finanziaria',
                        Icons.account_balance_wallet_outlined,
                        subtitle:
                            'Liquidità, investimenti e previdenza · valori attuali',
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, box) => Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          children: [
                            for (final e in <String, double?>{
                              'Patrimonio attuale': wealth,
                              'Totale liquidi · Excel': data?.liquids,
                              'Investimenti · app': invested,
                              'Fondo pensione · Excel': data?.pensionFund,
                            }.entries)
                              SizedBox(
                                width: box.maxWidth >= 850
                                    ? (box.maxWidth - 60) / 4
                                    : (box.maxWidth - 20) / 2,
                                child: _money(
                                  e.key,
                                  e.value,
                                  prominent: e.key == 'Patrimonio attuale',
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Patrimonio = liquidità dell’Excel + investimenti dell’app + fondo pensione. I fondi sono accantonamenti e non vengono sommati nuovamente.',
                        style: TextStyle(fontSize: 11, color: expenseMuted),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          for (final e
                              in data?.funds.entries ??
                                  <MapEntry<String, double?>>[])
                            _money(e.key, e.value),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _anchors['Riepilogo annuale'],
                child: _annual(data),
              ),
              const SizedBox(height: 12),
              _wealthHistory(data),
              const SizedBox(height: 12),
              _sourceSettings(data, limit),
            ],
          ),
        );
      },
    );
  }

  Widget _stats(
    ExpenseMonthSummary summary,
    double limit,
    double? ratio,
    double? residue,
  ) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 1050
          ? 4
          : box.maxWidth >= 540
          ? 2
          : 1;
      final statWidth = (box.maxWidth - (columns - 1) * 10) / columns;
      final footerStyle = const TextStyle(fontSize: 10, color: expenseMuted);
      final cards = [
        ExpenseStat(
          label: 'Spese totali',
          value: summary.spent,
          icon: Icons.account_balance_wallet_outlined,
          footer: ExpenseDelta(
            summary.change,
            _month,
            days: summary.elapsedDays,
          ),
        ),
        ExpenseStat(
          label: 'Budget mensile',
          value: limit,
          icon: Icons.shopping_cart_outlined,
          onTap: _budgetDialog,
          progress: ratio?.clamp(0, 1),
          footer: Text(
            ratio == null
                ? 'Imposta il massimale'
                : '${(ratio * 100).toStringAsFixed(0)}% utilizzato',
            style: footerStyle,
          ),
        ),
        ExpenseStat(
          label: 'Residuo',
          value: residue,
          icon: Icons.trending_up,
          footer: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: residue != null && residue < 0
                      ? AppColors.dangerSoft
                      : const Color(0xFFD7F5E8),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ratio == null
                      ? 'Budget meno spese'
                      : residue! < 0
                      ? 'Budget superato'
                      : '${((1 - ratio) * 100).toStringAsFixed(0)}% del budget',
                  style: footerStyle,
                ),
              ),
            ],
          ),
        ),
        ExpenseStat(
          label: 'Media giornaliera',
          value: summary.average,
          icon: Icons.pie_chart_outline,
          footer: Tooltip(
            message:
                'Spese effettive divise per ${summary.elapsedDays} giorni trascorsi del mese.',
            child: ExpenseDelta(
              summary.averageChange,
              _month,
              days: summary.elapsedDays,
            ),
          ),
        ),
      ];
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final card in cards)
            SizedBox(
              width: statWidth,
              height: usesPhoneLayout(context)
                  ? 130 * MediaQuery.textScalerOf(context).scale(1)
                  : 106,
              child: card,
            ),
        ],
      );
    },
  );
  Widget _legend() => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 7, color: AppColors.green),
      SizedBox(width: 8),
      Text(
        'Spese cumulate',
        style: TextStyle(fontSize: 10, color: expenseMuted),
      ),
      SizedBox(width: 24),
      SizedBox(
        width: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ColoredBox(
              color: expenseBlue,
              child: SizedBox(width: 5, height: 1.5),
            ),
            ColoredBox(
              color: expenseBlue,
              child: SizedBox(width: 5, height: 1.5),
            ),
            Icon(Icons.circle, size: 6, color: expenseBlue),
          ],
        ),
      ),
      SizedBox(width: 6),
      Text('Budget', style: TextStyle(fontSize: 10, color: expenseMuted)),
    ],
  );

  Widget _annual(ExpenseData? data) => ExpenseAnnualReport(
    data: data,
    year: _year,
    onYearChanged: (year) => _update(() => _year = year),
  );

  Widget _wealthHistory(ExpenseData? data) => ExpenseWealthHistory(
    data: data,
    year: _year,
    portfolio: widget.portfolio,
  );

  Widget _sourceSettings(ExpenseData? data, double limit) => ExpensePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpenseHeading(
          'Fonte Excel e parametri',
          Icons.cloud_done_outlined,
          action: IconButton(
            tooltip: 'Aggiorna Excel',
            onPressed: widget.controller.loading
                ? null
                : () => widget.controller.refresh(),
            icon: const Icon(Icons.refresh, size: 19),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _sourceOpen ? null : _sourceDialog,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Fonte Excel'),
            ),
            Text(
              data == null
                  ? 'Fonte non collegata'
                  : '${data.sourceName} · lettura ${dayLabel(data.loadedAt)} ${data.loadedAt.hour.toString().padLeft(2, '0')}:${data.loadedAt.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 11, color: expenseMuted),
            ),
            _money('Massimale ${expenseLongMonth(_month)}', limit),
            TextButton.icon(
              onPressed: widget.controller.saving ? null : _budgetDialog,
              icon: const Icon(Icons.tune, size: 17),
              label: const Text('Modifica massimale'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Verifica automatica ogni 20 secondi con Spese aperta. Quota condivisa C: ${data?.sharedFactor ?? 'non disponibile'} × importo originale (2- Totale!AF2). Link e massimali sincronizzati sul server.',
          style: const TextStyle(
            fontSize: 11,
            color: expenseMuted,
            height: 1.5,
          ),
        ),
        if (widget.controller.settings.budgets.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Massimali salvati per mese',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e
                      in (widget.controller.settings.budgets.entries.toList()
                        ..sort((a, b) => a.key.compareTo(b.key))))
                    ActionChip(
                      label: Text(
                        '${expenseLongMonth(DateTime.parse('${e.key}-01'))}: ${amount(e.value)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () {
                        _changeMonth(DateTime.parse('${e.key}-01'));
                        _budgetDialog();
                      },
                    ),
                ],
              ),
            ],
          ),
        if (data != null && data.warnings.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.info_outline,
              size: 19,
              color: AppColors.warning,
            ),
            title: Text(
              '${data.warnings.length} segnalazioni della fonte',
              style: const TextStyle(fontSize: 12, color: AppColors.warning),
            ),
            children: [
              for (final warning in data.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      warning,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
  Widget _money(String label, double? value, {bool prominent = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: expenseMuted),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount(value),
              style: TextStyle(
                fontSize: prominent ? 26 : 20,
                fontWeight: FontWeight.w600,
                color: prominent ? AppColors.green : AppColors.text,
              ),
            ),
          ),
        ],
      );
  Widget _notice(String message, {bool error = false}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? AppColors.dangerSoft : AppColors.greenSoft,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(
          error ? Icons.info_outline : Icons.link,
          size: 18,
          color: error ? AppColors.danger : AppColors.green,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: error ? AppColors.danger : AppColors.green,
            ),
          ),
        ),
        TextButton(onPressed: _sourceDialog, child: const Text('Fonte Excel')),
      ],
    ),
  );
}
