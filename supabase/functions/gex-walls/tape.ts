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
  const r = new CsvReader();
  let out: Print[] = [];
  const keep = (p: Print) => { out.push({ ...p }); };
  for await (const chunk of body) {
    r.push(chunk, keep);
    if (out.length) { yield* out; out = []; }
  }
  r.end(keep);
  yield* out;
}

/** One expiry's day straight from Theta's CSV into the tally, with no print kept and no async step per print.
    NVDA's next-day weekly on 12 Nov 2026 was 673,329 prints: the string parser spent about 1.9 s of the worker's
    2 s CPU on it (546 WORKER_RESOURCE_LIMIT, "CPU Time exceeded"); this reads the bytes in place, about 3x less. */
export async function aggregateCsv(body: ReadableStream<Uint8Array>, band?: [number, number]) {
  const a = new Tally(band), r = new CsvReader(), add = (p: Print) => a.add(p);
  for await (const chunk of body) r.push(chunk, add);
  r.end(add);
  return a.result();
}

const POW10 = Array.from({ length: 23 }, (_, i) => 10 ** i);
const utf8 = new TextDecoder();
const space = (c: number) => c === 32 || (c >= 9 && c <= 13);

/** Theta's CSV read as bytes, a line at a time, each print handed to `emit` in one reused object (copy it to
    keep it). It reads every print exactly as the string parser did (split on commas, quotes stripped, the line
    trimmed, Number() on each field): a plain decimal is its digits over a power of ten, one rounding, which is
    the double Number() gives; anything else goes through Number() itself. */
export class CsvReader {
  private rest: Uint8Array | null = null;
  private first = true;
  private head = false;
  private iK = -1; private iR = -1; private iP = -1; private iB = -1; private iA = -1; private iS = -1; private iC = -1;
  private cuts = new Int32Array(256);
  private p: Print = { k: 0, cp: 'P', price: 0, bid: 0, ask: 0, size: 0, cond: 0 };

  push(chunk: Uint8Array, emit: (p: Print) => void) {
    let b = chunk, s = 0;
    // The byte-order mark the text decoder used to drop.
    if (this.first && chunk.length) { this.first = false; if (chunk.length >= 3 && chunk[0] === 0xef && chunk[1] === 0xbb && chunk[2] === 0xbf) s = 3; }
    if (this.rest) {
      const r = this.rest;
      b = new Uint8Array(r.length + chunk.length - s); b.set(r); b.set(chunk.subarray(s), r.length);
      s = 0; this.rest = null;
    }
    const cuts = this.cuts;
    let n = 0, ls = s;
    for (let i = s, len = b.length; i < len; i++) {
      const c = b[i];
      if (c === 44) { if (n < 256) cuts[n++] = i; } else if (c === 10) { this.line(b, ls, i, n, emit); ls = i + 1; n = 0; }
    }
    if (ls < b.length) this.rest = b.slice(ls);
  }

  end(emit: (p: Print) => void) {
    const r = this.rest;
    this.rest = null;
    if (!r || !this.head) return;
    let n = 0;
    for (let i = 0; i < r.length; i++) if (r[i] === 44 && n < 256) this.cuts[n++] = i;
    this.line(r, 0, r.length, n, emit);
  }

  /** One line, b[s, e), its commas at cuts[0, n). The first line with anything on it is the header. */
  private line(b: Uint8Array, s: number, e: number, n: number, emit: (p: Print) => void) {
    while (s < e && space(b[s])) s++;
    while (e > s && space(b[e - 1])) e--;
    if (s >= e) return;
    if (!this.head) {
      const h = utf8.decode(b.subarray(s, e)).split(',').map((x) => (x && x.charCodeAt(0) === 34 ? x.slice(1, -1) : x));
      this.head = true;
      this.iK = h.indexOf('strike'); this.iR = h.indexOf('right'); this.iP = h.indexOf('price'); this.iB = h.indexOf('bid');
      this.iA = h.indexOf('ask'); this.iS = h.indexOf('size'); this.iC = h.indexOf('condition');
      return;
    }
    const p = this.p;
    p.k = this.num(b, s, e, n, this.iK); p.cp = this.isCall(b, s, e, n, this.iR) ? 'C' : 'P';
    p.price = this.num(b, s, e, n, this.iP); p.bid = this.num(b, s, e, n, this.iB); p.ask = this.num(b, s, e, n, this.iA);
    p.size = this.num(b, s, e, n, this.iS); p.cond = this.num(b, s, e, n, this.iC);
    emit(p);
  }

  // Field i of the line is b[s, e): after comma i - 1 (or the line start) up to comma i (or the line end), quotes
  // off. A missing field is empty.
  private isCall(b: Uint8Array, ls: number, le: number, n: number, i: number): boolean {
    if (i < 0 || i > n) return false;
    let s = i === 0 ? ls : this.cuts[i - 1] + 1, e = i < n ? this.cuts[i] : le;
    if (s < e && b[s] === 34) { s++; e--; }
    return e - s === 4 && b[s] === 67 && b[s + 1] === 65 && b[s + 2] === 76 && b[s + 3] === 76;
  }

  private num(b: Uint8Array, ls: number, le: number, n: number, i: number): number {
    if (i < 0 || i > n) return 0;
    let s = i === 0 ? ls : this.cuts[i - 1] + 1, e = i < n ? this.cuts[i] : le;
    if (s < e && b[s] === 34) { s++; e--; }
    if (s >= e) return 0;
    let j = s, neg = false, m = 0, d = 0, digits = 0, dot = false;
    if (b[j] === 45) { neg = true; j++; }
    for (; j < e; j++) {
      const c = b[j];
      if (c >= 48 && c <= 57) { m = m * 10 + (c - 48); digits++; if (dot) d++; } else if (c === 46 && !dot) dot = true;
      else return Number(utf8.decode(b.subarray(s, e)));
    }
    if (!digits || digits > 15) return Number(utf8.decode(b.subarray(s, e)));
    const v = d ? m / POW10[d] : m;
    return neg ? -v : v;
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
