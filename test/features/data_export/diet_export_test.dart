import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoraggio_personale_desktop/features/data_export/data/diet_export.dart';
import 'package:monitoraggio_personale_desktop/features/data_export/data/export_workbook_builder.dart';

final _state = <String, dynamic>{
  'diets': [
    {
      'id': 'd1',
      'name': 'Massa braccia',
      'start': '2026-11-16',
      'end': '2026-12-03',
      'dailyCalories': 2750,
      'mealCalories': [540, 250, 810, 320, 810],
      'meals': [
        [
          {
            'name': 'Colazione',
            'mode': 'one',
            'options': [
              {'name': 'Avena + Whey', 'quantity': 'Porridge', 'calories': 561},
            ],
          },
        ],
        [],
        [
          {
            'name': 'Piatto',
            'mode': 'one',
            'options': [
              {
                'name': 'Pasta o Riso + Pesce',
                'groups': [
                  {
                    'name': 'Pesce',
                    'mode': 'one',
                    'options': [
                      {
                        'name': 'Merluzzo',
                        'quantity': '250 g',
                        'calories': 178,
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
        [],
        [],
      ],
    },
  ],
  'logs': {
    'd1:2026-11-17:0': {
      'items': [
        {'name': 'Avena + Whey', 'quantity': 'Porridge', 'calories': 561},
      ],
      'at': '2026-11-17T07:30:00Z',
    },
  },
  'extraFoods': [
    {
      'id': 'x',
      'date': '2026-11-17',
      'meal': 3,
      'name': 'Pasta al tonno',
      'kcal': 367,
      'items': [
        {'name': 'Pasta', 'grams': 80, 'unit': 'g', 'kcal': 282},
        {'name': 'Tonno', 'grams': 112, 'unit': 'g', 'kcal': 85},
      ],
    },
  ],
  'savedCombos': [
    {'name': 'Pasta al tonno', 'kcal': 367, 'items': []},
  ],
  'customFoods': [],
};

void main() {
  test('daily calories add plan meals and off-plan foods', () {
    expect(DietSheets.dailyCalories(_state), {'2026-11-17': 561 + 367});
  });

  test('workbook gets one sheet per selected diet part', () {
    final bytes = const ExportWorkbookBuilder().build(
      ExportWorkbookInput(
        start: DateTime(2026, 11, 16),
        end: DateTime(2026, 11, 30),
        fitbitFields: const {},
        fitbitDays: const {},
        routineIds: const {},
        routineHistory: const [],
        routineEntries: const {},
        dietParts: const {
          DietExportPart.daily,
          DietExportPart.meals,
          DietExportPart.extras,
          DietExportPart.plans,
          DietExportPart.saved,
        },
        dietState: _state,
      ),
    );
    final excel = Excel.decodeBytes(bytes);
    expect(
      excel.tables.keys,
      containsAll([
        'Dieta - calorie',
        'Dieta - pasti',
        'Dieta - fuori piano',
        'Dieta - piani',
        'Dieta - combinazioni',
      ]),
    );
    final daily = excel.tables['Dieta - calorie']!;
    expect(daily.maxRows, 2);
    expect(daily.row(1)[5]?.value.toString(), '928');
    final plans = excel.tables['Dieta - piani']!;
    expect(
      plans.rows.any(
        (r) =>
            r[6]?.value.toString() == 'Piatto › Pasta o Riso + Pesce › Pesce',
      ),
      isTrue,
    );
    expect(excel.tables['Dieta - fuori piano']!.maxRows, 3);
  });
}
