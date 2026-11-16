const _weekdays = <String>[
  'lunedì',
  'martedì',
  'mercoledì',
  'giovedì',
  'venerdì',
  'sabato',
  'domenica',
];

const _months = <String>[
  'gennaio',
  'febbraio',
  'marzo',
  'aprile',
  'maggio',
  'giugno',
  'luglio',
  'agosto',
  'settembre',
  'ottobre',
  'novembre',
  'dicembre',
];

String formatItalianDate(DateTime date, {bool includeYear = true}) {
  final base =
      '${_weekdays[date.weekday - 1]}, ${date.day} '
      '${_months[date.month - 1]}';
  return includeYear ? '$base ${date.year}' : base;
}

String formatShortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String capitalize(String value) => value.isEmpty
    ? value
    : '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';
