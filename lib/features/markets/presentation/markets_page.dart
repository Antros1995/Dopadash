import '../../organizer/presentation/organizer_page.dart';
import 'market_heatmap.dart';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/presentation/responsive_layout.dart';
import '../../../core/presentation/modular_board.dart';
import '../application/market_controller.dart';
import '../domain/market_models.dart';
import 'finance_widgets.dart';

class MarketsPage extends StatefulWidget {
  const MarketsPage({
    required this.controller,
    this.scope = 'local',
    super.key,
  });
  final MarketController controller;
  final String scope;
  @override
  State<MarketsPage> createState() => MarketsPageState();
}

class MarketsPageState extends State<MarketsPage> {
  final _board = GlobalKey<ModularBoardState>();
  final _scroll = ScrollController();
  FinanceRange _range = FinanceRange.month;
  DateTimeRange? _custom;
  MarketInstrument? _selected, _compare;
  MarketSeries? _series, _comparison;
  String? _error;
  String _category = 'Tutti';
  bool _loading = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.controller.load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Watchlist locale non disponibile.');
    }
    if (!mounted) return;
    _selected = widget.controller.instruments.firstOrNull;
    await _fetch();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void showSection(String section) {
    if (['ETF', 'Azioni', 'Crypto'].contains(section)) {
      setState(() => _category = section);
    }
    if (section == 'Panoramica') {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _board.currentState?.showSection(
        ['ETF', 'Azioni', 'Crypto'].contains(section) ? 'Esplora' : section,
      );
    }
  }

  Future<void> _fetch() async {
    if (_selected == null) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _series = null;
      _comparison = null;
    });
    try {
      final results = await Future.wait([
        widget.controller.fetchDisplaySeries(_selected!, _range.query),
        if (_compare != null)
          widget.controller.fetchDisplaySeries(_compare!, _range.query),
      ]);
      if (mounted && request == _request) {
        setState(() {
          _series = results.first;
          _comparison = results.length > 1 ? results.last : null;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () => _error =
              'Prezzi o cambio storico non disponibili. Riprova o scegli un altro ticker.',
        );
      }
    }
    if (mounted && request == _request) setState(() => _loading = false);
  }

  Future<void> _rangeChanged(FinanceRange value) async {
    if (value == FinanceRange.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1980),
        lastDate: DateTime.now(),
        initialDateRange: _custom,
      );
      if (picked == null || !mounted) return;
      _custom = picked;
    }
    setState(() => _range = value);
    await _fetch();
  }

  Future<void> _add([MarketInstrument? initial]) async {
    final symbol = TextEditingController(text: initial?.symbol ?? '');
    final name = TextEditingController(text: initial?.name ?? '');
    String category = initial?.category ?? 'ETF';
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Aggiungi alla watchlist'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: symbol,
                  decoration: const InputDecoration(
                    labelText: 'Ticker della sorgente (es. VWCE.DE)',
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  items: [
                    for (final k in ['ETF', 'Azioni', 'Crypto', 'Indici'])
                      DropdownMenuItem(value: k, child: Text(k)),
                  ],
                  onChanged: (v) => category = v!,
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      update(() => saving = true);
                      try {
                        await widget.controller.add(
                          symbol: symbol.text,
                          name: name.text,
                          category: category,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) {
                          update(() {
                            saving = false;
                            error =
                                'Ticker o quotazione non disponibili. Verifica e riprova.';
                          });
                        }
                      }
                    },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    symbol.dispose();
    name.dispose();
    if (mounted &&
        _selected == null &&
        widget.controller.instruments.isNotEmpty) {
      _selected = widget.controller.instruments.first;
      await _fetch();
    }
  }

  List<TimeValue> _points(MarketSeries? s) {
    if (s == null) return [];
    final end = _range == FinanceRange.custom
        ? DateTime(
            _custom!.end.year,
            _custom!.end.month,
            _custom!.end.day,
            23,
            59,
            59,
          )
        : DateTime.now();
    final start = _range == FinanceRange.custom
        ? _custom!.start
        : _range.start(end);
    return [
      for (final p in s.points)
        if (!p.time.isBefore(start) && !p.time.isAfter(end))
          TimeValue(p.time, p.close),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      var points = _points(_series), second = _points(_comparison);
      final comparing = _compare != null;
      if (comparing && points.isNotEmpty && second.isNotEmpty) {
        final start = points.first.time.isAfter(second.first.time)
            ? points.first.time
            : second.first.time;
        final end = points.last.time.isBefore(second.last.time)
            ? points.last.time
            : second.last.time;
        points = points
            .where((p) => !p.time.isBefore(start) && !p.time.isAfter(end))
            .toList();
        second = second
            .where((p) => !p.time.isBefore(start) && !p.time.isAfter(end))
            .toList();
        if (points.isNotEmpty && second.isNotEmpty) {
          final a = points.first.value, b = second.first.value;
          points = points
              .map((p) => TimeValue(p.time, p.value / a * 100))
              .toList();
          second = second
              .map((p) => TimeValue(p.time, p.value / b * 100))
              .toList();
        }
      }
      return SingleChildScrollView(
        controller: _scroll,
        padding: pageInsets(context, const EdgeInsets.fromLTRB(18, 16, 18, 30)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (usesPhoneLayout(context)) ...[
              const Text(
                'Borsa',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const Text(
                'Mercati, strumenti e watchlist',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'EUR', label: Text('EUR')),
                      ButtonSegment(value: 'USD', label: Text('USD')),
                    ],
                    selected: {c.currency},
                    showSelectedIcon: false,
                    onSelectionChanged: (values) async {
                      final refresh = c.setCurrency(values.single);
                      await Future.wait([refresh, _fetch()]);
                    },
                  ),
                  IconButton(
                    tooltip: 'Aggiorna mercati',
                    onPressed: () {
                      c.refreshAll();
                      _fetch();
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Watchlist'),
                  ),
                ],
              ),
            ] else
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Borsa',
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          'Mercati, strumenti e watchlist',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'EUR', label: Text('EUR')),
                      ButtonSegment(value: 'USD', label: Text('USD')),
                    ],
                    selected: {c.currency},
                    showSelectedIcon: false,
                    onSelectionChanged: (values) async {
                      final refresh = c.setCurrency(values.single);
                      await Future.wait([refresh, _fetch()]);
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Aggiorna mercati',
                    onPressed: () {
                      c.refreshAll();
                      _fetch();
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Watchlist'),
                  ),
                ],
              ),
            ModularBoard(
              key: _board,
              area: 'borsa',
              scope: widget.scope,
              modules: [
                BoardModule(
                  'Mappa',
                  'Mappa del giorno',
                  FinanceCard(
                    title: 'Mappa del giorno',
                    child: MarketHeatmap(
                      controller: c,
                      onSelected: (i) {
                        setState(() => _selected = i);
                        _fetch();
                        _board.currentState?.showSection('Mercati');
                      },
                    ),
                  ),
                  height: 215,
                  minHeight: 190,
                ),
                BoardModule(
                  'S&P 500',
                  'S&P 500 a blocchi',
                  FinanceCard(
                    title: 'S&P 500 a blocchi',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Ogni blocco è una società: più è grande più pesa nell’indice, verde se oggi sale e rosso se scende. Dati TradingView.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 520,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: buildWebFrame(
                              'sp500/index.html',
                              'La mappa dell’S&P 500',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  height: 650,
                  minHeight: 420,
                ),
                BoardModule(
                  'Panoramica',
                  'Panoramica mercati',
                  FinanceCard(
                    title: 'Panoramica mercati',
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 12,
                      children: [
                        if (c.initializing) const CircularProgressIndicator(),
                        if (!c.initializing && c.instruments.isEmpty)
                          const Text('Aggiungi un benchmark alla watchlist.'),
                        for (final i in c.instruments.take(6))
                          SizedBox(
                            width: 200,
                            child: InkWell(
                              onTap: () {
                                setState(() => _selected = i);
                                _fetch();
                                _board.currentState?.showSection('Mercati');
                              },
                              child: _mini(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  height: 225,
                ),
                BoardModule(
                  'Mercati',
                  'Andamento mercati',
                  FinanceCard(
                    title: 'Andamento mercati',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 15,
                          runSpacing: 10,
                          children: [
                            DropdownButton<MarketInstrument>(
                              isExpanded: usesPhoneLayout(context),
                              value: c.instruments
                                  .where((i) => i.symbol == _selected?.symbol)
                                  .firstOrNull,
                              hint: const Text('Scegli strumento'),
                              items: [
                                for (final i in c.instruments)
                                  DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                      i.name,
                                      maxLines: usesPhoneLayout(context)
                                          ? 1
                                          : null,
                                      overflow: usesPhoneLayout(context)
                                          ? TextOverflow.ellipsis
                                          : null,
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                setState(() => _selected = v);
                                _fetch();
                              },
                            ),
                            DropdownButton<String>(
                              isExpanded: usesPhoneLayout(context),
                              value: _compare?.symbol ?? '',
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('Nessun confronto'),
                                ),
                                for (final i in c.instruments)
                                  DropdownMenuItem(
                                    value: i.symbol,
                                    child: Text(
                                      i.name,
                                      maxLines: usesPhoneLayout(context)
                                          ? 1
                                          : null,
                                      overflow: usesPhoneLayout(context)
                                          ? TextOverflow.ellipsis
                                          : null,
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                setState(
                                  () => _compare = c.instruments
                                      .where((i) => i.symbol == v)
                                      .firstOrNull,
                                );
                                _fetch();
                              },
                            ),
                          ],
                        ),
                        RangeSelector(value: _range, onChanged: _rangeChanged),
                        if (_range == FinanceRange.custom)
                          Text(
                            '${dayLabel(_custom!.start)} – ${dayLabel(_custom!.end)}',
                          ),
                        if (_loading) const LinearProgressIndicator(),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_error!),
                          ),
                        const SizedBox(height: 12),
                        FinanceChart(
                          points: points,
                          second: second,
                          label: _selected?.name ?? 'Prezzo',
                          secondLabel: _compare?.name ?? '',
                          currency: comparing
                              ? 'base 100'
                              : _series?.currency ?? '',
                          height: 245,
                        ),
                        if (comparing)
                          const Text(
                            'Confronto relativo: base 100 alla prima osservazione disponibile nell’intervallo comune. Sedute e orari possono differire.',
                            style: TextStyle(fontSize: 11),
                          ),
                        if (_series != null)
                          Text(
                            '${_series!.exchange} · ultimo dato ${dayLabel(_series!.points.last.time)} · quotazioni potenzialmente ritardate',
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  columns: 8,
                  height: 520,
                ),
                BoardModule(
                  'Insight',
                  'Insight di mercato',
                  FinanceCard(
                    title: 'Insight di mercato',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (points.length < 2)
                          const Text(
                            'Servono almeno due osservazioni nel periodo selezionato.',
                          ),
                        if (points.length >= 2) ...[
                          Text(
                            '${_selected?.name}: ${amount((points.last.value / points.first.value - 1) * 100, currency: '%')} tra ${dayLabel(points.first.time)} e ${dayLabel(points.last.time)}.',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '${points.length} osservazioni disponibili. Variazione calcolata sul prezzo, esclusi dividendi e costi.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                        if (points.length >= 2 && second.length >= 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Text(
                              'Differenza di performance tra i due strumenti: ${amount(((points.last.value / points.first.value) - (second.last.value / second.first.value)) * 100, currency: 'punti %')}.',
                            ),
                          ),
                      ],
                    ),
                  ),
                  columns: 4,
                  height: 520,
                ),
                BoardModule(
                  'Watchlist',
                  'Watchlist',
                  FinanceCard(
                    title: 'Watchlist · salvata su questo dispositivo',
                    child: Column(
                      children: [
                        for (final category in [
                          'Indici',
                          'ETF',
                          'Azioni',
                          'Crypto',
                        ]) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (!c.instruments.any((i) => i.category == category))
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Nessuno strumento',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          for (final i in c.instruments.where(
                            (i) => i.category == category,
                          ))
                            ListTile(
                              dense: true,
                              leading: IconButton(
                                tooltip: 'Porta in panoramica',
                                onPressed: () async {
                                  try {
                                    await c.move(
                                      i.symbol,
                                      -c.instruments.indexOf(i),
                                    );
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Ordine non salvato.'),
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.star_outline, size: 18),
                              ),
                              title: Text(i.name),
                              subtitle: Text(
                                '${i.symbol} · ${amount(c.seriesFor(i.symbol)?.latest, currency: c.seriesFor(i.symbol)?.currency ?? '')}',
                              ),
                              onTap: () {
                                setState(() => _selected = i);
                                _fetch();
                                _board.currentState?.showSection('Mercati');
                              },
                              trailing: IconButton(
                                tooltip: 'Rimuovi dalla watchlist',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () async {
                                  try {
                                    await c.remove(i.symbol);
                                    if (mounted) {
                                      if (_compare?.symbol == i.symbol) {
                                        _compare = null;
                                      }
                                      if (_selected?.symbol == i.symbol) {
                                        _selected = c.instruments.firstOrNull;
                                      }
                                      await _fetch();
                                    }
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Watchlist non salvata. Riprova.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  columns: 7,
                  height: 540,
                ),
                BoardModule(
                  'Esplora',
                  'Esplora strumenti',
                  FinanceCard(
                    title: 'Esplora strumenti',
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final k in [
                              'Tutti',
                              'ETF',
                              'Azioni',
                              'Crypto',
                            ])
                              ChoiceChip(
                                label: Text(k),
                                selected: k == _category,
                                onSelected: (_) =>
                                    setState(() => _category = k),
                              ),
                          ],
                        ),
                        for (final i in _catalog.where(
                          (i) =>
                              _category == 'Tutti' || i.category == _category,
                        ))
                          ListTile(
                            dense: true,
                            title: Text(i.name),
                            subtitle: Text(i.symbol),
                            trailing: IconButton(
                              tooltip: 'Osserva nella watchlist',
                              onPressed: () => _add(i),
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 20,
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: _add,
                          child: const Text('Cerca un altro ticker'),
                        ),
                      ],
                    ),
                  ),
                  columns: 5,
                  height: 540,
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  Widget _mini(MarketInstrument i) {
    final c = widget.controller, s = c.seriesFor(i.symbol);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(i.symbol, style: const TextStyle(fontSize: 10)),
          const SizedBox(height: 6),
          Text(
            amount(s?.latest, currency: s?.currency ?? ''),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Text(
            s == null
                ? 'Quotazione non disponibile'
                : '${s.changeFor(MarketPeriod.day) < 0 ? '▼' : '▲'} ${MarketHeatmap.percent(s.changePercentFor(MarketPeriod.day))} oggi',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: s != null && s.changeFor(MarketPeriod.day) < 0
                  ? AppColors.danger
                  : AppColors.green,
            ),
          ),
          if (s != null)
            SizedBox(
              height: 25,
              child: CustomPaint(
                size: const Size(double.infinity, 25),
                painter: _Spark(s.points.map((p) => p.close).toList()),
              ),
            ),
          if (s != null)
            Text(
              '${dayLabel(s.points.last.time)}${c.errorFor(i.symbol) != null ? ' · aggiornamento fallito' : ''}',
              style: const TextStyle(fontSize: 9),
            ),
        ],
      ),
    );
  }
}

const _catalog = [
  MarketInstrument(
    symbol: 'VWCE.DE',
    name: 'FTSE All-World · Vanguard',
    assetCategory: 'ETF',
  ),
  MarketInstrument(
    symbol: 'CSPX.L',
    name: 'S&P 500 · iShares',
    assetCategory: 'ETF',
  ),
  MarketInstrument(symbol: 'AAPL', name: 'Apple', assetCategory: 'Azioni'),
  MarketInstrument(symbol: 'MSFT', name: 'Microsoft', assetCategory: 'Azioni'),
  MarketInstrument(symbol: 'BTC-USD', name: 'Bitcoin', assetCategory: 'Crypto'),
  MarketInstrument(
    symbol: 'ETH-USD',
    name: 'Ethereum',
    assetCategory: 'Crypto',
  ),
];

class _Spark extends CustomPainter {
  _Spark(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b),
        max = values.reduce((a, b) => a > b ? a : b);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width,
          y =
              size.height -
              (values[i] - min) /
                  (max == min ? 1 : max - min) *
                  (size.height - 3);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = values.last >= values.first
            ? AppColors.green
            : AppColors.danger
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _Spark old) => true;
}
