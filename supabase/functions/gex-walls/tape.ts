/*
 * tape.ts · reading the options tape (handoff 32, 25 Oct 2026). Who bought and who sold, from where each
 * trade printed against the quote at that moment, kept apart from Theta and Supabase so it can be tested.
 *
 * Customer side of one print, s in [-1, 1]: at or above the ask the customer bought (s = 1), at or below the
 * bid the customer sold (s = -1), in between in part, linear from the mid (exactly mid: 0, unclassified). A
 * print with no two-sided quote is unclassified. Multi-leg, tied-to-stock and auction or cross prints are
 * never dropped: they count by price only when the price is clear (|s| >= 0.5), otherwise unclassified.
 * The dealer is the other side: dealer net = customer sold - customer bought.
 *
 * Print types come from Theta's trade condition (OPRA's list, checked against the quotes on 23 Oct 2026:
 * 18 auto-execution, 95 sweep, 125-129 single-leg auction, cross and floor, 130-134, 136-137, 144 multi-leg,
 * 135, 138-143 stock-option).
 */

export type Kind = 'single' | 'multi' | 'tied' | 'auction' | 'other';

export function kindOf(cond: number): Kind {
  if (cond >= 125 && cond <= 129) return 'auction';
  if ((cond >= 130 && cond <= 134) || cond === 136 || cond === 137 || cond === 144) return 'multi';
  if (cond === 135 || (cond >= 138 && cond <= 143)) return 'tied';
  if (cond === 0 || cond === 18 || cond === 95) return 'single';
  return 'other';
}

/** The customer's side of one print, -1 sold to 1 bought; 0 unclassified. */
export function side(price: number, bid: number, ask: number, kind: Kind): number {
  if (!(bid > 0 && ask > bid && price > 0)) return 0;
  const mid = (bid + ask) / 2, half = (ask - bid) / 2;
  const s = Math.max(-1, Math.min(1, (price - mid) / half));
  if (Math.abs(s) < 1e-9) return 0;
  if (kind !== 'single' && kind !== 'other' && Math.abs(s) < 0.5 - 1e-9) return 0;
  return s;
}

export interface Print { k: number; cp: 'C' | 'P'; price: number; bid: number; ask: number; size: number; cond: number }
export interface ContractDay { k: number; cp: 'C' | 'P'; vol: number; buy: number; sell: number; uncl: number }
export interface ExpiryDay {
  vol: number; classified: number; trades: number; small: number; callVol: number; putVol: number;
  sizes: Record<string, number>; byKind: Record<Kind, number>;
}

/** Trade size buckets for the median: 1 to 10 one by one, then ranges. */
export function sizeBucket(n: number): string {
  if (n <= 10) return String(n);
  if (n <= 25) return '11-25';
  if (n <= 50) return '26-50';
  if (n <= 100) return '51-100';
  return '101+';
}

/** One expiry's prints for a day: per contract, and the expiry's totals. Strikes outside `band` (a price
    range) are left out of the contracts but still count in the totals. */
export function aggregate(prints: Iterable<Print>, band?: [number, number]): { contracts: ContractDay[]; day: ExpiryDay } {
  const a = new Tally(band);
  for (const p of prints) a.add(p);
  return a.result();
}

/** The same, straight off the stream: a busy expiry is never held in memory (TSLA's next-day weekly on 3 Sep 2026
    ran the function out of compute when every print was kept first). */
export async function aggregateStream(prints: AsyncIterable<Print>, band?: [number, number]) {
  const a = new Tally(band);
  for await (const p of prints) a.add(p);
  return a.result();
}

class Tally {
  by = new Map<string, ContractDay>();
  day: ExpiryDay = { vol: 0, classified: 0, trades: 0, small: 0, callVol: 0, putVol: 0, sizes: {},
    byKind: { single: 0, multi: 0, tied: 0, auction: 0, other: 0 } };
  constructor(private band?: [number, number]) {}
  result() { return { contracts: [...this.by.values()], day: this.day }; }
  add(p: Print) {
    const day = this.day, by = this.by, band = this.band;
    if (!(p.size > 0)) return;
    const kind = kindOf(p.cond), s = side(p.price, p.bid, p.ask, kind);
    day.vol += p.size; day.trades += 1; day.classified += p.size * Math.abs(s);
    if (p.size <= 10) day.small += 1;
    if (p.cp === 'C') day.callVol += p.size; else day.putVol += p.size;
    const b = sizeBucket(p.size); day.sizes[b] = (day.sizes[b] ?? 0) + 1;
    day.byKind[kind] += p.size;
    if (band && (p.k < band[0] || p.k > band[1])) return;
    const key = `${p.k}|${p.cp}`;
    let c = by.get(key);
    if (!c) { c = { k: p.k, cp: p.cp, vol: 0, buy: 0, sell: 0, uncl: 0 }; by.set(key, c); }
    c.vol += p.size;
    if (s > 0) c.buy += p.size * s; else if (s < 0) c.sell += p.size * -s;
    c.uncl += p.size * (1 - Math.abs(s));
  }
}

/** The median trade size from the size buckets (a range reads as its low end). */
export function medianSize(sizes: Record<string, number>): number | null {
  const order = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11-25', '26-50', '51-100', '101+'];
  const total = order.reduce((s, k) => s + (sizes[k] ?? 0), 0);
  if (!total) return null;
  let run = 0;
  for (const k of order) { run += sizes[k] ?? 0; if (run >= total / 2) return Number(k.split('-')[0].replace('+', '')); }
  return null;
}

/** Parse Theta's trade_quote CSV, a chunk of lines at a time (TSLA's weekly is about 40,000 prints a day, its
    next-day expiry several times that). Only the seven fields used are read; quotes come off them alone. */
export async function* csvPrints(body: ReadableStream<Uint8Array>): AsyncGenerator<Print> {
  const chunks = body.pipeThrough(new TextDecoderStream());
  const uq = (x: string | undefined) => (x && x.charCodeAt(0) === 34 ? x.slice(1, -1) : x ?? '');
  let rest = '', head = false;
  let iK = -1, iR = -1, iP = -1, iB = -1, iA = -1, iS = -1, iC = -1;
  for await (const chunk of chunks) {
    const lines = (rest + chunk).split('\n');
    rest = lines.pop() ?? '';
    for (const raw of lines) {
      const line = raw.trim();
      if (!line) continue;
      const f = line.split(',');
      if (!head) {
        const h = f.map(uq); head = true;
        iK = h.indexOf('strike'); iR = h.indexOf('right'); iP = h.indexOf('price'); iB = h.indexOf('bid');
        iA = h.indexOf('ask'); iS = h.indexOf('size'); iC = h.indexOf('condition');
        continue;
      }
      yield { k: Number(uq(f[iK])), cp: uq(f[iR]) === 'CALL' ? 'C' : 'P', price: Number(uq(f[iP])), bid: Number(uq(f[iB])),
              ask: Number(uq(f[iA])), size: Number(uq(f[iS])), cond: Number(uq(f[iC])) };
    }
  }
  if (rest.trim() && head) {
    const f = rest.trim().split(',');
    yield { k: Number(uq(f[iK])), cp: uq(f[iR]) === 'CALL' ? 'C' : 'P', price: Number(uq(f[iP])), bid: Number(uq(f[iB])),
            ask: Number(uq(f[iA])), size: Number(uq(f[iS])), cond: Number(uq(f[iC])) };
  }
}

/** The running dealer position for one contract after a session: yesterday's plus the dealer's net that day
    (customer sold minus bought), never more than open interest either way. */
export function step(pos: number, c: { buy: number; sell: number }, oi: number | null): number {
  const next = pos + c.sell - c.buy;
  return oi == null ? next : Math.max(-oi, Math.min(oi, next));
}

/** What the open-interest model assumes for a contract the tape did not see open: dealers long the calls and
    short the puts (customers overwrite calls and buy puts). */
export const seedOf = (cp: 'C' | 'P', oi: number) => (cp === 'C' ? oi : -oi);
