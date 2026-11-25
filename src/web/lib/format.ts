// Numbers and words on the Sunny web, README "Rules that apply everywhere".
// - Money in K and M: $624, $5.9K, $13.7K, $379K, $1.2M, no trailing .0 (the app's fK, one rule for app and web).
// - Exact: the account value at the top of Home ($92,000), stock prices, strikes and index levels.
// - A gain or a loss carries a sign (handoff 2026-11-25-focus §2.2): + up, − (U+2212) down, never a colour on the
//   words (`wordOf`, `signBy`); no sign while privacy hides the figure. Arrows stay where the copy has them.
// - Percentages: one decimal; two only under 0.1%.
// - No em dashes anywhere.
import { fK } from '../../../supabase/functions/_shared/book-engine.ts';
import { signed, word } from './focus';

export const C = {
  ink: '#F2F2F2', ink2: '#8C8C8C', ink3: '#AAAAAA',
  green: '#4CBB6C', red: '#E82127', orange: '#E8A33D', blue: '#3E6AE1', teal: '#AAAAAA', violet: '#B9A3F0',
} as const;

/** Money in K and M, no sign: $624, $5.9K, $1.2M (`signBy` / `signed` put the sign on). */
export const money = (x: number | null | undefined) => fK(+(x ?? 0));
/** Whole dollars, exact, no sign: $92,000 (the account value at the top of Home). */
export const dollars = (x: number | null | undefined) => '$' + Math.round(Math.abs(+(x ?? 0))).toLocaleString('en-US');
/** A share price, strike or premium: $35.28 (exact, two decimals). */
export const price = (x: number | null | undefined) =>
  '$' + Math.abs(+(x ?? 0)).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
/** An index level or other plain number with its decimals: 6,742 or 4.08. */
export const level = (x: number | null | undefined, dp = 2) =>
  Math.abs(+(x ?? 0)).toLocaleString('en-US', { minimumFractionDigits: dp, maximumFractionDigits: dp });
/** A count with thousands separators, no sign: 3,000. */
export const count = (x: number | null | undefined) => Math.round(Math.abs(+(x ?? 0))).toLocaleString('en-US');

/** A percentage from a percent number (2.7 → "2.7%"): one decimal, two under 0.1%, no sign. */
export const pct = (p: number | null | undefined) => {
  const a = Math.abs(+(p ?? 0));
  return (a > 0 && a < 0.1 ? a.toFixed(2) : a.toFixed(1)) + '%';
};
/** A percentage from a fraction (0.027 → "2.7%"). */
export const pctOf = (f: number | null | undefined) => pct(+(f ?? 0) * 100);

/** Green up, red down, grey flat. */
export const tone = (x: number | null | undefined, flat = C.ink2) => (+(x ?? 0) > 0 ? C.green : +(x ?? 0) < 0 ? C.red : flat);
/** ▲ or ▼ by sign (for copy that carries an arrow, like "▼ 1.7%"). */
export const arrow = (x: number | null | undefined) => (+(x ?? 0) < 0 ? '▼' : '▲');

/** Server colour names (the brief doc's "green", "red", "orange", "blue", "secondary", "ink") to the web's colours. */
export const named = (c: string | null | undefined, fallback: string = C.ink) => {
  switch (c) {
    case 'green': case 'up': case 'gain': return C.green;
    case 'red': case 'down': case 'loss': return C.red;
    case 'orange': case 'act': case 'watch': return C.orange;
    case 'blue': case 'navy': return C.blue;
    case 'teal': return C.teal;
    case 'violet': return C.violet;
    case 'secondary': case 'gray': case 'grey': case 'muted': return C.ink2;
    case 'ink': case 'primary': return C.ink;
    default: return fallback;
  }
};

/* ── The focus look (handoff 2026-11-25-focus §2.1, §2.2) ─────────────────────────────────────────────────────── */
const HUES = new Set<string>([C.green, C.red, C.orange, C.blue, C.violet, '#FCC00A']);
/** §2.1: a colour on words turns neutral, ink at 15 px and up, grey under; ink, grey or no colour stays as it is. */
export const wordOf = (c: string | null | undefined, fs: number): string | undefined =>
  (c && HUES.has(c.toUpperCase()) ? word(fs) : c ?? undefined);
/** A bare money figure or a percentage: "$4.3K", "$9.4K left", "29.6%" (not "$•••", not words). */
const FIG = (s: string) => /^\$\d/.test(s) || /^\d[\d,]*(?:\.\d+)?%$/.test(s);
/** §2.2 by value: + up, − down before a bare money figure or percentage (the masked "$•••" and words stay). */
export const sgn = (v: number, s: string) => {
  const lead = /^\s*/.exec(s)![0], body = s.slice(lead.length);
  return FIG(body.trim()) ? lead + signed(v, body) : s;
};
/** §2.2 by the colour the figure used to wear: green +, red −; any other colour, no sign. */
export const signBy = (c: string | null | undefined, s: string) => sgn(c === C.green ? 1 : c === C.red ? -1 : 0, s);

/** Privacy (README): every dollar figure about the book becomes $•••; a $ figure with two decimals (a share price)
    stays, as do prices, strikes and index levels. Same rule as the design's msk(). */
export const maskMoney = (s: string) => s.replace(/\$\d[\d,]*(?:\.\d+)?[KM]?/g, (m) => (/\.\d\d$/.test(m) ? m : '$•••'));

/** No em or en dashes ever reach the page: the server's words are already clean, this is a last guard. */
export const clean = (s: string | null | undefined) => (s ?? '').replace(/\s*[—–]\s*/g, ' · ');
