import { afterEach, expect, it, vi } from "vitest";
import { savedFitbitHistory } from "../src/fitbit/history";
import type { FitbitDaySnapshot } from "../src/fitbit/types";

afterEach(() => vi.restoreAllMocks());

it("returns all saved Fitbit dates sorted without synchronizing or exposing connection secrets", () => {
  const fetch = vi.spyOn(globalThis, "fetch");
  const old = { date: "2024-01-01", source: "fitbit", steps: 0 } as FitbitDaySnapshot;
  const recent = { date: "2026-10-12", source: "fitbit", heartProfile: [{ average: 61 }] } as FitbitDaySnapshot;
  const input = { recent, old };
  expect(savedFitbitHistory(input)).toEqual({ days: [old, recent] });
  expect(Object.keys(input)).toEqual(["recent", "old"]);
  expect(fetch).not.toHaveBeenCalled();
});

it("returns an empty history when no snapshots are saved", () => {
  expect(savedFitbitHistory({})).toEqual({ days: [] });
});
