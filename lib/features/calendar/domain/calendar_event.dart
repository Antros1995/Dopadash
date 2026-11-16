class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.subject,
    required this.startDateTime,
    required this.endDateTime,
    required this.location,
    required this.isAllDay,
    required this.isCancelled,
  });

  factory CalendarEvent.fromJson(Map<String, Object?> json) {
    final start = _requiredMap(json['start'], 'start');
    final end = _requiredMap(json['end'], 'end');
    return CalendarEvent(
      id: _requiredString(json['id'], 'id'),
      subject: _requiredString(json['subject'], 'subject'),
      startDateTime: _requiredString(start['dateTime'], 'start.dateTime'),
      endDateTime: _requiredString(end['dateTime'], 'end.dateTime'),
      location: json['location'] is String ? json['location']! as String : '',
      isAllDay: json['isAllDay'] == true,
      isCancelled: json['isCancelled'] == true,
    );
  }

  final String id;
  final String subject;
  final String startDateTime;
  final String endDateTime;
  final String location;
  final bool isAllDay;
  final bool isCancelled;

  String get startLabel => isAllDay ? 'Tutto il giorno' : _time(startDateTime);
  String get endLabel => isAllDay ? '' : _time(endDateTime);

  static String _time(String value) {
    final match = RegExp(r'T(\d{2}):(\d{2})').firstMatch(value);
    return match == null ? '--:--' : '${match.group(1)}:${match.group(2)}';
  }
}

class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.timeZone,
    required this.events,
  });

  factory CalendarDay.fromJson(Map<String, Object?> json) {
    final rawEvents = json['events'];
    if (rawEvents is! List<Object?>) {
      throw const FormatException('events non valido');
    }
    return CalendarDay(
      date: _requiredString(json['date'], 'date'),
      timeZone: _requiredString(json['timeZone'], 'timeZone'),
      events: rawEvents
          .map((event) {
            if (event is! Map<String, Object?>) {
              throw const FormatException('evento non valido');
            }
            return CalendarEvent.fromJson(event);
          })
          .where((event) => !event.isCancelled)
          .toList(growable: false),
    );
  }

  final String date;
  final String timeZone;
  final List<CalendarEvent> events;
}

Map<String, Object?> _requiredMap(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name non valido');
  }
  return value;
}

String _requiredString(Object? value, String name) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$name non valido');
  }
  return value;
}
