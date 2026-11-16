import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:monitoraggio_personale_desktop/features/calendar/data/calendar_repository.dart';
import 'package:supabase/supabase.dart';

void main() {
  group('PersonalAgentCalendarRepository', () {
    test('sends the Supabase session and parses Outlook events', () async {
      late http.Request capturedRequest;
      final repository = PersonalAgentCalendarRepository(
        supabase: SupabaseClient(
          'https://project.supabase.co',
          'sb_publishable_test',
        ),
        apiBaseUrl: Uri.parse('https://agent.example/'),
        accessTokenProvider: () => 'supabase-access-token',
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'date': '2026-08-25',
              'timeZone': 'Europe/Rome',
              'events': [
                {
                  'id': 'event-1',
                  'subject': 'Riunione',
                  'start': {
                    'dateTime': '2026-08-25T09:00:00',
                    'timeZone': 'Europe/Rome',
                  },
                  'end': {
                    'dateTime': '2026-08-25T10:00:00',
                    'timeZone': 'Europe/Rome',
                  },
                  'location': 'Online',
                  'isAllDay': false,
                  'isCancelled': false,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final day = await repository.fetchDay(DateTime(2026, 8, 25));

      expect(
        capturedRequest.url.toString(),
        'https://agent.example/api/desktop/calendar?date=2026-08-25',
      );
      expect(
        capturedRequest.headers['authorization'],
        'Bearer supabase-access-token',
      );
      expect(day.events.single.subject, 'Riunione');
      expect(day.events.single.startLabel, '09:00');
    });

    test('maps a disconnected Outlook account to the dedicated failure', () {
      final repository = PersonalAgentCalendarRepository(
        supabase: SupabaseClient(
          'https://project.supabase.co',
          'sb_publishable_test',
        ),
        apiBaseUrl: Uri.parse('https://agent.example/'),
        accessTokenProvider: () => 'supabase-access-token',
        httpClient: MockClient((_) async => http.Response('{}', 409)),
      );

      expect(
        repository.fetchDay(DateTime(2026, 8, 25)),
        throwsA(
          isA<CalendarFailure>().having(
            (failure) => failure.kind,
            'kind',
            CalendarFailureKind.outlookNotConnected,
          ),
        ),
      );
    });

    test('requests a Microsoft authorization URL with the session', () async {
      late http.Request capturedRequest;
      final repository = PersonalAgentCalendarRepository(
        supabase: SupabaseClient(
          'https://project.supabase.co',
          'sb_publishable_test',
        ),
        apiBaseUrl: Uri.parse('https://agent.example/'),
        accessTokenProvider: () => 'supabase-access-token',
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'authorizationUrl':
                  'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
            }),
            200,
          );
        }),
      );

      final uri = await repository.beginOutlookConnect();

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url.toString(),
        'https://agent.example/api/desktop/outlook/connect',
      );
      expect(
        capturedRequest.headers['authorization'],
        'Bearer supabase-access-token',
      );
      expect(uri.host, 'login.microsoftonline.com');
    });
  });
}
