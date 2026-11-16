import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/presentation/responsive_layout.dart';
import '../../core/presentation/modular_board.dart';
import '../markets/presentation/finance_widgets.dart';
import 'portfolio.dart';
import 'portfolio_history_card.dart';

class InvestmentsPage extends StatefulWidget {
  const InvestmentsPage({
    required this.controller,
    this.scope = 'local',
    super.key,
  });
  final PortfolioController controller;
  final String scope;
  @override
  State<InvestmentsPage> createState() => InvestmentsPageState();
}

class InvestmentsPageState extends State<InvestmentsPage> {
  final _board = GlobalKey<ModularBoardState>();
  final _scroll = ScrollController();
  void showSection(String section) {
    if (section == 'Panoramica' || section == 'Portafoglio') {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _board.currentState?.showSection(section);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _edit({
    Holding? holding,
    PortfolioTrade? trade,
    bool opening = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TradeDialog(
        controller: widget.controller,
        holding: holding,
        trade: trade,
        opening: opening,
      ),
    );
    if (mounted) widget.controller.refresh();
  }

  Future<void> _delete(PortfolioTrade trade) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina operazione'),
        content: Text(
          '${trade.symbol} · ${dayLabel(trade.date)}\nLe quantità saranno ricalcolate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.controller.save(deleteTrade: trade.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return SingleChildScrollView(
        controller: _scroll,
        padding: pageInsets(context, const EdgeInsets.fromLTRB(18, 16, 18, 30)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (usesPhoneLayout(context)) ...[
              const Text(
                'Investimenti',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const Text(
                'Il tuo patrimonio · registro locale',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Aggiorna prezzi',
                    onPressed: c.refreshing ? null : c.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  FilledButton.icon(
                    onPressed: c.loading || c.error != null
                        ? null
                        : () => _edit(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Aggiungi strumento'),
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
                          'Investimenti',
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          'Il tuo patrimonio · registro locale',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Aggiorna prezzi',
                    onPressed: c.refreshing ? null : c.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  FilledButton.icon(
                    onPressed: c.loading || c.error != null
                        ? null
                        : () => _edit(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Aggiungi strumento'),
                  ),
                ],
              ),
            if (c.loading || c.refreshing) const LinearProgressIndicator(),
            if (c.error != null)
              Text(c.error!, style: const TextStyle(color: AppColors.danger)),
            ModularBoard(
              key: _board,
              area: 'investimenti',
              scope: widget.scope,
              modules: [
                BoardModule(
                  'Panoramica',
                  'Patrimonio',
                  FinanceCard(
                    title: 'Il tuo portafoglio',
                    child: Wrap(
                      spacing: 35,
                      runSpacing: 18,
                      children: [
                        _kpi(
                          c.complete
                              ? 'VALORE PORTAFOGLIO'
                              : 'VALORE PARZIALE · EUR',
                          amount(c.totalValue),
                        ),
                        _kpi(
                          'CAPITALE NETTO INVESTITO · EUR',
                          amount(c.netCapital),
                        ),
                        _kpi(
                          'GUADAGNO / PERDITA',
                          c.complete ? amount(c.profit) : '—',
                        ),
                        _kpi(
                          'RENDIMENTO SU CAPITALE NETTO',
                          amount(c.returnPercent, currency: '%'),
                        ),
                      ],
                    ),
                  ),
                  height: 155,
                  minHeight: 140,
                ),
                BoardModule(
                  'Storico',
                  'Andamento portafoglio',
                  PortfolioHistoryCard(controller: c),
                  columns: 8,
                  height: 490,
                ),
                BoardModule(
                  'Allocazione',
                  'Allocazione',
                  FinanceCard(
                    title: 'Allocazione · valore in EUR',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final kind in AssetKind.values)
                          _allocation(
                            kind.label,
                            c.positions
                                .where(
                                  (p) =>
                                      p.holding.kind == kind &&
                                      p.holding.currency == 'EUR',
                                )
                                .fold(0.0, (v, p) => v + (c.value(p) ?? 0)),
                            c.totalValue,
                          ),
                        const Divider(height: 24),
                        for (final p in c.positions.where(
                          (p) => p.quantity > 0 && p.holding.currency == 'EUR',
                        ))
                          _allocation(
                            p.holding.symbol,
                            c.value(p) ?? 0,
                            c.totalValue,
                          ),
                      ],
                    ),
                  ),
                  columns: 4,
                  height: 490,
                ),
                for (final kind in AssetKind.values)
                  BoardModule(
                    kind.label,
                    kind.label,
                    FinanceCard(
                      title: kind.label,
                      action: TextButton(
                        onPressed: () => _edit(),
                        child: const Text('+ Aggiungi'),
                      ),
                      child: Column(
                        children: [
                          if (!c.positions.any((p) => p.holding.kind == kind))
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                kind == AssetKind.stock
                                    ? 'Nessuna azione in portafoglio'
                                    : 'Nessuno strumento in questa categoria',
                              ),
                            ),
                          for (final p in c.positions.where(
                            (p) => p.holding.kind == kind,
                          ))
                            _position(p, c),
                        ],
                      ),
                    ),
                    height: kind == AssetKind.etf ? 430 : 220,
                  ),
                BoardModule(
                  'Operazioni',
                  'Operazioni',
                  FinanceCard(
                    title: 'Operazioni registrate',
                    action: TextButton(
                      onPressed: () => _edit(holding: c.holdings.firstOrNull),
                      child: const Text('+ Operazione'),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Registro personale. Le operazioni aggiornano solo questo archivio locale.',
                          style: TextStyle(fontSize: 12),
                        ),
                        if (c.trades.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Nessuna operazione registrata. Le posizioni importate sono saldi iniziali.',
                            ),
                          ),
                        for (final t in [
                          ...c.trades,
                        ]..sort((a, b) => b.date.compareTo(a.date)))
                          ListTile(
                            dense: true,
                            title: Text(
                              '${t.buy ? 'Acquisto' : 'Vendita'} · ${t.symbol} · ${amount(t.quantity, currency: '', digits: 4)}',
                            ),
                            subtitle: Text(
                              '${dayLabel(t.date)} · ${amount(t.price, currency: t.currency)} · commissioni ${amount(t.fees, currency: t.currency)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Modifica operazione',
                                  onPressed: () => _edit(
                                    trade: t,
                                    holding: c.holdings.firstWhere(
                                      (h) => h.symbol == t.symbol,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Elimina operazione',
                                  onPressed: () => _delete(t),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  height: 330,
                ),
                const BoardModule(
                  'Fonti',
                  'Dati e metodo',
                  FinanceCard(
                    title: 'Come vengono calcolati',
                    child: Text(
                      'Inserisci a mano quantità e capitale iniziale di ogni titolo. Il prezzo medio di carico usa il capitale iniziale completo, evitando arrotondamenti. I saldi iniziali sono modificabili; le nuove operazioni includono le commissioni. Le valute diverse da EUR sono escluse dai totali finché non esiste un cambio documentato.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  height: 180,
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  Widget _kpi(String title, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
      ),
      const SizedBox(height: 9),
      Text(
        value,
        style: const TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
    ],
  );
  Widget _allocation(String label, double value, double total) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            Text(
              total > 0
                  ? amount(value / total * 100, currency: '%', digits: 1)
                  : '—',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: total > 0 ? (value / total).clamp(0, 1) : 0,
          minHeight: 6,
          borderRadius: BorderRadius.circular(4),
          backgroundColor: AppColors.greenSoft,
        ),
      ],
    ),
  );
  Widget _position(Position p, PortfolioController c) {
    final h = p.holding, v = c.value(p), q = c.quote(h);
    final profit = v == null ? null : v - p.cost;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${h.name} · ${h.symbol}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => _edit(holding: h),
                child: const Text('Operazione'),
              ),
              IconButton(
                tooltip: 'Correggi saldo iniziale / prezzo manuale',
                onPressed: () => _edit(holding: h, opening: true),
                icon: const Icon(Icons.tune, size: 18),
              ),
            ],
          ),
          Wrap(
            spacing: 22,
            runSpacing: 8,
            children: [
              Text('Quantità ${amount(p.quantity, currency: '', digits: 4)}'),
              Text(
                'PMC ${amount(p.averageCost, currency: h.currency, digits: 4)}',
              ),
              Text('Prezzo ${amount(c.price(h), currency: h.currency)}'),
              Text('Costo residuo ${amount(p.cost, currency: h.currency)}'),
              Text('Valore ${amount(v, currency: h.currency)}'),
              Text(
                'Non realizzato ${amount(profit, currency: h.currency)} (${amount(profit == null || p.cost == 0 ? null : profit / p.cost * 100, currency: '%')})',
              ),
              Text('Realizzato ${amount(p.realized, currency: h.currency)}'),
              Text(
                'Peso ${amount(h.currency == 'EUR' && v != null && c.totalValue > 0 ? v / c.totalValue * 100 : null, currency: '%')}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            q == null
                ? 'Prezzo manuale/importato: ${h.snapshotDate == null ? 'non disponibile' : dayLabel(h.snapshotDate!)}${c.quoteErrors.containsKey(h.symbol) ? ' · aggiornamento non disponibile' : ''}'
                : 'Quotazione ${q.exchange} · ${dayLabel(q.points.last.time)} ${q.points.last.time.hour.toString().padLeft(2, '0')}:${q.points.last.time.minute.toString().padLeft(2, '0')} · può essere ritardata',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _TradeDialog extends StatefulWidget {
  const _TradeDialog({
    required this.controller,
    this.holding,
    this.trade,
    this.opening = false,
  });
  final PortfolioController controller;
  final Holding? holding;
  final PortfolioTrade? trade;
  final bool opening;
  @override
  State<_TradeDialog> createState() => _TradeDialogState();
}

class _TradeDialogState extends State<_TradeDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _symbol,
      _name,
      _currency,
      _quantity,
      _price,
      _fees,
      _cost;
  late AssetKind _kind;
  late DateTime _date, _priceDate;
  bool _buy = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final h = widget.holding, t = widget.trade;
    _symbol = TextEditingController(text: h?.symbol ?? '');
    _name = TextEditingController(text: h?.name ?? '');
    _currency = TextEditingController(text: h?.currency ?? 'EUR');
    _quantity = TextEditingController(
      text:
          (widget.opening ? h?.openingQuantity : t?.quantity)?.toString() ?? '',
    );
    _price = TextEditingController(
      text: (widget.opening ? h?.snapshotPrice : t?.price)?.toString() ?? '',
    );
    _fees = TextEditingController(text: t?.fees.toString() ?? '0');
    _cost = TextEditingController(text: h?.openingCost.toString() ?? '0');
    _kind = h?.kind ?? AssetKind.etf;
    _buy = t?.buy ?? true;
    _date = (widget.opening ? h?.openingDate : t?.date) ?? DateTime.now();
    _priceDate = h?.snapshotDate ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [
      _symbol,
      _name,
      _currency,
      _quantity,
      _price,
      _fees,
      _cost,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController c) =>
      double.parse(c.text.trim().replaceAll(',', '.'));
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final symbol = _symbol.text.trim().toUpperCase(),
          currency = _currency.text.trim().toUpperCase();
      final h = widget.holding;
      if (h == null &&
          widget.controller.holdings.any((h) => h.symbol == symbol)) {
        throw ArgumentError(
          'Strumento già presente: usa Operazione nella posizione esistente.',
        );
      }
      await widget.controller.save(
        holding: widget.opening
            ? Holding(
                symbol: symbol,
                name: _name.text.trim(),
                currency: currency,
                kind: _kind,
                openingQuantity: _number(_quantity),
                openingCost: _number(_cost),
                openingDate: _date,
                snapshotPrice: _number(_price),
                snapshotDate: _priceDate,
              )
            : h == null
            ? Holding(
                symbol: symbol,
                name: _name.text.trim(),
                currency: currency,
                kind: _kind,
              )
            : null,
        trade: widget.opening
            ? null
            : PortfolioTrade(
                id:
                    widget.trade?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                symbol: symbol,
                date: _date,
                buy: _buy,
                quantity: _number(_quantity),
                price: _number(_price),
                fees: _number(_fees),
                currency: currency,
              ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Widget _field(
    String label,
    TextEditingController c, {
    bool number = false,
    bool locked = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: c,
      readOnly: locked,
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Campo obbligatorio';
        if (number) {
          final n = double.tryParse(v.trim().replaceAll(',', '.'));
          if (n == null || !n.isFinite || n < 0) {
            return 'Inserisci un numero positivo, senza separatore delle migliaia';
          }
        }
        return null;
      },
    ),
  );
  Future<void> _pickDate(bool price) async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: price ? _priceDate : _date,
    );
    if (result != null && mounted) {
      setState(() {
        if (price) {
          _priceDate = result;
        } else {
          _date = result;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.opening
          ? 'Saldo iniziale e prezzo manuale'
          : widget.trade != null
          ? 'Modifica operazione'
          : widget.holding == null
          ? 'Aggiungi strumento'
          : 'Registra operazione',
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.holding == null || widget.opening) ...[
                DropdownButtonFormField<AssetKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Tipologia'),
                  items: [
                    for (final k in AssetKind.values)
                      DropdownMenuItem(value: k, child: Text(k.label)),
                  ],
                  onChanged: (v) => setState(() => _kind = v!),
                ),
                const SizedBox(height: 14),
                _field(
                  'Ticker (es. VWCE.DE, BTC-EUR)',
                  _symbol,
                  locked: widget.holding != null,
                ),
                _field('Nome', _name),
                _field(
                  'Valuta (EUR, USD…)',
                  _currency,
                  locked: widget.holding != null,
                ),
              ] else
                Text('${widget.holding!.name} · ${widget.holding!.currency}'),
              if (!widget.opening)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Acquisto')),
                      ButtonSegment(value: false, label: Text('Vendita')),
                    ],
                    selected: {_buy},
                    onSelectionChanged: (v) => setState(() => _buy = v.single),
                  ),
                ),
              _field('Quantità', _quantity, number: true),
              _field(
                widget.opening
                    ? 'Prezzo manuale di riferimento'
                    : 'Prezzo unitario',
                _price,
                number: true,
              ),
              if (widget.opening)
                _field('Capitale iniziale totale', _cost, number: true)
              else
                _field('Commissioni', _fees, number: true),
              TextButton.icon(
                onPressed: () => _pickDate(false),
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  '${widget.opening ? 'Inizio ricostruzione' : 'Data operazione'}: ${dayLabel(_date)}',
                ),
              ),
              if (widget.opening)
                TextButton(
                  onPressed: () => _pickDate(true),
                  child: Text('Data prezzo manuale: ${dayLabel(_priceDate)}'),
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Salvataggio…' : 'Salva nel registro'),
      ),
    ],
  );
}
