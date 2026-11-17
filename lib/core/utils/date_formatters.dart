import '../i18n/i18n.dart';

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

const _weekdaysEnglish = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _monthsEnglish = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Weekday name in the interface language ("lunedì" / "Monday").
String weekdayName(DateTime date) =>
    (isEnglish ? _weekdaysEnglish : _weekdays)[date.weekday - 1];

/// Month name in the interface language ("novembre" / "November").
String monthName(int month) =>
    (isEnglish ? _monthsEnglish : _months)[month - 1];

/// "lunedì, 16 novembre 2026" in Italian, "Monday, 16 November 2026" in English.
String formatLongDate(DateTime date, {bool includeYear = true}) {
  final base = '${weekdayName(date)}, ${date.day} ${monthName(date.month)}';
  return includeYear ? '$base ${date.year}' : base;
}

String formatShortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String capitalize(String value) => value.isEmpty
    ? value
    : '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';
