// The alert card's list (README 1, item 6): the phone's deck alerts, one card under the strip, paged.
// Which kinds per moment (the design): pre Aftershock, Earnings season, Holiday · open Earnings, Holiday ·
// post Aftershock, Earnings, Holiday · weekend Holiday, Earnings.
// The words are the server's (doc.deckCards: kicker, title, sub; Aftershock's by state, as BriefDeck picks them).
// The server writes Earnings season only outside pre and post; there the card is made from Home's earnings list
// with the server's own rule and words (doc.ts `season`: the next report within 14 days).
import type { J, Tab } from '../../lib/data';
import { C } from '../../lib/format';

export interface Alert { key: string; kind: string; kick: string; t: string; s: string; dot: string; linked: boolean }

const KINDS: Record<Tab, string[]> = {
  pre: ['aftershock', 'earningsSeason', 'holiday'], open: ['earningsSeason', 'holiday'],
  post: ['aftershock', 'earningsSeason', 'holiday'], weekend: ['holiday', 'earningsSeason'],
};
const DOT: Record<string, string> = { aftershock: C.orange, earningsSeason: C.blue, holiday: C.green };
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const NUM = ['No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten'];
const word = (n: number) => (n <= 10 ? NUM[n] : String(n));
const md = (d: string) => { const [, m, dd] = d.split('-').map(Number); return `${MON[m - 1]} ${dd}`; };
const dayDiff = (a: string, b: string) => Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 864e5);

/** doc.ts `season`, from Home's earnings list (held names) and the brief's company names. */
function season(payload: J, today: string): J | null {
  const list: J[] = Array.isArray(payload?.deck?.earnings) ? payload.deck.earnings : [];
  const ahead = list.filter((e) => String(e?.date ?? '') >= today).sort((a, b) => String(a.date).localeCompare(String(b.date)));
  if (!ahead.length || dayDiff(today, String(ahead[0].date)) > 14) return null;
  const names: J[] = Array.isArray(payload?.brief?.names) ? payload.brief.names : [];
  const company = (t: string) => names.find((n) => n?.t === t)?.name ?? t;
  return { kind: 'earningsSeason', kicker: 'Earnings season', title: `${word(ahead.length)} ${ahead.length === 1 ? 'name' : 'names'} still to report`,
    sub: ahead.slice(0, 3).map((e) => `${company(String(e.ticker))} ${md(String(e.date))}`).join(' · ') };
}

export function alertsFor(tab: Tab, doc: J, payload: J): Alert[] {
  const deck: J[] = Array.isArray(doc?.deckCards) ? doc.deckCards : doc?.alert ? [doc.alert] : [];
  const kinds = KINDS[tab];
  const list = deck.filter((a) => a && kinds.includes(a.kind));
  if (kinds.includes('earningsSeason') && !list.some((a) => a.kind === 'earningsSeason') && doc?.built_for) {
    const s = season(payload, String(doc.built_for));
    if (s) list.push(s);
  }
  list.sort((a, b) => kinds.indexOf(a.kind) - kinds.indexOf(b.kind));
  return list.map((a) => {
    let t = String(a.title ?? ''), s = String(a.sub ?? '');
    if (a.kind === 'aftershock') {
      // BriefDeck: near the close it counts down, after the close it reports the scan, else it waits for 4:15.
      const key = doc?.moment === 'last20' || doc?.moment === 'last5' ? 'soon' : doc?.moment === 'post' ? 'done' : 'wait';
      const st: J[] = Array.isArray(a.states?.[key]) ? a.states[key] : [];
      t = String(st[0] ?? a.kicker ?? 'Aftershock'); s = String(st[1] ?? '');
    }
    return { key: `${tab}|${a.kind}`, kind: a.kind, kick: String(a.kicker ?? ''), t, s, dot: DOT[a.kind] ?? C.ink3, linked: a.kind !== 'aftershock' };
  }).filter((a) => a.t);
}
