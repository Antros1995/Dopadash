import type { EncryptedValue } from "../outlook/types";

export interface FitbitDaySnapshot {
  schemaVersion: 7;
  availability?: Record<string, boolean>;
  source?: "fitbit";
  date: string;
  finalized: boolean;
  syncedAt: string;
  steps: number;
  distanceKm: number;
  calories: number;
  activeMinutes: number;
  sedentaryMinutes: number | null;
  mindfulnessMinutes: number | null;
  activeZoneMinutes: number | null;
  activeZoneMinutesByZone: {
    fatBurn: number;
    cardio: number;
    peak: number;
  } | null;
  restingHeartRate: number | null;
  latestHeartRate?: {
    measuredAt: string;
    beatsPerMinute: number;
  } | null;
  sleepMinutes: number | null;
  sleepEfficiency: number | null;
  sleepDetails: {
    startTime: string | null;
    endTime: string | null;
    type: string | null;
    processed: boolean | null;
    stagesStatus: string | null;
    minutesInSleepPeriod: number;
    minutesAwake: number;
    minutesToFallAsleep: number;
    minutesAfterWakeUp: number;
    stageMinutes: {
      awake: number;
      light: number;
      deep: number;
      rem: number;
      asleep: number;
      restless: number;
    };
    shortAwakenings: Array<{
      startTime: string;
      endTime: string;
    }>;
  } | null;
  oxygenSaturation: {
    average: number;
    minimum: number | null;
    maximum: number | null;
  } | null;
  heartRateVariabilityMs: number | null;
  respiratoryRate: number | null;
  skinTemperature: {
    nightlyCelsius: number;
    baselineCelsius: number | null;
  } | null;
  vo2Max: {
    value: number;
    measuredDate: string;
    cardioFitnessLevel: string | null;
    estimated: boolean;
  } | null;
  workouts: Array<{
    type: string;
    name: string | null;
    startTime: string;
    activeMinutes: number;
    calories: number | null;
    distanceKm: number | null;
    averageHeartRate: number | null;
  }>;
  heartProfile: Array<{
    startTime: string;
    average: number;
    minimum: number;
    maximum: number;
  }>;
  sleepStages: Array<{
    startTime: string;
    endTime: string;
    type: string;
  }>;
  trends: {
    steps: number[];
    distanceKm: number[];
    calories: number[];
    activeMinutes: number[];
    sedentaryMinutes: number[];
    activeZoneMinutes: number[];
    restingHeartRate: number[];
    sleepMinutes: number[];
    oxygenSaturation: number[];
    heartRateVariabilityMs: number[];
    respiratoryRate: number[];
    skinTemperature: number[];
    vo2Max: number[];
  };
}

export interface FitbitConnectionState {
  status: "DISCONNECTED" | "PENDING" | "CONNECTED";
  oauthState: string | null;
  pkceVerifier: EncryptedValue | null;
  oauthExpiresAt: string | null;
  accessToken: EncryptedValue | null;
  refreshToken: EncryptedValue | null;
  accessTokenExpiresAt: string | null;
  connectedAt: string | null;
  fitbitUserId: string | null;
  deviceName: string | null;
  syncScheduleId: string | null;
  days: Record<string, FitbitDaySnapshot>;
}

export interface FitbitTokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  scope: string;
}

export interface FitbitView {
  configured: boolean;
  connection: "DISCONNECTED" | "PENDING" | "CONNECTED";
  deviceName: string | null;
  day: FitbitDaySnapshot | null;
}
