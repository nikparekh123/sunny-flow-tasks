// The index strip (README 1, item 5): the market numbers live here only (section 1 keeps its words).
// Six columns in the design's order; a column the data does not carry is left out, never made up:
//   Pre-market   ES NQ RTY (Home's futures, live) · 10Y (the brief's Overnight card) · VIX (the brief's index cards;
//                the data has no VX future) · DXY (Overnight's Dollar)
//   Hours, post  SPY QQQ IWM VIX (the brief's index cards); the brief carries no 10Y or DXY in these moments
//   Weekend      SPY QQQ IWM VIX the week (the brief's week cards) · 10Y and DXY (The world this week)
// An earlier brief picked on a moment tab shows its own cards, as they stood when it was written.
import type { J, Tab } from '../../lib/data';
import { arrow, C, pct } from '../../lib/format';
import { spansOf, type Span } from './spans';

export const INDEX_TYPES = new Set(['indexCards', 'futuresCards', 'theWeekIndexes']);

export interface Col { k: string; t: string; v: string; m: string; c: string }
export interface Strip { kicker: string; cols: Col[]; headline: Span[] | null }

const allCards = (doc: J): J[] => (Array.isArray(doc?.sections) ? doc.sections.flatMap((s: J) => (Array.isArray(s?.cards) ? s.cards : [])) : []);
/** A futures or index level as the brief writes one: no decimals from 1,000 up, else two. */
const lvl = (x: number) => (Math.abs(x) >= 1000 ? Math.round(x).toLocaleString('en-US') : x.toFixed(2));
const mv = (signed: number): Pick<Col, 'm' | 'c'> => ({ m: `${arrow(signed)} ${pct(signed)}`, c: signed < 0 ? C.red : C.green });

/** One of the brief's index cards: "$735.29" shows as 735.29 (a level, as the design writes it). */
function fromIndexCard(x: J): Col | null {
  if (!x?.symbol || x.price == null) return null;
  const s = typeof x.moveSigned === 'number' ? x.moveSigned : x.moveColor === 'red' ? -parseFloat(x.move) : parseFloat(x.move);
  if (!isFinite(s)) return null;
  return { k: x.symbol, t: x.symbol, v: String(x.price).replace(/^\$/, ''), ...mv(s) };
}
/** A row of the Overnight or The world this week card: "4.85%" and "1 bp", or "101.83" and "0.5%". */
function fromRow(r: J, t: string): Col | null {
  if (!r?.value || !r?.move) return null;
  const down = r.moveColor === 'red', m = String(r.move);
  const num = parseFloat(m);
  const moveText = /bp$/.test(m) ? m : isFinite(num) ? pct(num) : m;
  return { k: t, t, v: String(r.value), m: `${down ? '▼' : '▲'} ${moveText}`, c: down ? C.red : C.green };
}

export function buildStrip(tab: Tab, current: boolean, doc: J, payload: J, privacyHeadline: boolean): Strip {
  const cards = allCards(doc);
  const ix = cards.find((c) => INDEX_TYPES.has(c?.type));
  const rates = cards.find((c) => c?.type === 'overnight' || c?.type === 'worldThisWeek');
  const ixCols = (Array.isArray(ix?.cards) ? ix.cards : []).map(fromIndexCard).filter(Boolean) as Col[];
  const row = (name: string, t: string) => {
    const r = (Array.isArray(rates?.rows) ? rates.rows : []).find((x: J) => x?.name === name);
    return r ? fromRow(r, t) : null;
  };
  const tenY = row('10y yield', '10Y'), dxy = row('Dollar', 'DXY');
  let vol = ixCols.find((c) => c.t === 'VIX') ?? null;
  // The overnight brief's futures cards carry no VIX: the live one is Home's own index quote.
  if (!vol && current) {
    const q = (Array.isArray(payload?.indices) ? payload.indices : []).find((x: J) => x?.label === 'VIX');
    if (q && isFinite(+q.price) && isFinite(+q.change_pct)) vol = { k: 'VIX', t: 'VIX', v: (+q.price).toFixed(2), ...mv(+q.change_pct) };
  }
  const stocks = ixCols.filter((c) => c.t !== 'VIX');

  let lead: Col[] = stocks;
  if (tab === 'pre' && current && Array.isArray(payload?.futures) && payload.futures.length) {
    const fut = (payload.futures as J[]).map((f) => {
      const p = +f?.price, b = +f?.base;
      if (!f?.pill || !isFinite(p) || !isFinite(b) || !b) return null;
      return { k: f.pill, t: f.pill, v: lvl(p), ...mv((p / b - 1) * 100) } as Col;
    }).filter(Boolean) as Col[];
    if (fut.length) lead = fut;
  }
  const cols = [...lead.slice(0, 3), tenY, vol, dxy].filter(Boolean) as Col[];

  const footer: string = String(ix?.footer ?? '');
  let kicker: string;
  if (tab === 'pre') kicker = 'Futures · implied at the open';
  else if (tab === 'open') {
    const when = !current ? String(doc?.dayCaption?.clock ?? '') : footer === 'Live' || !footer ? 'now' : footer.replace(/^As of /, '');
    kicker = `The market · ${when || 'now'}`;
  } else if (tab === 'post') {
    const at = /(\d{1,2}:\d{2} [AP]M)/.exec(footer)?.[1] ?? '4:00 PM';
    kicker = `The close · ${at}`;
  } else {
    const wk = /Week of (.+?)(?: ·|$)/.exec(footer)?.[1] ?? /The week of (.+)$/.exec(String(doc?.dayCaption?.caption ?? ''))?.[1];
    kicker = wk ? `The week · ${wk}` : 'The week';
  }

  // README 5: when the brief's first section holds nothing but index cards, its headline moves up here.
  const s1 = Array.isArray(doc?.sections) ? doc.sections[0] : null;
  const onlyIx = !!s1 && Array.isArray(s1.cards) && s1.cards.length > 0 && s1.cards.every((c: J) => INDEX_TYPES.has(c?.type));
  const headline = onlyIx ? spansOf(privacyHeadline ? (s1.privacy?.headline ?? s1.headline) : s1.headline) : null;

  return { kicker, cols, headline: headline && headline.length ? headline : null };
}
