import type { FitbitDaySnapshot } from "./types";

export function savedFitbitHistory(days: Record<string, FitbitDaySnapshot>): {
  days: FitbitDaySnapshot[];
} {
  return {
    days: Object.values(days)
      .sort((a, b) => a.date.localeCompare(b.date)),
  };
}
