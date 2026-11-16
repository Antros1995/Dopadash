import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:supabase/supabase.dart';

/// Dati dell'Alimentazione: lo stesso stato che il componente Dieta salva
/// nella tabella `diet_app_states` (piani, pasti registrati, cibi aggiunti,
/// combinazioni salvate…).
abstract interface class DietStateRepository {
  Future<Map<String, dynamic>?> fetchState();
}

class SupabaseDietStateRepository implements DietStateRepository {
  SupabaseDietStateRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> fetchState() async {
    final user = _client.auth.currentUser?.id;
    if (user == null) throw StateError('Accedi per esportare la dieta.');
    final row = await _client
        .from('diet_app_states')
        .select('state')
        .eq('user_id', user)
        .maybeSingle();
    final state = row?['state'];
    return state is Map ? state.cast<String, dynamic>() : null;
  }
}

enum DietExportPart {
  daily('Calorie giorno per giorno'),
  meals('Pasti registrati (cosa hai scelto)'),
  extras('Cibi fuori piano'),
  plans('Piani dieta completi'),
  saved('Combinazioni e alimenti creati da te'),
  backup('Copia completa della dieta (file JSON)');

  const DietExportPart(this.label);
  final String label;
}

const _mealNames = [
  'Colazione',
  'Spuntino mattina',
  'Pranzo',
  'Spuntino pomeriggio',
  'Cena',
  'Fuori pasto',
];

String _mealName(Object? index) {
  final i = (index as num?)?.toInt();
  return i != null && i >= 0 && i < _mealNames.length ? _mealNames[i] : '—';
}

/// Fogli Excel dell'Alimentazione. Le date sono quelle del periodo scelto;
/// i piani sono esportati per intero se si sovrappongono al periodo.
class DietSheets {
  DietSheets(this.state, this.start, this.end);
  final Map<String, dynamic> state;
  final DateTime start, end;

  List<Map<String, dynamic>> _list(String key) => [
    for (final item in (state[key] as List?) ?? const [])
      if (item is Map) item.cast<String, dynamic>(),
  ];

  List<Map<String, dynamic>> get diets => _list('diets');
  Map<String, dynamic> get logs =>
      (state['logs'] as Map?)?.cast<String, dynamic>() ?? const {};

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  bool _inRange(String? date) =>
      date != null &&
      date.compareTo(_key(start)) >= 0 &&
      date.compareTo(_key(end)) <= 0;

  Iterable<String> get _dates sync* {
    var d = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!d.isAfter(last)) {
      yield _key(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
  }

  Map<String, dynamic>? _dietOn(String date) {
    for (final d in diets) {
      if ('${d['start']}'.compareTo(date) <= 0 &&
          '${d['end']}'.compareTo(date) >= 0) {
        return d;
      }
    }
    return null;
  }

  static num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

  /// Calorie di un pasto registrato: somma degli alimenti scelti.
  static num _logCalories(Map<String, dynamic>? log) {
    if (log == null) return 0;
    num total = 0;
    for (final item in (log['items'] as List?) ?? const []) {
      if (item is Map) total += _num(item['calories']) ?? 0;
    }
    return total;
  }

  /// Calorie mangiate per giorno (`AAAA-MM-GG`): pasti registrati del piano
  /// più i cibi fuori piano. Solo i giorni con almeno un dato.
  static Map<String, num> dailyCalories(Map<String, dynamic> state) {
    final result = <String, num>{};
    final logs = (state['logs'] as Map?) ?? const {};
    for (final entry in logs.entries) {
      final parts = '${entry.key}'.split(':');
      if (parts.length < 3 || entry.value is! Map) continue;
      final date = parts[parts.length - 2];
      result[date] =
          (result[date] ?? 0) +
          _logCalories((entry.value as Map).cast<String, dynamic>());
    }
    for (final e in (state['extraFoods'] as List?) ?? const []) {
      if (e is! Map || e['date'] is! String) continue;
      result[e['date'] as String] =
          (result[e['date'] as String] ?? 0) + (_num(e['kcal']) ?? 0);
    }
    return result;
  }

  List<Map<String, dynamic>> _extrasOn(String date) =>
      _list('extraFoods').where((e) => e['date'] == date).toList();

  void fillDaily(Sheet sheet) {
    _header(sheet, [
      'Data',
      'Dieta',
      'Obiettivo (kcal)',
      'Dal piano (kcal)',
      'Fuori piano (kcal)',
      'Totale (kcal)',
      'Differenza dall’obiettivo',
      'Pasti registrati',
    ]);
    for (final date in _dates) {
      final diet = _dietOn(date);
      num plan = 0;
      var logged = 0;
      if (diet != null) {
        for (var i = 0; i < 5; i++) {
          final log = logs['${diet['id']}:$date:$i'];
          if (log is Map) {
            logged++;
            plan += _logCalories(log.cast<String, dynamic>());
          }
        }
      }
      final extra = _extrasOn(
        date,
      ).fold<num>(0, (n, e) => n + (_num(e['kcal']) ?? 0));
      final target =
          _num(diet?['dailyCalories']) ?? _num(state['calorieTarget']);
      final total = plan + extra;
      // Solo i giorni con qualcosa di registrato: uno 0 sembrerebbe un digiuno.
      if (logged == 0 && extra == 0) continue;
      sheet.appendRow([
        _date(date),
        _text(diet?['name']),
        _number(target),
        _number(plan),
        _number(extra),
        _number(total),
        target == null ? null : _number(total - target),
        IntCellValue(logged),
      ]);
    }
    _size(sheet, 8);
  }

  void fillMeals(Sheet sheet) {
    _header(sheet, [
      'Data',
      'Dieta',
      'Pasto',
      'Alimento',
      'Quantità',
      'Kcal',
      'Registrato il',
    ]);
    final byId = {for (final d in diets) '${d['id']}': d};
    final rows = <List<CellValue?>>[];
    for (final entry in logs.entries) {
      final parts = entry.key.split(':');
      if (parts.length < 3 || entry.value is! Map) continue;
      final meal = int.tryParse(parts.last);
      final date = parts[parts.length - 2];
      final dietId = parts.sublist(0, parts.length - 2).join(':');
      if (!_inRange(date)) continue;
      final log = (entry.value as Map).cast<String, dynamic>();
      final items = [
        for (final i in (log['items'] as List?) ?? const [])
          if (i is Map) i.cast<String, dynamic>(),
      ];
      final base = [
        _date(date),
        _text(byId[dietId]?['name'] ?? dietId),
        _text(_mealName(meal)),
      ];
      if (items.isEmpty) {
        rows.add([
          ...base,
          _text(
            log['viaExtras'] == true
                ? 'Completato con cibi fuori piano'
                : 'Completato',
          ),
          null,
          null,
          _text(log['at']),
        ]);
      }
      for (final item in items) {
        rows.add([
          ...base,
          _text('${item['name'] ?? ''}'),
          _text(item['quantity'] as String?),
          _number(_num(item['calories'])),
          _text(log['at']),
        ]);
      }
    }
    rows.sort((a, b) {
      final da = (a[0] as DateCellValue?), db = (b[0] as DateCellValue?);
      final ka = da == null ? '' : '${da.year}${da.month}${da.day}';
      final kb = db == null ? '' : '${db.year}${db.month}${db.day}';
      return ka.compareTo(kb);
    });
    for (final r in rows) {
      sheet.appendRow(r);
    }
    _size(sheet, 7);
  }

  void fillExtras(Sheet sheet) {
    _header(sheet, [
      'Data',
      'Pasto',
      'Piatto',
      'Alimento',
      'Quantità',
      'Kcal',
      'Proteine (g)',
      'Carboidrati (g)',
      'Grassi (g)',
      'Al posto di',
      'Registrato il',
    ]);
    final extras =
        _list(
          'extraFoods',
        ).where((e) => _inRange(e['date'] as String?)).toList()..sort(
          (a, b) =>
              '${a['date']}${a['at']}'.compareTo('${b['date']}${b['at']}'),
        );
    for (final e in extras) {
      final parts = [
        for (final i in (e['items'] as List?) ?? [e])
          if (i is Map) i.cast<String, dynamic>(),
      ];
      for (final p in parts) {
        final grams = _num(p['grams']);
        sheet.appendRow([
          _date('${e['date']}'),
          _text(_mealName(e['meal'])),
          _text('${e['name'] ?? ''}'),
          _text('${p['name'] ?? ''}'),
          _text(
            grams == null ? null : '$grams ${p['unit'] == 'ml' ? 'ml' : 'g'}',
          ),
          _number(_num(p['kcal'])),
          _number(_num(p['protein'])),
          _number(_num(p['carbs'])),
          _number(_num(p['fat'])),
          _text(e['replaces'] as String?),
          _text(e['at'] as String?),
        ]);
      }
    }
    _size(sheet, 11);
  }

  void fillPlans(Sheet sheet) {
    _header(sheet, [
      'Dieta',
      'Dal',
      'Al',
      'Kcal al giorno',
      'Pasto',
      'Kcal pasto',
      'Gruppo',
      'Scelta',
      'Alimento o piatto',
      'Quantità',
      'Kcal',
      'Limite settimanale',
    ]);
    for (final diet in diets) {
      if ('${diet['end']}'.compareTo(_key(start)) < 0 ||
          '${diet['start']}'.compareTo(_key(end)) > 0) {
        continue;
      }
      final meals = (diet['meals'] as List?) ?? const [];
      final mealKcal = (diet['mealCalories'] as List?) ?? const [];
      void walk(List groups, int meal, String path) {
        for (final g in groups) {
          if (g is! Map) continue;
          final groupPath = path.isEmpty
              ? '${g['name']}'
              : '$path › ${g['name']}';
          for (final o in (g['options'] as List?) ?? const []) {
            if (o is! Map) continue;
            sheet.appendRow([
              _text('${diet['name']}'),
              _date('${diet['start']}'),
              _date('${diet['end']}'),
              _number(_num(diet['dailyCalories'])),
              _text(_mealName(meal)),
              _number(meal < mealKcal.length ? _num(mealKcal[meal]) : null),
              _text(groupPath),
              _text(switch (g['mode']) {
                'one' => 'Una a scelta',
                'all' => 'Tutte',
                'many' => 'Più scelte',
                _ => '${g['mode'] ?? ''}',
              }),
              _text('${o['name'] ?? ''}'),
              _text(o['quantity'] as String?),
              _number(_num(o['calories'])),
              _number(_num(o['weeklyLimit'])),
            ]);
            final sub = o['groups'];
            if (sub is List && sub.isNotEmpty) {
              walk(sub, meal, '$groupPath › ${o['name']}');
            }
          }
        }
      }

      for (var i = 0; i < meals.length; i++) {
        if (meals[i] is List) walk(meals[i] as List, i, '');
      }
    }
    _size(sheet, 12);
  }

  void fillSaved(Sheet sheet) {
    _header(sheet, ['Tipo', 'Nome', 'Kcal', 'Dettaglio']);
    for (final c in _list('savedCombos')) {
      sheet.appendRow([
        _text('Combinazione'),
        _text('${c['name'] ?? ''}'),
        _number(_num(c['kcal'])),
        _text(
          [
            for (final i in (c['items'] as List?) ?? const [])
              if (i is Map)
                '${i['name']}${i['grams'] == null ? '' : ' ${i['grams']} ${i['unit'] == 'ml' ? 'ml' : 'g'}'}',
          ].join(' · '),
        ),
      ]);
    }
    for (final f in _list('customFoods')) {
      sheet.appendRow([
        _text('Alimento creato'),
        _text('${f['name'] ?? ''}'),
        _number(_num(f['kcal'])),
        _text(
          'per 100 g · proteine ${f['protein'] ?? '—'} g · carboidrati ${f['carbs'] ?? '—'} g · grassi ${f['fat'] ?? '—'} g',
        ),
      ]);
    }
    _size(sheet, 4);
  }

  /// Tutto lo stato, così com'è salvato: utile da rianalizzare nel tempo.
  static Uint8List backup(Map<String, dynamic> state) => Uint8List.fromList(
    utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'source': 'diet_app_states',
        'state': state,
      }),
    ),
  );

  static void _header(Sheet sheet, List<String> labels) {
    sheet.appendRow([for (final l in labels) TextCellValue(l)]);
    final style = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#FFB5612B'),
      verticalAlign: VerticalAlign.Center,
    );
    for (final cell in sheet.row(0)) {
      cell?.cellStyle = style;
    }
  }

  static void _size(Sheet sheet, int count) {
    for (var i = 0; i < count; i++) {
      sheet.setColumnWidth(i, i == 0 ? 13 : 22);
    }
  }

  static CellValue? _date(String? value) {
    final d = DateTime.tryParse(value ?? '');
    return d == null
        ? _text(value)
        : DateCellValue(year: d.year, month: d.month, day: d.day);
  }

  static CellValue? _text(Object? value) =>
      value == null || '$value'.isEmpty ? null : TextCellValue('$value');
  static CellValue? _number(num? value) => value == null
      ? null
      : value is int || value == value.roundToDouble()
      ? IntCellValue(value.round())
      : DoubleCellValue(value.toDouble());
}
