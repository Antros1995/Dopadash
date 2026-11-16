import type { FitbitDaySnapshot } from "./types";

interface DailyRollupResponse {
  rollupDataPoints?: Array<{
    civilStartTime?: { date?: CivilDate };
    civilEndTime?: { date?: CivilDate };
    steps?: { countSum?: string };
    distance?: { millimetersSum?: string };
    totalCalories?: { kcalSum?: number };
    activeMinutes?: {
      activeMinutesRollupByActivityLevel?: Array<{
        activityLevel?: string;
        activeMinutesSum?: string;
      }>;
    };
    activeZoneMinutes?: {
      sumInCardioHeartZone?: string;
      sumInPeakHeartZone?: string;
      sumInFatBurnHeartZone?: string;
    };
    sedentaryPeriod?: { durationSum?: string };
  }>;
}

interface ListDataPointsResponse {
  dataPoints?: Array<{
    dailyRestingHeartRate?: {
      date?: { year?: number; month?: number; day?: number };
      beatsPerMinute?: string;
    };
    sleep?: {
      interval?: {
        startTime?: string;
        endTime?: string;
        civilEndTime?: { date?: { year?: number; month?: number; day?: number } };
      };
      type?: string;
      summary?: {
        minutesInSleepPeriod?: string;
        minutesAfterWakeUp?: string;
        minutesToFallAsleep?: string;
        minutesAsleep?: string;
        minutesAwake?: string;
        stagesSummary?: Array<{ type?: string; minutes?: string; count?: string }>;
      };
      sleepStages?: SleepStage[];
      stages?: SleepStage[];
      shortAwakenings?: SleepStage[];
      outOfBedSegments?: Array<{ startTime?: string; endTime?: string }>;
      metadata?: {
        main?: boolean;
        processed?: boolean;
        nap?: boolean;
        stagesStatus?: string;
      };
    };
    dailyOxygenSaturation?: {
      date?: CivilDate;
      averagePercentage?: number;
      lowerBoundPercentage?: number;
      upperBoundPercentage?: number;
    };
    dailyHeartRateVariability?: {
      date?: CivilDate;
      averageHeartRateVariabilityMilliseconds?: number;
    };
    dailyRespiratoryRate?: {
      date?: CivilDate;
      breathsPerMinute?: number;
    };
    dailySleepTemperatureDerivations?: {
      date?: CivilDate;
      nightlyTemperatureCelsius?: number;
      baselineTemperatureCelsius?: number;
    };
    dailyVo2Max?: {
      date?: CivilDate;
      estimated?: boolean;
      cardioFitnessLevel?: string;
      vo2Max?: number;
    };
    exercise?: {
      interval?: {
        startTime?: string;
        endTime?: string;
        civilStartTime?: { date?: CivilDate };
      };
      exerciseType?: string;
      displayName?: string;
      activeDuration?: string;
      metricsSummary?: {
        caloriesKcal?: number;
        distanceMillimeters?: number;
        averageHeartRateBeatsPerMinute?: string;
      };
    };
  }>;
}

interface CivilDate {
  year?: number;
  month?: number;
  day?: number;
}

interface SleepStage {
  startTime?: string;
  endTime?: string;
  type?: string;
}

interface HeartRateRollupResponse {
  rollupDataPoints?: Array<{
    startTime?: string;
    endTime?: string;
    heartRate?: {
      beatsPerMinuteAvg?: number;
      beatsPerMinuteMin?: number;
      beatsPerMinuteMax?: number;
    };
  }>;
}

interface HeartRateSampleResponse {
  dataPoints?: Array<{
    heartRate?: {
      sampleTime?: { physicalTime?: string };
      beatsPerMinute?: string | number;
    };
  }>;
  nextPageToken?: string;
}

interface PairedDevicesResponse {
  pairedDevices?: Array<{ deviceType?: string; deviceVersion?: string }>;
}

async function healthRequest<T>(
  path: string,
  accessToken: string,
  init?: RequestInit,
): Promise<T> {
  const response = await fetch(`https://health.googleapis.com${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${accessToken}`,
      accept: "application/json",
      ...(init?.body ? { "content-type": "application/json" } : {}),
      ...init?.headers,
    },
  });
  if (!response.ok) {
    throw new Error(`Google Health API request failed with status ${response.status}`);
  }
  return response.json<T>();
}

function dateParts(date: string): { year: number; month: number; day: number } {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/u.exec(date);
  if (!match) throw new Error("Invalid Google Health date");
  return { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) };
}

function nextDate(parts: { year: number; month: number; day: number }) {
  const next = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + 1));
  return {
    year: next.getUTCFullYear(),
    month: next.getUTCMonth() + 1,
    day: next.getUTCDate(),
  };
}

function civilDateTime(date: { year: number; month: number; day: number }) {
  return { date, time: { hours: 0, minutes: 0, seconds: 0, nanos: 0 } };
}

async function dailyRollup(
  dataType: string,
  date: string,
  accessToken: string,
): Promise<DailyRollupResponse> {
  const endDay = dateParts(date);
  const startDate = new Date(Date.UTC(endDay.year, endDay.month - 1, endDay.day - 13));
  const start = {
    year: startDate.getUTCFullYear(),
    month: startDate.getUTCMonth() + 1,
    day: startDate.getUTCDate(),
  };
  return healthRequest<DailyRollupResponse>(
    `/v4/users/me/dataTypes/${dataType}/dataPoints:dailyRollUp`,
    accessToken,
    {
      method: "POST",
      body: JSON.stringify({
        range: {
          start: civilDateTime(start),
          end: civilDateTime(nextDate(endDay)),
        },
        windowSizeDays: 1,
        dataSourceFamily: "users/me/dataSourceFamilies/google-wearables",
      }),
    },
  );
}

function rollupForDate(response: DailyRollupResponse, date: string) {
  const points = response.rollupDataPoints ?? [];
  return (
    points.find((point) => dateKey(point.civilStartTime?.date) === date) ??
    (points.length === 1 ? (points[0] ?? {}) : {})
  );
}

function orderedRollups(response: DailyRollupResponse) {
  return [...(response.rollupDataPoints ?? [])].sort(
    (left, right) =>
      dateNumber(left.civilStartTime?.date) - dateNumber(right.civilStartTime?.date),
  );
}

function intValue(value: string | number | undefined): number {
  const parsed = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : 0;
}

function durationMinutes(value?: string): number {
  const seconds = Number(value?.replace(/s$/u, "") ?? 0);
  return Number.isFinite(seconds) ? Math.max(0, Math.round(seconds / 60)) : 0;
}

export async function fetchFitbitDevice(accessToken: string): Promise<string | null> {
  const response = await healthRequest<PairedDevicesResponse>(
    "/v4/users/me/pairedDevices?pageSize=10",
    accessToken,
  );
  const tracker =
    response.pairedDevices?.find((device) => device.deviceType === "TRACKER") ??
    response.pairedDevices?.[0];
  return tracker?.deviceVersion?.slice(0, 100) ?? null;
}

async function fetchDailyRestingHeartRate(date: string, accessToken: string) {
  const response = await healthRequest<ListDataPointsResponse>(
    "/v4/users/me/dataTypes/daily-resting-heart-rate/dataPoints:reconcile?" +
      new URLSearchParams({
        pageSize: "90",
        dataSourceFamily: "users/me/dataSourceFamilies/all-sources",
      }).toString(),
    accessToken,
  );
  const expected = dateParts(date);
  const point = response.dataPoints?.find((item) => {
    const value = item.dailyRestingHeartRate?.date;
    return value?.year === expected.year && value.month === expected.month && value.day === expected.day;
  });
  const raw = point?.dailyRestingHeartRate?.beatsPerMinute;
  const trend = (response.dataPoints ?? [])
    .filter((item) => item.dailyRestingHeartRate?.beatsPerMinute != null)
    .sort((left, right) => {
      const leftDate = left.dailyRestingHeartRate?.date;
      const rightDate = right.dailyRestingHeartRate?.date;
      return dateNumber(leftDate) - dateNumber(rightDate);
    })
    .slice(-14)
    .map((item) => intValue(item.dailyRestingHeartRate?.beatsPerMinute));
  return { current: raw == null ? null : intValue(raw), trend };
}

function dateNumber(value?: { year?: number; month?: number; day?: number }): number {
  return (value?.year ?? 0) * 10_000 + (value?.month ?? 0) * 100 + (value?.day ?? 0);
}

function dateKey(value?: { year?: number; month?: number; day?: number }): string | null {
  if (!value?.year || !value.month || !value.day) return null;
  return `${value.year.toString().padStart(4, "0")}-${value.month
    .toString()
    .padStart(2, "0")}-${value.day.toString().padStart(2, "0")}`;
}

function romeDateKeyFromTimestamp(value?: string): string | null {
  if (!value) return null;
  const timestamp = new Date(value);
  if (Number.isNaN(timestamp.getTime())) return null;
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-GB", {
      timeZone: "Europe/Rome",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    })
      .formatToParts(timestamp)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function sleepDateKey(
  point: NonNullable<ListDataPointsResponse["dataPoints"]>[number],
): string | null {
  return (
    dateKey(point.sleep?.interval?.civilEndTime?.date) ??
    romeDateKeyFromTimestamp(point.sleep?.interval?.endTime)
  );
}

function shiftDate(date: string, days: number): string {
  const parts = dateParts(date);
  const shifted = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + days));
  return `${shifted.getUTCFullYear().toString().padStart(4, "0")}-${(shifted.getUTCMonth() + 1)
    .toString()
    .padStart(2, "0")}-${shifted.getUTCDate().toString().padStart(2, "0")}`;
}

async function fetchSleep(date: string, accessToken: string) {
  const from = shiftDate(date, -13);
  const to = shiftDate(date, 1);
  const filter =
    `sleep.interval.civil_end_time >= "${from}" AND sleep.interval.civil_end_time < "${to}"`;
  const query = new URLSearchParams({
    filter,
    pageSize: "25",
    dataSourceFamily: "users/me/dataSourceFamilies/all-sources",
  });
  let points: NonNullable<ListDataPointsResponse["dataPoints"]> = [];
  try {
    const response = await healthRequest<ListDataPointsResponse>(
      `/v4/users/me/dataTypes/sleep/dataPoints:reconcile?${query.toString()}`,
      accessToken,
    );
    points = response.dataPoints ?? [];
  } catch (error) {
    console.warn("Reconciled sleep unavailable; using the raw Fitbit session", {
      date,
      message: error instanceof Error ? error.message.slice(0, 120) : "unknown",
    });
  }
  const primarySleep = (candidates: NonNullable<ListDataPointsResponse["dataPoints"]>) =>
    [...candidates].sort(
      (left, right) =>
        Number(right.sleep?.metadata?.main === true) -
          Number(left.sleep?.metadata?.main === true) ||
        Number(left.sleep?.metadata?.nap === true) -
          Number(right.sleep?.metadata?.nap === true) ||
        Number((right.sleep?.stages?.length ?? right.sleep?.sleepStages?.length ?? 0) > 0) -
          Number((left.sleep?.stages?.length ?? left.sleep?.sleepStages?.length ?? 0) > 0) ||
        intValue(right.sleep?.summary?.minutesInSleepPeriod) -
          intValue(left.sleep?.summary?.minutesInSleepPeriod),
    )[0];
  const selected = points.filter(
    (point) => sleepDateKey(point) === date,
  );
  let mainPoint = primarySleep(selected);
  const reconciledStages =
    mainPoint?.sleep?.stages ?? mainPoint?.sleep?.sleepStages ?? [];
  if (!mainPoint || reconciledStages.length === 0) {
    // Raw Fitbit sessions do not always contain civilEndTime. Filtering the raw
    // endpoint by that optional output field can make an otherwise valid sleep
    // disappear before we get a chance to derive its Rome calendar day from
    // interval.endTime.
    const rawFilter =
      `sleep.interval.end_time >= "${romeMidnightUtc(from).toISOString()}" ` +
      `AND sleep.interval.end_time < "${romeMidnightUtc(to).toISOString()}"`;
    const rawQuery = new URLSearchParams({ filter: rawFilter, pageSize: "25" });
    const rawResponse = await healthRequest<ListDataPointsResponse>(
      `/v4/users/me/dataTypes/sleep/dataPoints?${rawQuery.toString()}`,
      accessToken,
    );
    const rawPoints = rawResponse.dataPoints ?? [];
    const rawSelected = rawPoints.filter(
      (point) => sleepDateKey(point) === date,
    );
    const rawMainPoint = primarySleep(rawSelected);
    const rawStages = rawMainPoint?.sleep?.stages ?? rawMainPoint?.sleep?.sleepStages ?? [];
    if (!mainPoint || rawStages.length > reconciledStages.length) {
      mainPoint = rawMainPoint ?? mainPoint;
    }
    if (points.length === 0) points = rawPoints;
  }
  const byDate = new Map<string, NonNullable<ListDataPointsResponse["dataPoints"]>>();
  for (const point of points) {
    const key = sleepDateKey(point);
    if (!key || point.sleep?.summary?.minutesAsleep == null) continue;
    const values = byDate.get(key) ?? [];
    values.push(point);
    byDate.set(key, values);
  }
  const trend = [...byDate.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([, values]) => intValue(primarySleep(values)?.sleep?.summary?.minutesAsleep))
    .slice(-14);
  const main = mainPoint?.sleep?.summary;
  const stages = (mainPoint?.sleep?.sleepStages ?? mainPoint?.sleep?.stages ?? [])
    .filter(
      (stage): stage is Required<Pick<SleepStage, "startTime" | "endTime" | "type">> =>
        typeof stage.startTime === "string" &&
        typeof stage.endTime === "string" &&
        typeof stage.type === "string" &&
        Number.isFinite(Date.parse(stage.startTime)) &&
        Number.isFinite(Date.parse(stage.endTime)) &&
        Date.parse(stage.endTime) > Date.parse(stage.startTime),
    )
    .map((stage) => ({
      startTime: stage.startTime,
      endTime: stage.endTime,
      type: stage.type.toUpperCase(),
    }))
    .sort((left, right) => left.startTime.localeCompare(right.startTime));
  const shortAwakenings = [
    ...(mainPoint?.sleep?.shortAwakenings ?? []),
    ...(mainPoint?.sleep?.outOfBedSegments ?? []),
  ]
    .filter(
      (segment): segment is Required<Pick<SleepStage, "startTime" | "endTime">> =>
        typeof segment.startTime === "string" && typeof segment.endTime === "string",
    )
    .map((segment) => ({ startTime: segment.startTime, endTime: segment.endTime }))
    .sort((left, right) => left.startTime.localeCompare(right.startTime));
  if (!main) {
    return { minutes: null, efficiency: null, trend, stages, details: null };
  }
  const minutes = intValue(main.minutesAsleep);
  const inPeriod = intValue(main.minutesInSleepPeriod);
  const stageMinutes = {
    awake: 0,
    light: 0,
    deep: 0,
    rem: 0,
    asleep: 0,
    restless: 0,
  };
  for (const summary of main.stagesSummary ?? []) {
    const key = summary.type?.toLowerCase();
    if (key && key in stageMinutes) {
      stageMinutes[key as keyof typeof stageMinutes] = intValue(summary.minutes);
    }
  }
  if (Object.values(stageMinutes).every((value) => value === 0)) {
    for (const stage of stages) {
      const key = stage.type.toLowerCase();
      if (!(key in stageMinutes)) continue;
      const duration = Math.max(
        0,
        Math.round((Date.parse(stage.endTime) - Date.parse(stage.startTime)) / 60_000),
      );
      stageMinutes[key as keyof typeof stageMinutes] += duration;
    }
  }
  return {
    minutes,
    efficiency: inPeriod > 0 ? Math.round((minutes / inPeriod) * 100) : null,
    trend,
    stages,
    details: {
      startTime: mainPoint?.sleep?.interval?.startTime ?? null,
      endTime: mainPoint?.sleep?.interval?.endTime ?? null,
      type: mainPoint?.sleep?.type ?? null,
      processed: mainPoint?.sleep?.metadata?.processed ?? null,
      stagesStatus: mainPoint?.sleep?.metadata?.stagesStatus ?? null,
      minutesInSleepPeriod: inPeriod,
      minutesAwake:
        main.minutesAwake == null ? stageMinutes.awake : intValue(main.minutesAwake),
      minutesToFallAsleep: intValue(main.minutesToFallAsleep),
      minutesAfterWakeUp: intValue(main.minutesAfterWakeUp),
      stageMinutes,
      shortAwakenings,
    },
  };
}

async function fetchDailyVitals(date: string, accessToken: string) {
  const types = [
    "daily-oxygen-saturation",
    "daily-heart-rate-variability",
    "daily-respiratory-rate",
    "daily-sleep-temperature-derivations",
    "daily-vo2-max",
  ] as const;
  const responses = await Promise.allSettled(
    types.map((type) =>
      healthRequest<ListDataPointsResponse>(
        `/v4/users/me/dataTypes/${type}/dataPoints:reconcile?${new URLSearchParams({
          pageSize: "90",
          dataSourceFamily: "users/me/dataSourceFamilies/all-sources",
        }).toString()}`,
        accessToken,
      ),
    ),
  );
  const responseAt = (index: number): ListDataPointsResponse => {
    const response = responses[index];
    return response?.status === "fulfilled" ? response.value : {};
  };
  const oxygenPoints = responseAt(0).dataPoints ?? [];
  const hrvPoints = responseAt(1).dataPoints ?? [];
  const respiratoryPoints = responseAt(2).dataPoints ?? [];
  const temperaturePoints = responseAt(3).dataPoints ?? [];
  const vo2Points = responseAt(4).dataPoints ?? [];
  const oxygen = oxygenPoints.find(
    (point) => dateKey(point.dailyOxygenSaturation?.date) === date,
  )?.dailyOxygenSaturation;
  const hrv = hrvPoints.find(
    (point) => dateKey(point.dailyHeartRateVariability?.date) === date,
  )?.dailyHeartRateVariability;
  const respiratory = respiratoryPoints.find(
    (point) => dateKey(point.dailyRespiratoryRate?.date) === date,
  )?.dailyRespiratoryRate;
  const temperature = temperaturePoints.find(
    (point) => dateKey(point.dailySleepTemperatureDerivations?.date) === date,
  )?.dailySleepTemperatureDerivations;
  const vo2 = [...vo2Points]
    .filter((point) => {
      const key = dateKey(point.dailyVo2Max?.date);
      return key != null && key <= date && point.dailyVo2Max?.vo2Max != null;
    })
    .sort(
      (left, right) =>
        dateNumber(right.dailyVo2Max?.date) - dateNumber(left.dailyVo2Max?.date),
    )[0]?.dailyVo2Max;
  const trend = <T>(
    points: ListDataPointsResponse["dataPoints"],
    dateOf: (point: NonNullable<ListDataPointsResponse["dataPoints"]>[number]) => CivilDate | undefined,
    valueOf: (point: NonNullable<ListDataPointsResponse["dataPoints"]>[number]) => T | undefined,
  ): T[] =>
    [...(points ?? [])]
      .sort((left, right) => dateNumber(dateOf(left)) - dateNumber(dateOf(right)))
      .map(valueOf)
      .filter((value): value is T => value != null)
      .slice(-14);
  return {
    oxygen:
      oxygen?.averagePercentage == null
        ? null
        : {
            average: oxygen.averagePercentage,
            minimum: oxygen.lowerBoundPercentage ?? null,
            maximum: oxygen.upperBoundPercentage ?? null,
          },
    hrv: hrv?.averageHeartRateVariabilityMilliseconds ?? null,
    respiratoryRate: respiratory?.breathsPerMinute ?? null,
    temperature:
      temperature?.nightlyTemperatureCelsius == null
        ? null
        : {
            nightlyCelsius: temperature.nightlyTemperatureCelsius,
            baselineCelsius: temperature.baselineTemperatureCelsius ?? null,
          },
    vo2Max:
      vo2?.vo2Max == null
        ? null
        : {
            value: vo2.vo2Max,
            measuredDate: dateKey(vo2.date) ?? date,
            cardioFitnessLevel: vo2.cardioFitnessLevel ?? null,
            estimated: vo2.estimated ?? false,
          },
    oxygenTrend: trend(
      oxygenPoints,
      (point) => point.dailyOxygenSaturation?.date,
      (point) => point.dailyOxygenSaturation?.averagePercentage,
    ),
    hrvTrend: trend(
      hrvPoints,
      (point) => point.dailyHeartRateVariability?.date,
      (point) => point.dailyHeartRateVariability?.averageHeartRateVariabilityMilliseconds,
    ),
    respiratoryTrend: trend(
      respiratoryPoints,
      (point) => point.dailyRespiratoryRate?.date,
      (point) => point.dailyRespiratoryRate?.breathsPerMinute,
    ),
    temperatureTrend: trend(
      temperaturePoints,
      (point) => point.dailySleepTemperatureDerivations?.date,
      (point) => point.dailySleepTemperatureDerivations?.nightlyTemperatureCelsius,
    ),
    vo2MaxTrend: trend(
      vo2Points,
      (point) => point.dailyVo2Max?.date,
      (point) => point.dailyVo2Max?.vo2Max,
    ),
  };
}

function romeMidnightUtc(date: string): Date {
  const expected = dateParts(date);
  const desired = Date.UTC(expected.year, expected.month - 1, expected.day);
  let guess = desired;
  const formatter = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Rome",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  for (let pass = 0; pass < 2; pass += 1) {
    const parts = Object.fromEntries(
      formatter
        .formatToParts(new Date(guess))
        .filter((part) => part.type !== "literal")
        .map((part) => [part.type, Number(part.value)]),
    );
    const displayed = Date.UTC(
      parts.year ?? 0,
      (parts.month ?? 1) - 1,
      parts.day ?? 1,
      parts.hour ?? 0,
      parts.minute ?? 0,
      parts.second ?? 0,
    );
    guess -= displayed - desired;
  }
  return new Date(guess);
}

async function fetchHeartProfile(date: string, accessToken: string) {
  const response = await healthRequest<HeartRateRollupResponse>(
    "/v4/users/me/dataTypes/heart-rate/dataPoints:rollUp",
    accessToken,
    {
      method: "POST",
      body: JSON.stringify({
        range: {
          startTime: romeMidnightUtc(date).toISOString(),
          endTime: romeMidnightUtc(shiftDate(date, 1)).toISOString(),
        },
        windowSize: "1800s",
        dataSourceFamily: "users/me/dataSourceFamilies/google-wearables",
        pageSize: 100,
      }),
    },
  );
  return (response.rollupDataPoints ?? [])
    .filter(
      (point) =>
        typeof point.startTime === "string" &&
        point.heartRate?.beatsPerMinuteAvg != null,
    )
    .map((point) => ({
      startTime: point.startTime!,
      average: point.heartRate!.beatsPerMinuteAvg!,
      minimum:
        point.heartRate!.beatsPerMinuteMin ?? point.heartRate!.beatsPerMinuteAvg!,
      maximum:
        point.heartRate!.beatsPerMinuteMax ?? point.heartRate!.beatsPerMinuteAvg!,
    }))
    .sort((left, right) => left.startTime.localeCompare(right.startTime));
}

async function fetchLatestHeartRate(
  intervalStart: string,
  accessToken: string,
): Promise<NonNullable<FitbitDaySnapshot["latestHeartRate"]> | null> {
  const start = Date.parse(intervalStart);
  const end = start + 30 * 60_000;
  const field = "heart_rate.sample_time.physical_time";
  const query = new URLSearchParams({
    filter: `${field} >= "${intervalStart}" AND ${field} < "${new Date(end).toISOString()}"`,
    dataSourceFamily: "users/me/dataSourceFamilies/google-wearables",
    pageSize: "2000",
  });
  let latest: NonNullable<FitbitDaySnapshot["latestHeartRate"]> | null = null;
  let latestTime = -Infinity;
  let pageToken: string | undefined;
  do {
    if (pageToken) query.set("pageToken", pageToken);
    const response = await healthRequest<HeartRateSampleResponse>(
      `/v4/users/me/dataTypes/heart-rate/dataPoints:reconcile?${query}`,
      accessToken,
    );
    for (const { heartRate } of response.dataPoints ?? []) {
      const measuredAt = heartRate?.sampleTime?.physicalTime;
      const beatsPerMinute = Number(heartRate?.beatsPerMinute);
      const time = measuredAt ? Date.parse(measuredAt) : NaN;
      if (
        measuredAt && time >= start && time < end && time > latestTime &&
        Number.isInteger(beatsPerMinute) && beatsPerMinute > 0
      ) {
        latest = { measuredAt, beatsPerMinute };
        latestTime = time;
      }
    }
    pageToken = response.nextPageToken;
  } while (pageToken);
  return latest;
}

async function fetchWorkouts(date: string, accessToken: string) {
  const filter =
    `exercise.interval.civil_start_time >= "${date}" AND ` +
    `exercise.interval.civil_start_time < "${shiftDate(date, 1)}"`;
  const response = await healthRequest<ListDataPointsResponse>(
    `/v4/users/me/dataTypes/exercise/dataPoints:reconcile?${new URLSearchParams({
      filter,
      pageSize: "25",
      dataSourceFamily: "users/me/dataSourceFamilies/all-sources",
    }).toString()}`,
    accessToken,
  );
  return (response.dataPoints ?? [])
    .map((point) => point.exercise)
    .filter(
      (exercise): exercise is NonNullable<typeof exercise> & {
        interval: { startTime: string };
      } =>
        exercise?.interval?.startTime != null &&
        (dateKey(exercise.interval.civilStartTime?.date) ??
          romeDateKeyFromTimestamp(exercise.interval.startTime)) === date,
    )
    .map((exercise) => ({
      type: exercise.exerciseType ?? "OTHER",
      name: exercise.displayName?.slice(0, 100) ?? null,
      startTime: exercise.interval.startTime,
      activeMinutes: durationMinutes(exercise.activeDuration),
      calories:
        exercise.metricsSummary?.caloriesKcal == null
          ? null
          : Math.max(0, Math.round(exercise.metricsSummary.caloriesKcal)),
      distanceKm:
        exercise.metricsSummary?.distanceMillimeters == null
          ? null
          : Math.max(0, exercise.metricsSummary.distanceMillimeters / 1_000_000),
      averageHeartRate:
        exercise.metricsSummary?.averageHeartRateBeatsPerMinute == null
          ? null
          : intValue(exercise.metricsSummary.averageHeartRateBeatsPerMinute),
    }))
    .sort((left, right) => left.startTime.localeCompare(right.startTime));
}

export async function fetchFitbitDay(
  date: string,
  accessToken: string,
  finalized: boolean,
  now = new Date(),
): Promise<FitbitDaySnapshot> {
  const results = await Promise.allSettled([
    dailyRollup("steps", date, accessToken),
    dailyRollup("distance", date, accessToken),
    dailyRollup("total-calories", date, accessToken),
    dailyRollup("active-minutes", date, accessToken),
    dailyRollup("active-zone-minutes", date, accessToken),
    dailyRollup("sedentary-period", date, accessToken),
    fetchDailyRestingHeartRate(date, accessToken),
    fetchSleep(date, accessToken),
    fetchDailyVitals(date, accessToken),
    fetchHeartProfile(date, accessToken),
    fetchWorkouts(date, accessToken),
  ] as const);
  const value = <T>(result: PromiseSettledResult<T>, fallback: T): T =>
    result.status === "fulfilled" ? result.value : fallback;
  const stepsResponse = value(results[0], {});
  const distanceResponse = value(results[1], {});
  const caloriesResponse = value(results[2], {});
  const activeResponse = value(results[3], {});
  const activeZoneResponse = value(results[4], {});
  const sedentaryResponse = value(results[5], {});
  const heart = value(results[6], { current: null, trend: [] });
  const sleep = value(results[7], {
    minutes: null,
    efficiency: null,
    trend: [],
    stages: [],
    details: null,
  });
  const vitals = value(results[8], {
    oxygen: null,
    hrv: null,
    respiratoryRate: null,
    temperature: null,
    vo2Max: null,
    oxygenTrend: [],
    hrvTrend: [],
    respiratoryTrend: [],
    temperatureTrend: [],
    vo2MaxTrend: [],
  });
  const heartProfile = value(results[9], []);
  const workouts = value(results[10], []);

  const failedMetrics = results.filter((result) => result.status === "rejected").length;
  const coreResults = results.filter((_, index) => index !== 8);
  if (coreResults.every((result) => result.status === "rejected")) {
    const unauthorized = coreResults.find(
      (result) => result.status === "rejected" &&
        result.reason instanceof Error &&
        /status 401\b/u.test(result.reason.message),
    );
    const failure = unauthorized ?? coreResults[0];
    if (failure?.status === "rejected") throw failure.reason;
  }
  if (failedMetrics > 0) {
    console.warn("Google Health returned partial daily data", {
      date,
      failedMetrics,
      statuses: results.flatMap((result) =>
        result.status === "rejected" && result.reason instanceof Error
          ? [/status (\d+)/u.exec(result.reason.message)?.[1] ?? "network"]
          : [],
      ),
    });
  }
  // The most recent rollup bounds the raw query to one 30-minute interval.
  const latestInterval = heartProfile.at(-1);
  const latestHeartRate = !finalized && latestInterval
    ? await fetchLatestHeartRate(latestInterval.startTime, accessToken).catch((error: unknown) => {
        console.warn("Google Health heart rate sample unavailable", {
          status: error instanceof Error ? /status (\d+)\b/u.exec(error.message)?.[1] : undefined,
        });
        return null;
      })
    : null;
  const activeLevels =
    rollupForDate(activeResponse, date).activeMinutes?.activeMinutesRollupByActivityLevel ?? [];
  const activeMinutes = activeLevels
    .filter((value) => value.activityLevel === "MODERATE" || value.activityLevel === "VIGOROUS")
    .reduce((sum, value) => sum + intValue(value.activeMinutesSum), 0);
  const activeZoneRollup = rollupForDate(activeZoneResponse, date).activeZoneMinutes;
  const activeZoneBreakdown = activeZoneRollup
    ? {
        fatBurn: intValue(activeZoneRollup.sumInFatBurnHeartZone),
        cardio: intValue(activeZoneRollup.sumInCardioHeartZone),
        peak: intValue(activeZoneRollup.sumInPeakHeartZone),
      }
    : null;
  const activeZoneMinutes = activeZoneBreakdown
    ? activeZoneBreakdown.fatBurn + activeZoneBreakdown.cardio + activeZoneBreakdown.peak
    : null;
  return {
    schemaVersion: 7,
    source: "fitbit",
    date,
    availability: {
      steps: rollupForDate(stepsResponse, date).steps?.countSum != null,
      distanceKm: rollupForDate(distanceResponse, date).distance?.millimetersSum != null,
      activeMinutes: rollupForDate(activeResponse, date).activeMinutes != null,
      calories: rollupForDate(caloriesResponse, date).totalCalories?.kcalSum != null,
    },
    finalized,
    syncedAt: now.toISOString(),
    steps: intValue(rollupForDate(stepsResponse, date).steps?.countSum),
    distanceKm:
      intValue(rollupForDate(distanceResponse, date).distance?.millimetersSum) / 1_000_000,
    calories: intValue(rollupForDate(caloriesResponse, date).totalCalories?.kcalSum),
    activeMinutes,
    sedentaryMinutes:
      rollupForDate(sedentaryResponse, date).sedentaryPeriod?.durationSum == null
        ? null
        : durationMinutes(
            rollupForDate(sedentaryResponse, date).sedentaryPeriod?.durationSum,
          ),
    mindfulnessMinutes: null,
    activeZoneMinutes,
    activeZoneMinutesByZone: activeZoneBreakdown,
    restingHeartRate: heart.current,
    latestHeartRate,
    sleepMinutes: sleep.minutes,
    sleepEfficiency: sleep.efficiency,
    sleepDetails: sleep.details,
    oxygenSaturation: vitals.oxygen,
    heartRateVariabilityMs: vitals.hrv,
    respiratoryRate: vitals.respiratoryRate,
    skinTemperature: vitals.temperature,
    vo2Max: vitals.vo2Max,
    workouts,
    heartProfile,
    sleepStages: sleep.stages,
    trends: {
      steps: orderedRollups(stepsResponse).map((point) =>
        intValue(point.steps?.countSum),
      ),
      distanceKm: orderedRollups(distanceResponse).map(
        (point) => intValue(point.distance?.millimetersSum) / 1_000_000,
      ),
      calories: orderedRollups(caloriesResponse).map((point) =>
        intValue(point.totalCalories?.kcalSum),
      ),
      activeMinutes: orderedRollups(activeResponse).map((point) =>
        (point.activeMinutes?.activeMinutesRollupByActivityLevel ?? [])
          .filter(
            (item) => item.activityLevel === "MODERATE" || item.activityLevel === "VIGOROUS",
          )
          .reduce((sum, item) => sum + intValue(item.activeMinutesSum), 0),
      ),
      sedentaryMinutes: orderedRollups(sedentaryResponse).map((point) =>
        durationMinutes(point.sedentaryPeriod?.durationSum),
      ),
      activeZoneMinutes: orderedRollups(activeZoneResponse).map((point) => {
        const rollup = point.activeZoneMinutes;
        return (
          intValue(rollup?.sumInFatBurnHeartZone) +
          intValue(rollup?.sumInCardioHeartZone) +
          intValue(rollup?.sumInPeakHeartZone)
        );
      }),
      restingHeartRate: heart.trend,
      sleepMinutes: sleep.trend,
      oxygenSaturation: vitals.oxygenTrend,
      heartRateVariabilityMs: vitals.hrvTrend,
      respiratoryRate: vitals.respiratoryTrend,
      skinTemperature: vitals.temperatureTrend,
      vo2Max: vitals.vo2MaxTrend,
    },
  };
}
