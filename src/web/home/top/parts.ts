// Together's per-account parts on Home (handoff 2026-11-24 §2.2 and §3, Current Web `acct === 'tog'`): every total
// is both accounts with each one's part under it. The server sends each account's own Home pieces in payload.split
// (Together only, null on Sunny and Nicolay): its chart, value, today, Open P&L, margin, time value left and each
// section headline's key figure. Each part is worked out with the SAME functions the page uses for the total
// (chartModel, rangeView, stats, todayChange, weekChange), on a payload built from that account's piece.
import type { J } from '../../lib/data';
import { arrow, C, money } from '../../lib/format';
import { chartModel, type ChartModel, type Range } from './model';

export interface AcctPart {
  id: string;
  /** "Sunny", "Nicolay". */
  name: string;
  /** "S", "N": the account's id (the stats row writes the full name, Nik 24 Nov 2026). */
  ini: string;
  /** The account's piece laid out as a Home payload, so the page's own functions read it. */
  payload: J;
  m: ChartModel | null;
}

/** Each account's part on Together, in the server's order (Sunny, Nicolay); empty on a single account. */
export function acctParts(payload: J): AcctPart[] {
  const sp: J[] = Array.isArray(payload?.split) ? payload.split : [];
  if (sp.length < 2) return [];
  return sp.map((s) => {
    const p: J = {
      today: payload?.today,
      chart: s?.chart ?? null,
      account: {
        value: s?.value ?? undefined,
        today: s?.today != null ? { amount: +s.today } : undefined,
        open_pl: s?.open_pl ?? null,
        margin: s?.margin ?? null,
        time_value_sold: s?.time_value_sold ?? null,
      },
      brief: s?.tvLeft != null ? { timeValue: { tvLeft: +s.tvLeft } } : undefined,
    };
    const name = String(s?.name ?? s?.id ?? '');
    return { id: String(s?.id ?? ''), name, ini: String(s?.id ?? name.charAt(0)), payload: p, m: chartModel(p) };
  });
}

/** The account's model with every range starting on its last close on or before `day` (the total's start), so each
    part covers the same days as the total. An account that began later starts at its first close. */
export function startingOn(m: ChartModel, day: string): ChartModel {
  let s = 0;
  for (let i = m.n - 1; i >= 0; i--) if (m.days[i] <= day) { s = i; break; }
  return { ...m, start: (_r: Range) => s };
}

/** "Sunny ▼ $13.7K · Nicolay ▲ $4.2K" (the change lines' parts, grey with their arrows). Null when any part is missing. */
export function changeParts(parts: AcctPart[], f: (p: AcctPart) => number | null): string | null {
  if (!parts.length) return null;
  const v = parts.map((p) => ({ p, d: f(p) }));
  if (v.some((x) => x.d == null || !Number.isFinite(x.d))) return null;
  return v.map(({ p, d }) => `${p.name} ${arrow(d!)} ${money(d!)}`).join(' · ');
}

/** One stat's part: "Sunny $4.9K" (`ini` carries the account's full name); `c` red marks a loss, which the page
    draws as a − in grey (handoff 2026-11-25-focus §2.2). */
export interface StatPart { ini: string; v: string; c: string }
export const statPart = (ini: string, x: number | null): StatPart | null =>
  x == null || !Number.isFinite(x) ? null : { ini, v: money(x), c: Math.round(x) < 0 ? C.red : '#8C8C8C' };

/** The key figure of each account's section headline ("$13.7K", "6.2%"), by the section's kicker. */
export function headParts(payload: J, kicker: string): { name: string; v: string }[] {
  const sp: J[] = Array.isArray(payload?.split) ? payload.split : [];
  if (sp.length < 2) return [];
  const key = (k: string) => String(k ?? '').replace(/^\d+\s*·\s*/, '').trim().toLowerCase();
  const want = key(kicker);
  const out: { name: string; v: string }[] = [];
  for (const s of sp) {
    const h = s?.heads ?? {};
    const hit = Object.keys(h).find((k) => key(k) === want);
    if (hit && h[hit]) out.push({ name: String(s?.name ?? s?.id ?? ''), v: String(h[hit]) });
  }
  return out;
}

/** Which account holds a name on Together ("Sunny", "Nicolay", or both), from each account's names. */
export function holderOf(payload: J): (t: string) => string {
  const sp: J[] = Array.isArray(payload?.split) ? payload.split : [];
  if (sp.length < 2) return () => '';
  const sets = sp.map((s) => ({ name: String(s?.name ?? s?.id ?? ''), ts: new Set<string>((s?.names ?? []).map(String)) }));
  return (t: string) => sets.filter((x) => x.ts.has(t)).map((x) => x.name).join(' and ');
}
