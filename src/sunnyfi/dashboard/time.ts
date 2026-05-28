/**
 * Time helpers shared by the dashboard.
 *
 *   useNow(intervalMs)   — re-renders the hook caller every N ms with a
 *                          fresh Date. 30s default; 1s if you need to
 *                          watch the countdown.
 *   marketClock(now)     — "Markets open in 2h 48m" / "closes in 4h 12m"
 *                          / "closed". Approximates EDT (Mar-Nov) / EST.
 *   fmtBrandDate(now)    — "FRI · JUN 27 · 06:42 AM PT"
 *
 * The clock label says PT throughout because the user trades from the
 * west coast; if/when timezone becomes a setting we lift it here.
 */
import { useEffect, useState } from "react";

export function useNow(intervalMs = 30_000): Date {
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
  return now;
}

/** Returns the market state + a human countdown phrase. */
export function marketClock(now: Date): { phrase: string; live: boolean } {
  const dow = now.getDay();
  if (dow === 0 || dow === 6) return { phrase: "Markets closed · weekend", live: false };

  // Convert local time to ET. We approximate DST (March → November = EDT
  // UTC-4, otherwise EST UTC-5) — accurate enough for a status string.
  const month = now.getMonth();
  const etOffset = month >= 2 && month <= 10 ? -4 : -5;
  const utc = now.getTime() + now.getTimezoneOffset() * 60_000;
  const et = new Date(utc + etOffset * 3_600_000);
  const etMins = et.getHours() * 60 + et.getMinutes();
  const open = 9 * 60 + 30;
  const close = 16 * 60;

  const fmtGap = (mins: number) => {
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    if (h === 0) return `${m}m`;
    return `${h}h ${m.toString().padStart(2, "0")}m`;
  };

  if (etMins >= open && etMins < close) {
    return { phrase: `Markets close in ${fmtGap(close - etMins)}`, live: true };
  }
  if (etMins < open) {
    return { phrase: `Markets open in ${fmtGap(open - etMins)}`, live: false };
  }
  return { phrase: "Markets closed", live: false };
}

/** "FRI · JUN 27 · 06:42 AM PT" — used by BrandBar + Cockpit hero. */
export function fmtBrandDate(d: Date): string {
  const days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
  const months = [
    "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
    "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
  ];
  const hh = d.getHours();
  const mm = d.getMinutes().toString().padStart(2, "0");
  const ampm = hh >= 12 ? "PM" : "AM";
  const h12 = ((hh + 11) % 12) + 1;
  return `${days[d.getDay()]} · ${months[d.getMonth()]} ${d.getDate()} · ${h12.toString().padStart(2, "0")}:${mm} ${ampm} PT`;
}
