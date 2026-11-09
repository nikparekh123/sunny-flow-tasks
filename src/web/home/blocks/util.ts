// Shared bits for Home's section blocks: the server's runs of words, the design's numbers rules applied to the
// server's strings, the heat-map tile colours (the design's dark palette), and a scroll to a block.
import type { J } from '../../lib/data';
import { C, clean, money, named, pct } from '../../lib/format';

/** One run of words from the brief doc: { t, b, c } (BriefSpan). */
export interface Span { t: string; b?: boolean; c?: string }

/** The doc's runs: a string, a list of strings, or a list of { t, b, c } (BriefSpan.list). */
export const spans = (v: J): Span[] => {
  if (v == null) return [];
  if (typeof v === 'string') return v ? [{ t: v }] : [];
  if (Array.isArray(v)) return v.flatMap((x) => (typeof x === 'string' ? [{ t: x }] : x && typeof x.t === 'string' ? [{ t: x.t, b: x.b, c: x.c }] : []));
  if (typeof v.t === 'string') return [{ t: v.t, b: v.b, c: v.c }];
  return [];
};
export const plain = (v: J) => spans(v).map((s) => s.t).join('');

/** The numbers rules on a book sentence from the server: whole dollars with thousands become K and M ($16,432 →
    $16.4K; prices with cents, strikes and $211 stay), and a percentage keeps one decimal (two only under 0.1%). */
export const tidy = (s: string | null | undefined) =>
  clean(s)
    .replace(/\$(\d{1,3}(?:,\d{3})+)(?!\d|[.,]\d)/g, (_, n: string) => money(+n.replace(/,/g, '')))
    .replace(/(?<![\d.])(\d+\.\d{2,})%/g, (m, n: string) => (+n >= 0.1 ? pct(+n) : m));

/** A move as the design writes it: "▲ 1.8%", "▼ 2 bp", coloured by the server's colour name or the sign. */
export function move(text: string | null | undefined, color?: string | null, signed?: number | null): { t: string; c: string } {
  const raw = clean(text).replace(/^[↑↓▲▼+\-−]\s*/, '').trim();
  const sign = signed != null && isFinite(+signed) && +signed !== 0 ? Math.sign(+signed)
    : color === 'green' || color === 'up' ? 1 : color === 'red' || color === 'down' ? -1
    : /^[↓▼\-−]/.test(clean(text).trim()) ? -1 : /^[↑▲+]/.test(clean(text).trim()) ? 1 : 0;
  const m = /^(\d+(?:\.\d+)?)%$/.exec(raw);
  const body = m ? pct(+m[1]) : raw;
  const c = color ? named(color, sign > 0 ? C.green : sign < 0 ? C.red : C.ink) : sign > 0 ? C.green : sign < 0 ? C.red : C.ink;
  return { t: (sign < 0 ? '▼ ' : '▲ ') + body, c };
}
/** A signed percent number as a move: 1.8 → "▲ 1.8%". */
export const pmove = (p: number) => (p < 0 ? '▼ ' : '▲ ') + pct(p);

/** A reading or level with its sign taken off (red says negative): "-0.52" → "0.52", "+6.3%" → "6.3%". */
export const unsign = (s: string | null | undefined) => clean(s).replace(/^[+\-−]\s*/, '');
export const isNeg = (s: string | null | undefined) => /^[\-−]/.test(clean(s).trim());
/** The number in a reading: "2.33%" → 2.33, "189K" → 189, "-0.52" → -0.52. */
export const numOf = (s: string | null | undefined) => {
  const m = /[+\-−]?\d[\d,]*(?:\.\d+)?/.exec(clean(s));
  return m ? parseFloat(m[0].replace(/[−]/, '-').replace(/,/g, '')) : NaN;
};

/** The design's heat tiles on dark (dk() of its UB/UF/DB/DF): by size of move <0.5, <1.5, <3, more; the text in
    the tile's own colour, lighter on the deeper tiles. */
const UB = ['#1D3521', '#22492A', '#2A6232', '#2E7034'], UF = ['#A8DCA3', '#B5E3B0', '#C8EDC4', '#E3F5E0'];
const DB = ['#3D2322', '#572927', '#77302D', '#A53A35'], DF = ['#F2A9A5', '#F5B8B4', '#F9CFCC', '#FDE5E3'];
export const tileColors = (p: number) => {
  const a = Math.abs(p), L = a < 0.5 ? 0 : a < 1.5 ? 1 : a < 3 ? 2 : 3;
  return p >= 0 ? { bg: UB[L], fg: UF[L] } : { bg: DB[L], fg: DF[L] };
};

/** The page scrolls the window; a block lands 92 px under the top (clear of the 64 px header). */
export function scrollToSel(sel: string) {
  const el = document.querySelector(sel) as HTMLElement | null;
  if (!el) return;
  const top = el.getBoundingClientRect().top + window.scrollY - 92;
  const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  window.scrollTo({ top: Math.max(0, top), behavior: reduce ? 'auto' : 'smooth' });
}

/** The tab a brief moment belongs to (TAB_OF), with the futures brief on Pre. */
export type Mo = 'pre' | 'open' | 'post' | 'weekend';
export const momentOf = (m: string | null | undefined): Mo =>
  m === 'post' ? 'post' : m === 'weekend' ? 'weekend' : m === 'pre' || m === 'futures' ? 'pre' : 'open';
