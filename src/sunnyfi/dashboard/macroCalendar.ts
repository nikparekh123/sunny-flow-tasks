/**
 * Hardcoded macro events calendar.
 *
 * Per CD-1 scoping, we run with a static file rather than an admin UI
 * for now — easier to ship, low maintenance burden (re-edit quarterly).
 * Keep dates ISO YYYY-MM-DD; time is wall-clock ET. Sort doesn't matter
 * — the dashboard filters by date and renders chronologically.
 *
 * Categories:
 *   • FOMC  — rate decision or meeting minutes
 *   • CPI   — Consumer Price Index, monthly
 *   • PCE   — Personal Consumption Expenditures, monthly (Fed's pref)
 *   • NFP   — Non-Farm Payrolls, first Friday of the month
 *
 * Tone drives the chip color: 'warn' for high-impact (FOMC, NFP, CPI),
 * 'plain' for everything else.
 */

export type MacroKind = "FOMC" | "CPI" | "PCE" | "NFP";

export interface MacroEvent {
  date: string;            // YYYY-MM-DD
  timeET: string;          // "14:00 ET" / "08:30 ET"
  kind: MacroKind;
  label: string;           // "FOMC minutes" / "Core CPI" etc.
  tone: "warn" | "plain";
}

export const MACRO_EVENTS: MacroEvent[] = [
  // Late May / June 2026
  { date: "2026-05-27", timeET: "14:00 ET", kind: "FOMC", label: "FOMC minutes",        tone: "warn"  },
  { date: "2026-05-30", timeET: "08:30 ET", kind: "PCE",  label: "PCE inflation",       tone: "warn"  },
  { date: "2026-06-05", timeET: "08:30 ET", kind: "NFP",  label: "Non-farm payrolls",   tone: "warn"  },
  { date: "2026-06-11", timeET: "08:30 ET", kind: "CPI",  label: "CPI inflation",       tone: "warn"  },
  { date: "2026-06-17", timeET: "14:00 ET", kind: "FOMC", label: "FOMC rate decision",  tone: "warn"  },
  { date: "2026-06-26", timeET: "08:30 ET", kind: "PCE",  label: "PCE inflation",       tone: "warn"  },

  // July
  { date: "2026-07-03", timeET: "08:30 ET", kind: "NFP",  label: "Non-farm payrolls",   tone: "warn"  },
  { date: "2026-07-15", timeET: "08:30 ET", kind: "CPI",  label: "CPI inflation",       tone: "warn"  },
  { date: "2026-07-29", timeET: "14:00 ET", kind: "FOMC", label: "FOMC rate decision",  tone: "warn"  },
  { date: "2026-07-31", timeET: "08:30 ET", kind: "PCE",  label: "PCE inflation",       tone: "warn"  },
];

/** Convenience — events on a specific ISO date, sorted by time. */
export function macroEventsOn(date: string): MacroEvent[] {
  return MACRO_EVENTS
    .filter((e) => e.date === date)
    .sort((a, b) => a.timeET.localeCompare(b.timeET));
}

/** Convenience — events in [today, today+nDays) inclusive of start. */
export function macroEventsWithin(startIso: string, nDays: number): MacroEvent[] {
  const end = new Date(startIso + "T00:00:00Z");
  end.setUTCDate(end.getUTCDate() + nDays);
  const endIso = end.toISOString().slice(0, 10);
  return MACRO_EVENTS
    .filter((e) => e.date >= startIso && e.date < endIso)
    .sort((a, b) => (a.date + a.timeET).localeCompare(b.date + b.timeET));
}
