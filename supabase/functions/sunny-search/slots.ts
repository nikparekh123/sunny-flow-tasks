/**
 * Number slots (Sunny search, 28 Oct 2026; handoff "Search for launch", hard rule 1: the model picks the shape and
 * writes the words, it never writes a number). Every number a lookup returns reaches the model tagged with a short
 * name ("r12=99.63"). The answer asks for a figure as [r12|$2], or works one out from a few of them ([r3-r5|$]),
 * and Sunny writes the figure itself, rounded the way the design asks. Signs are never written: a fall is red.
 * Small whole numbers (counts up to 20: "3 days", "×15") stay plain; the number check (check.ts) covers those.
 */
type Json = null | boolean | number | string | Json[] | { [k: string]: Json };

/** Formats, after the bar: $ dollars, $2 to the cent, $k short ($3.8K, $46.3B), % one decimal, %0 whole, %2 two,
    # whole number, #1 and #2 decimals, d a delta (.62), x a multiple (18.0x), k a strike (104, 37.5). */
export function fmt(v: number, f: string): string {
  const a = Math.abs(v), us = (x: number, d = 0) => x.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
  const short = (x: number) => {
    const [u, s] = x >= 1e12 ? [1e12, 'T'] : x >= 1e9 ? [1e9, 'B'] : x >= 1e6 ? [1e6, 'M'] : x >= 1e3 ? [1e3, 'K'] : [1, ''];
    const y = x / u;
    return s ? (y >= 100 ? us(y) : y.toFixed(1).replace(/\.0$/, '')) + s : us(x);
  };
  switch (f.trim()) {
    case '$': return '$' + us(Math.round(a));
    case '$2': return '$' + us(a, 2);
    case '$k': return '$' + short(a);
    case '%': return a.toFixed(1) + '%';
    case '%0': return Math.round(a) + '%';
    case '%2': return a.toFixed(2) + '%';
    case '#': return us(Math.round(a));
    case '#1': return us(a, 1);
    case '#2': return us(a, 2);
    case 'd': return a >= 1 ? a.toFixed(2) : a.toFixed(2).replace(/^0/, '');
    case 'x': return a.toFixed(1) + 'x';
    case 'k': { const r = Math.round(a * 100) / 100; return Number.isInteger(r) ? String(r) : r.toFixed(2); }   // 104, 37.50
    case '': return Number.isInteger(a) ? us(a) : us(a, 2);
  }
  throw new Error(`format ${f}`);
}

/** Formats that count up on screen (the big number): whole dollars and whole numbers. */
export const COUNTS = new Set(['$', '#']);

/** Literal numbers a slot may use besides its names: small counts and 100 (for a percent). */
const LITERAL_OK = (n: number) => n === 100 || (Number.isInteger(n) && n >= 0 && n <= 20);

/* Money, prices, rates and greeks are named however small: they are never counts. A hedge's $13 a day of theta
   stayed plain like "15 calls", so the model could not write it and left seven of ten hedges blank (30 Oct 2026). */
const MEASURE = /usd|pct|price|strike|theta|delta|gamma|vega|mark|paid|cost|premium|pnl|value|iv/i;

export class Slots {
  readonly vals = new Map<string, number>();
  private n = 0;

  /** A copy of the data with every number named; a small whole number stays plain only when it is a count. */
  tag(v: Json, key = ''): Json {
    if (typeof v === 'number') {
      if (!Number.isFinite(v) || (Number.isInteger(v) && Math.abs(v) <= 20 && !MEASURE.test(key))) return v;
      const k = `r${++this.n}`;
      this.vals.set(k, v);
      return `${k}=${v}`;
    }
    if (Array.isArray(v)) return v.map((x) => this.tag(x, key));
    if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, this.tag(x, k)]));
    return v;
  }

  /** The value of one slot's sum: names, + - * /, brackets, abs(), and the few literals allowed. */
  value(expr: string): number {
    const toks = expr.replace(/\s+/g, '').match(/abs\(|r\d+|\d+(?:\.\d+)?|[-+*/()]/g) ?? [];
    if (toks.join('') !== expr.replace(/\s+/g, '')) throw new Error(`cannot read ${expr}`);
    let i = 0;
    const atom = (): number => {
      const t = toks[i++];
      if (t === '(') { const x = sum(); if (toks[i++] !== ')') throw new Error('bracket'); return x; }
      if (t === 'abs(') { const x = sum(); if (toks[i++] !== ')') throw new Error('bracket'); return Math.abs(x); }
      if (t === '-') return -atom();
      if (t && /^r\d+$/.test(t)) { const x = this.vals.get(t); if (x == null) throw new Error(`${t} is not a number you read`); return x; }
      if (t && /^\d/.test(t)) { const x = Number(t); if (!LITERAL_OK(x)) throw new Error(`${t} is written by hand`); return x; }
      throw new Error(`cannot read ${expr}`);
    };
    const prod = (): number => { let x = atom(); while (toks[i] === '*' || toks[i] === '/') { const op = toks[i++], y = atom(); x = op === '*' ? x * y : x / y; } return x; };
    const sum = (): number => { let x = prod(); while (toks[i] === '+' || toks[i] === '-') { const op = toks[i++], y = prod(); x = op === '+' ? x + y : x - y; } return x; };
    const x = sum();
    if (i !== toks.length || !Number.isFinite(x)) throw new Error(`cannot read ${expr}`);
    return x;
  }

  /** Every slot in a text written out; what could not be is listed, and left out of the text. */
  fill(text: string, bad: string[]): string {
    return text.replace(SLOT, (_m, expr: string, f = '') => {
      try { return fmt(this.value(expr), f); } catch (e) { bad.push(`[${expr}${f ? '|' + f : ''}]: ${(e as Error).message}`); return ''; }
    });
  }
}

/** A slot: [names and signs | format], with at least one name in it. */
export const SLOT = /\[((?=[^\]|]*\br\d)[^\]|]+)(?:\|([^\]]*))?\]/g;
