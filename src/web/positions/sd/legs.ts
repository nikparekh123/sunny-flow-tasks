// SD on your positions (handoff 2026-11-11-sd-on-positions; App Explorations 139a). Every option leg held gets three
// short lines: how far its strike is from today in dollars, the same distance in SD by that leg's own expiry, and the
// odds in your favour. The maths is the calculator's (sd-engine.ts legSd and tradingYears), not a copy of it.
//
// Nik, 11 Nov 2026: each leg's OWN IV (from its price, the IV the page already prices that leg on), not the expiry's
// ATM IV; orange ("needs a look", sold legs only) when in the money, within 0.5 SD, or under 70% to expire worthless.
// These are prices and odds, not the book's dollars: they stay visible with privacy on.
import { legSd, tradingYears, type LegSd } from '../../../../supabase/functions/_shared/sd-engine.ts';
import { ny } from '../../lib/clock';
import type { J } from '../../lib/data';
import type { PLeg, PosModel } from '../model';

/** The 139a web colours: ink, muted, and the calculator's orange. */
export const L_INK = '#F5F5F7', L_MU = '#98989D', L_OR = '#F2A93B';

export interface LegLines extends LegSd {
  /** Line 1's colour: orange when the leg needs a look. */
  c1: string;
  /** Line 3's colour: orange on a sold leg under a 70% chance to expire worthless. */
  c3: string;
}

/** The days the market is shut, from Home's calendar (`kind: 'closed'`); none when the page has no calendar. */
export const closedDays = (calendar: J): Set<string> =>
  new Set(((Array.isArray(calendar) ? calendar : []) as J[]).filter((d) => d?.kind === 'closed' && d?.date).map((d) => String(d.date)));

const lines = (S: number, K: number, put: boolean, sold: boolean, iv: number, ex: string, exLabel: string, closed: Set<string>): LegLines | null => {
  if (!(S > 0) || !(K > 0) || !(iv > 0) || !ex) return null;
  const n = ny(), T = tradingYears(n.date, ex, closed, n.mins);
  const r = legSd({ S, K, put, sold, iv, T, exLabel });
  return { ...r, c1: r.look ? L_OR : L_INK, c3: sold && r.odds < 0.7 ? L_OR : L_MU };
};

/** The three lines for a leg on the page (null for shares). A held leg reads its own IV from the inputs the server
    priced it on; a What if trade (and a held leg with no IV of its own) reads the IV the page prices a trade on. */
export function legLines(m: PosModel, closed: Set<string>) {
  return (l: PLeg): LegLines | null => {
    if (l.ty === 'S') return null;
    const own = l.trade == null ? m.localLeg.get(l.k)?.iv ?? 0 : 0;
    const iv = own > 0.03 ? own : m.tradeIv;
    return lines(m.S0, l.K, l.ty === 'P', l.q < 0, iv, l.ex, l.exL, closed);
  };
}

/** Try a trade's line: the strike, expiry, side and Buy or Sell picked, on the IV the trade is priced on. */
export function draftLines(m: PosModel, closed: Set<string>, d: { side: 's' | 'b'; ty: 'c' | 'p'; K: number; ex: string }, exLabel: string): LegLines | null {
  return lines(m.S0, d.K, d.ty === 'p', d.side === 's', m.tradeIv, d.ex, exLabel, closed);
}
