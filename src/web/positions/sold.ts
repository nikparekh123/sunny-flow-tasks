// Every sold leg of the book, from Home's payload (brief_inputs: strike, count, sold at, the mark, each leg's own IV),
// for the name strip's dot (positions-engine nameDot: a sold leg in the money or within 0.5 SD). The Sold, in SD card
// that used to read these is off (handoff 2026-11-24 §4: its content lives in Every leg).
import type { J } from '../lib/data';
import { ny } from '../lib/clock';
import { tradingDays, type SoldIn } from '../../../supabase/functions/_shared/positions-engine.ts';
import { expLabel } from './model';
import type { SdReply } from './intel';

/** The days the market is shut, from Home's calendar. */
export const closedDays = (calendar: J): Set<string> =>
  new Set(((Array.isArray(calendar) ? calendar : []) as J[]).filter((d) => d?.kind === 'closed' && d?.date).map((d) => String(d.date)));

/** Every sold leg of the book, from Home's payload; z0 from the names' sunny-sd replies when they are in. */
export function soldLegs(payload: J, sd: Map<string, SdReply | undefined>): SoldIn[] {
  const inp = payload?.brief_inputs;
  if (!inp?.names) return [];
  const n0 = ny(), closed = closedDays(payload?.calendar), gone = Math.max(0, (Date.now() - Date.parse(inp.built_at)) / 864e5);
  const out: SoldIn[] = [];
  for (const n of inp.names as J[]) {
    const S = Number(n.S0);
    if (!(S > 0)) continue;
    const reply = sd.get(String(n.t));
    for (const l of (n.legs ?? []) as J[]) {
      if (l.ty === 'S' || !(Number(l.q) < 0) || !l.ex) continue;
      const put = l.ty === 'P', K = Number(l.K), ex = String(l.ex), cd = Math.max(0, Number(l.days) - gone);
      const iv = Number(l.iv) > 0.03 ? Number(l.iv) : Number(n.iv) || 0;
      const z0 = reply?.sold?.find((s) => s.put === put && Math.abs(s.K - K) < 1e-6 && s.ex === ex)?.z0 ?? null;
      out.push({ t: String(n.t), S, put, K, n: -Number(l.q), ex, exLabel: expLabel(ex, Math.round(cd)), entry: l.at != null ? Number(l.at) : null,
        mark: l.now != null ? Number(l.now) : null, iv, td: tradingDays(n0.date, ex, closed, n0.mins), cd, z0 });
    }
  }
  return out;
}
