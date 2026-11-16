import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:monitoraggio_personale_desktop/features/fitbit/data/fitbit_repository.dart';
import 'package:supabase/supabase.dart';

void main() {
  test(
    'reads a finalized Google Health daily snapshot through the agent',
    () async {
      late http.Request captured;
      final repository = PersonalAgentFitbitRepository(
        supabase: SupabaseClient(
          'https://project.supabase.co',
          'sb_publishable_test',
        ),
        apiBaseUrl: Uri.parse('https://agent.example/'),
        accessTokenProvider: () => 'supabase-access-token',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'configured': true,
              'connection': 'CONNECTED',
              'deviceName': 'Charge 6',
              'day': {
                'date': '2026-08-25',
                'finalized': true,
                'syncedAt': '2026-08-26T00:15:00.000Z',
                'steps': 8432,
                'distanceKm': 6.1,
                'calories': 2140,
                'activeMinutes': 48,
                'activeZoneMinutes': 24,
                'activeZoneMinutesByZone': {
                  'fatBurn': 12,
                  'cardio': 8,
                  'peak': 4,
                },
                'restingHeartRate': 58,
                'sleepMinutes': 441,
                'sleepEfficiency': 92,
                'sleepDetails': {
                  'startTime': '2026-08-24T22:00:00.000Z',
                  'endTime': '2026-08-25T06:00:00.000Z',
                  'type': 'STAGES',
                  'processed': true,
                  'stagesStatus': 'SUCCEEDED',
                  'minutesInSleepPeriod': 480,
                  'minutesAwake': 39,
                  'minutesToFallAsleep': 0,
                  'minutesAfterWakeUp': 0,
                  'stageMinutes': {
                    'awake': 39,
                    'light': 241,
                    'deep': 100,
                    'rem': 100,
                    'asleep': 0,
                    'restless': 0,
                  },
                  'shortAwakenings': [],
                },
                'vo2Max': {
                  'value': 43.2,
                  'measuredDate': '2026-08-25',
                  'cardioFitnessLevel': 'GOOD',
                  'estimated': false,
                },
              },
            }),
            200,
          );
        }),
      );

      final status = await repository.fetchDay(DateTime(2026, 8, 25));

      expect(
        captured.url.toString(),
        'https://agent.example/api/desktop/fitbit?date=2026-08-25',
      );
      expect(captured.headers['authorization'], 'Bearer supabase-access-token');
      expect(status.deviceName, 'Charge 6');
      expect(status.day?.finalized, isTrue);
      expect(status.day?.steps, 8432);
      expect(status.day?.activeZoneMinutes, 24);
      expect(status.day?.sleepDetails?.minutesAwake, 39);
      expect(status.day?.sleepDetails?.stageMinutes.deep, 100);
      expect(status.day?.vo2Max?.value, 43.2);
    },
  );

  test(
    'saves manually entered mindfulness minutes for the selected day',
    () async {
      late http.Request captured;
      final repository = PersonalAgentFitbitRepository(
        supabase: SupabaseClient(
          'https://project.supabase.co',
          'sb_publishable_test',
        ),
        apiBaseUrl: Uri.parse('https://agent.example/'),
        accessTokenProvider: () => 'supabase-access-token',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'configured': true,
              'connection': 'CONNECTED',
              'deviceName': 'Charge 6',
              'day': {
                'date': '2026-08-25',
                'finalized': true,
                'syncedAt': '2026-08-26T00:15:00.000Z',
                'steps': 0,
                'distanceKm': 0,
                'calories': 0,
                'activeMinutes': 0,
                'mindfulnessMinutes': 12,
                'restingHeartRate': null,
                'sleepMinutes': null,
                'sleepEfficiency': null,
              },
            }),
            200,
          );
        }),
      );

      final status = await repository.saveMindfulnessMinutes(
        DateTime(2026, 8, 25),
        12,
      );

      expect(captured.method, 'POST');
      expect(captured.headers['content-type'], contains('application/json'));
      expect(jsonDecode(captured.body), {
        'date': '2026-08-25',
        'mindfulnessMinutes': 12,
      });
      expect(status.day?.mindfulnessMinutes, 12);
    },
  );
}
