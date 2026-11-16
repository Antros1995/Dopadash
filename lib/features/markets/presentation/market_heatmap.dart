import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../application/market_controller.dart';
import '../domain/market_models.dart';

/// Mappa a blocchi della watchlist, come i quadranti dell'S&P 500: un blocco
/// per strumento, verde se oggi sale e rosso se scende, più intenso quanto
/// più si è mosso. Sopra, una frase che dice in parole com'è la giornata.
class MarketHeatmap extends StatelessWidget {
  const MarketHeatmap({
    required this.controller,
    required this.onSelected,
    super.key,
  });
  final MarketController controller;
  final ValueChanged<MarketInstrument> onSelected;

  static const _up = Color(0xFF0E9F6E), _down = Color(0xFFD64545);

  static String percent(double value) =>
      '${value >= 0 ? '+' : '−'}${value.abs().toStringAsFixed(2).replaceAll('.', ',')}%';

  @override
  Widget build(BuildContext context) {
    final rows = <(MarketInstrument, MarketSeries?, double?)>[
      for (final i in controller.instruments)
        (
          i,
          controller.seriesFor(i.symbol),
          controller.seriesFor(i.symbol)?.changePercentFor(MarketPeriod.day),
        ),
    ]..sort((a, b) => (b.$3 ?? -1e9).compareTo(a.$3 ?? -1e9));
    final known = [
      for (final r in rows)
        if (r.$3 != null) r,
    ];
    final rising = known.where((r) => r.$3! >= 0).length;
    final summary = known.isEmpty
        ? 'Quotazioni non ancora disponibili.'
        : 'Oggi $rising su ${known.length} in rialzo · migliore ${known.first.$1.name} ${percent(known.first.$3!)}'
              '${known.length > 1 ? ' · peggiore ${known.last.$1.name} ${percent(known.last.$3!)}' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                summary,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ),
            const _Legend(),
          ],
        ),
        const SizedBox(height: 12),
        if (controller.initializing)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          )
        else if (rows.isEmpty)
          const Text(
            'Aggiungi uno strumento alla watchlist per vedere la mappa.',
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final columns = (box.maxWidth / 170).floor().clamp(2, 6);
              final width = (box.maxWidth - (columns - 1) * 6) / columns;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final row in rows)
                    SizedBox(
                      width: width,
                      height: 100 * MediaQuery.textScalerOf(context).scale(1),
                      child: _Block(
                        instrument: row.$1,
                        series: row.$2,
                        change: row.$3,
                        onTap: () => onSelected(row.$1),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.instrument,
    required this.series,
    required this.change,
    required this.onTap,
  });
  final MarketInstrument instrument;
  final MarketSeries? series;
  final double? change;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final change = this.change;
    // Da ±0% (tenue) a ±3% e oltre (pieno).
    final strength = change == null ? 0.0 : (change.abs() / 3).clamp(0, 1);
    final base = change == null
        ? AppColors.textFaint
        : change >= 0
        ? MarketHeatmap._up
        : MarketHeatmap._down;
    final background = change == null
        ? AppColors.fill
        : Color.lerp(base.withValues(alpha: .16), base, strength.toDouble())!;
    final strong = strength > .45;
    final ink = strong ? Colors.white : AppColors.text;
    return Tooltip(
      message: series == null
          ? '${instrument.name}: quotazione non disponibile'
          : '${instrument.name} · variazione di oggi rispetto alla chiusura precedente',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  instrument.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                Text(
                  instrument.symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    color: strong
                        ? Colors.white.withValues(alpha: .8)
                        : AppColors.textMuted,
                  ),
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    change == null
                        ? '—'
                        : '${change >= 0 ? '▲' : '▼'} ${MarketHeatmap.percent(change)}',
                    style: TextStyle(
                      fontSize: 19,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.3,
                      color: strong
                          ? Colors.white
                          : change == null
                          ? AppColors.textMuted
                          : base,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget swatch(Color c) => Container(
      width: 16,
      height: 10,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    const label = TextStyle(fontSize: 11, color: AppColors.textMuted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('−3%', style: label),
        const SizedBox(width: 4),
        swatch(MarketHeatmap._down),
        swatch(MarketHeatmap._down.withValues(alpha: .4)),
        swatch(MarketHeatmap._up.withValues(alpha: .4)),
        swatch(MarketHeatmap._up),
        const SizedBox(width: 6),
        const Text('+3%', style: label),
      ],
    );
  }
}
