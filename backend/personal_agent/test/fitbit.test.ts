import { afterEach, describe, expect, it, vi } from "vitest";

import { fetchFitbitDay } from "../src/fitbit/api";
import {
  beginFitbitAuthorization,
  completeFitbitAuthorization,
} from "../src/fitbit/auth";
import { decryptSecret } from "../src/outlook/crypto";

const encryptionKey = btoa(String.fromCharCode(...new Uint8Array(32).fill(9)));
const config = {
  clientId: "fitbit-client",
  clientSecret: "fitbit-secret",
  redirectUri: "https://example.workers.dev/oauth/fitbit/callback",
  encryptionKey,
};

afterEach(() => vi.restoreAllMocks());

describe("Fitbit OAuth", () => {
  it("uses authorization code PKCE and encrypts returned tokens", async () => {
    const authorization = await beginFitbitAuthorization(config, {}, new Date(0));
    const url = new URL(authorization.url);
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
    expect(url.origin).toBe("https://accounts.google.com");
    expect(url.searchParams.get("scope")).toContain(
      "googlehealth.activity_and_fitness.readonly",
    );
    expect(url.searchParams.get("access_type")).toBe("offline");

    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          access_token: "fitbit-access",
          refresh_token: "fitbit-refresh",
          expires_in: 28_800,
          scope: "activity heartrate sleep profile",
        }),
      ),
    );
    const completed = await completeFitbitAuthorization(
      authorization.state,
      config,
      "code",
      authorization.state.oauthState!,
      new Date(1),
    );
    expect(JSON.stringify(completed.state)).not.toContain("fitbit-refresh");
    expect(
      await decryptSecret(completed.state.refreshToken!, encryptionKey),
    ).toBe("fitbit-refresh");
  });
});

describe("Fitbit daily snapshot", () => {
  it("combines activity and sleep into a final daily record", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            rollupDataPoints: [
              {
                civilStartTime: { date: { year: 2026, month: 8, day: 25 } },
                steps: { countSum: "8432" },
              },
              {
                civilStartTime: { date: { year: 2026, month: 8, day: 26 } },
                steps: { countSum: "99999" },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ rollupDataPoints: [{ distance: { millimetersSum: "6100000" } }] }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ rollupDataPoints: [{ totalCalories: { kcalSum: 2140 } }] })),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            rollupDataPoints: [
              {
                activeMinutes: {
                  activeMinutesRollupByActivityLevel: [
                    { activityLevel: "MODERATE", activeMinutesSum: "18" },
                    { activityLevel: "VIGOROUS", activeMinutesSum: "30" },
                  ],
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            rollupDataPoints: [
              {
                activeZoneMinutes: {
                  sumInFatBurnHeartZone: "12",
                  sumInCardioHeartZone: "8",
                  sumInPeakHeartZone: "4",
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            rollupDataPoints: [{ sedentaryPeriod: { durationSum: "21600s" } }],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            dataPoints: [
              {
                dailyRestingHeartRate: {
                  date: { year: 2026, month: 8, day: 25 },
                  beatsPerMinute: "58",
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            dataPoints: [
              {
                sleep: {
                  interval: {
                    startTime: "2026-08-24T22:00:00Z",
                    endTime: "2026-08-25T06:00:00Z",
                    civilEndTime: { date: { year: 2026, month: 8, day: 25 } },
                  },
                  type: "STAGES",
                  metadata: { processed: true, nap: false, stagesStatus: "SUCCEEDED" },
                  summary: {
                    minutesAsleep: "441",
                    minutesInSleepPeriod: "480",
                    minutesAwake: "39",
                    stagesSummary: [
                      { type: "LIGHT", minutes: "241" },
                      { type: "DEEP", minutes: "100" },
                      { type: "REM", minutes: "100" },
                      { type: "AWAKE", minutes: "39" },
                    ],
                  },
                  stages: [
                    {
                      startTime: "2026-08-24T22:00:00Z",
                      endTime: "2026-08-24T23:00:00Z",
                      type: "LIGHT",
                    },
                  ],
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            dataPoints: [
              {
                dailyOxygenSaturation: {
                  date: { year: 2026, month: 8, day: 25 },
                  averagePercentage: 96.4,
                  lowerBoundPercentage: 93.1,
                  upperBoundPercentage: 98.2,
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            dataPoints: [
              {
                dailyHeartRateVariability: {
                  date: { year: 2026, month: 8, day: 25 },
                  averageHeartRateVariabilityMilliseconds: 42.8,
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            dataPoints: [
              {
                dailyRespiratoryRate: {
                  date: { year: 2026, month: 8, day: 25 },
                  breathsPerMinute: 15.2,
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            dataPoints: [
              {
                dailySleepTemperatureDerivations: {
                  date: { year: 2026, month: 8, day: 25 },
                  nightlyTemperatureCelsius: 33.4,
                  baselineTemperatureCelsius: 33.1,
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            dataPoints: [
              {
                dailyVo2Max: {
                  date: { year: 2026, month: 8, day: 25 },
                  vo2Max: 43.2,
                  cardioFitnessLevel: "GOOD",
                  estimated: false,
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            rollupDataPoints: [
              {
                startTime: "2026-08-25T10:00:00Z",
                heartRate: {
                  beatsPerMinuteAvg: 72,
                  beatsPerMinuteMin: 61,
                  beatsPerMinuteMax: 88,
                },
              },
            ],
          }),
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            dataPoints: [
              {
                exercise: {
                  interval: {
                    startTime: "2026-08-25T16:00:00Z",
                    civilStartTime: { date: { year: 2026, month: 8, day: 25 } },
                  },
                  exerciseType: "RUNNING",
                  displayName: "Corsa",
                  activeDuration: "1800s",
                  metricsSummary: {
                    caloriesKcal: 260,
                    distanceMillimeters: 5000000,
                    averageHeartRateBeatsPerMinute: "145",
                  },
                },
              },
            ],
          }),
        ),
      );

    const day = await fetchFitbitDay(
      "2026-08-25",
      "token",
      true,
      new Date("2026-08-26T00:15:00Z"),
    );
    expect(day).toMatchObject({
      date: "2026-08-25",
      finalized: true,
      steps: 8432,
      distanceKm: 6.1,
      calories: 2140,
      activeMinutes: 48,
      sedentaryMinutes: 360,
      activeZoneMinutes: 24,
      restingHeartRate: 58,
      sleepMinutes: 441,
      sleepEfficiency: 92,
      sleepDetails: {
        type: "STAGES",
        processed: true,
        stagesStatus: "SUCCEEDED",
        minutesAwake: 39,
      },
      oxygenSaturation: { average: 96.4, minimum: 93.1, maximum: 98.2 },
      heartRateVariabilityMs: 42.8,
      respiratoryRate: 15.2,
      vo2Max: { value: 43.2, cardioFitnessLevel: "GOOD", estimated: false },
      workouts: [
        {
          type: "RUNNING",
          name: "Corsa",
          activeMinutes: 30,
          calories: 260,
          distanceKm: 5,
          averageHeartRate: 145,
        },
      ],
    });
    expect(day.sleepStages).toHaveLength(1);
    expect(day.heartProfile).toHaveLength(1);
    expect(String(fetchMock.mock.calls[7]?.[0])).toContain(
      "/sleep/dataPoints:reconcile?",
    );
    expect(String(fetchMock.mock.calls[6]?.[0])).toContain(
      "/daily-resting-heart-rate/dataPoints:reconcile?",
    );
  });

  it("uses the newest valid point from the last populated heart rate interval", async () => {
    const sample = (physicalTime: string, beatsPerMinute: string) => ({
      heartRate: { sampleTime: { physicalTime }, beatsPerMinute },
    });
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = new URL(String(input));
      if (url.pathname.endsWith("/heart-rate/dataPoints:rollUp")) {
        return Response.json({ rollupDataPoints: [
          { startTime: "2026-08-25T12:00:00Z", heartRate: { beatsPerMinuteAvg: 72 } },
          { startTime: "2026-08-25T11:30:00Z", heartRate: { beatsPerMinuteAvg: 71 } },
        ] });
      }
      if (url.pathname.endsWith("/heart-rate/dataPoints:reconcile")) {
        const pageToken = url.searchParams.get("pageToken");
        return Response.json(pageToken === "more" ? {
          dataPoints: [sample("2026-08-25T12:17:10Z", "85"), sample("2026-08-25T12:29:10Z", "0")],
        } : {
          dataPoints: [sample("2026-08-25T12:10:00Z", "72")], nextPageToken: "more",
        });
      }
      return Response.json({});
    });

    const day = await fetchFitbitDay("2026-08-25", "token", false, new Date("2026-08-25T13:00:00Z"));
    expect(day.latestHeartRate).toEqual({ measuredAt: "2026-08-25T12:17:10Z", beatsPerMinute: 85 });
    const request = fetchMock.mock.calls.map(([url]) => new URL(String(url)))
      .find((url) => url.pathname.endsWith("/heart-rate/dataPoints:reconcile"));
    expect(request?.searchParams.get("filter")).toBe(
      'heart_rate.sample_time.physical_time >= "2026-08-25T12:00:00Z" AND heart_rate.sample_time.physical_time < "2026-08-25T12:30:00.000Z"',
    );
  });

  it("falls back to the Fitbit sleep session and keeps the latest VO2 max", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url.includes("/sleep/dataPoints:reconcile?")) {
        return new Response(JSON.stringify({ dataPoints: [] }));
      }
      if (url.includes("/sleep/dataPoints?")) {
        return new Response(
          JSON.stringify({
            dataPoints: [
              {
                sleep: {
                  interval: {
                    startTime: "2026-08-26T22:30:00Z",
                    endTime: "2026-08-27T05:33:00Z",
                  },
                  type: "STAGES",
                  metadata: { processed: true, nap: false, stagesStatus: "SUCCEEDED" },
                  summary: {
                    minutesAsleep: "393",
                    minutesInSleepPeriod: "423",
                    minutesAwake: "30",
                  },
                  stages: [
                    {
                      startTime: "2026-08-26T22:30:00Z",
                      endTime: "2026-08-27T05:03:00Z",
                      type: "LIGHT",
                    },
                    {
                      startTime: "2026-08-27T05:03:00Z",
                      endTime: "2026-08-27T05:33:00Z",
                      type: "AWAKE",
                    },
                  ],
                },
              },
            ],
          }),
        );
      }
      if (url.includes("/daily-vo2-max/dataPoints:reconcile?")) {
        return new Response(
          JSON.stringify({
            dataPoints: [
              {
                dailyVo2Max: {
                  date: { year: 2026, month: 8, day: 20 },
                  vo2Max: 41.7,
                  cardioFitnessLevel: "GOOD",
                },
              },
            ],
          }),
        );
      }
      return new Response(JSON.stringify({}));
    });

    const day = await fetchFitbitDay("2026-08-27", "token", false);

    expect(day.sleepMinutes).toBe(393);
    expect(day.availability?.steps).toBe(false);
    expect(day.availability?.distanceKm).toBe(false);
    expect(day.sleepStages).toHaveLength(2);
    expect(day.sleepDetails?.minutesAwake).toBe(30);
    expect(day.vo2Max).toMatchObject({
      value: 41.7,
      measuredDate: "2026-08-20",
      cardioFitnessLevel: "GOOD",
    });
    expect(
      fetchMock.mock.calls.some(([input]) =>
        String(input).includes("/sleep/dataPoints?"),
      ),
    ).toBe(true);
    const rawSleepUrl = String(
      fetchMock.mock.calls.find(([input]) =>
        String(input).includes("/sleep/dataPoints?"),
      )?.[0],
    );
    expect(rawSleepUrl).not.toContain("dataSourceFamily");
    const rawSleepFilter = new URL(rawSleepUrl).searchParams.get("filter") ?? "";
    expect(rawSleepFilter).toContain(
      'sleep.interval.end_time >= "2026-08-13T22:00:00.000Z"',
    );
    expect(rawSleepFilter).not.toContain(
      "sleep.interval.civil_end_time",
    );
  });
});
