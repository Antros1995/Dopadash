import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../markets/presentation/finance_widgets.dart';
import 'portfolio.dart';

/// The same portfolio history, controls and presentation in every section.
/// Excel balances are deliberately not used as a substitute for market history.
class PortfolioHistoryCard extends StatefulWidget {
  const PortfolioHistoryCard({required this.controller, super.key});

  final PortfolioController controller;

  @override
  State<PortfolioHistoryCard> createState() => _PortfolioHistoryCardState();
}

class _PortfolioHistoryCardState extends State<PortfolioHistoryCard> {
  FinanceRange _range = FinanceRange.all;
  DateTimeRange? _custom;

  Future<void> _rangeChanged(FinanceRange value) async {
    if (value == FinanceRange.custom) {
      final selected = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        initialDateRange: _custom,
      );
      if (selected == null || !mounted) return;
      _custom = selected;
    }
    setState(() => _range = value);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final end = _range == FinanceRange.custom ? _custom!.end : DateTime.now();
      final start = _range == FinanceRange.custom
          ? _custom!.start
          : _range == FinanceRange.all
          ? widget.controller.firstActivityDate ?? FinanceRange.year.start(end)
          : _range.start(end);
      final history = widget.controller.loading
          ? <PortfolioHistoryPoint>[]
          : widget.controller.historyFor(start, end);
      return FinanceCard(
        title: 'Andamento portafoglio',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RangeSelector(value: _range, onChanged: _rangeChanged),
            const SizedBox(height: 10),
            if (_range == FinanceRange.custom)
              Text(
                '${dayLabel(start)} – ${dayLabel(end)}',
                style: const TextStyle(fontSize: 11),
              ),
            if (widget.controller.loading)
              const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              FinanceChart(
                points: [for (final p in history) TimeValue(p.date, p.value)],
                second: [for (final p in history) TimeValue(p.date, p.capital)],
                label: 'Portafoglio',
                secondLabel: 'Capitale netto',
                connectGaps: false,
              ),
            const SizedBox(height: 12),
            Text(
              '${history.length} giornate coperte da prezzi disponibili. Storico giornaliero: il filtro 24H non contiene quotazioni intraday del portafoglio.',
              style: const TextStyle(fontSize: 11),
            ),
            const Text(
              'Ricostruzione a partire dalle quantità iniziali e dalle operazioni registrate. Chiusure precedenti riportate per massimo 4 giorni; lacune non collegate.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    },
  );
}
