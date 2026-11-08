// ── README 12: the invariants, checked on every build (handoff 6 Nov 2026, Pass 2) ──
// The same number must read the same everywhere it shows. sunny-home runs these on the page it just built and
// keeps the failures in payload.brief.checks; invariants_test.ts runs them at every moment on a test book.
// Overview's halves (2, 3, 4, 5, 9 there) join when Overview is built.
//
//  1 Makes-the-most price: By name row = the names list (logo strip) = To decide card and headline = Positions
//    at the Friday stop, to the cent.
//  2 Past-its-best names: By name rows = the logo strip's dots; the count line says the same number.
//  3 Put cover: Your position's line = insurance puts x 100 / shares, capped at the shares, name by name.
//  5 To do: the orders count in the lede = the Tomorrow headline = Tomorrow's orders card; weekend sales likewise.
//  6 Book today: the lede's figure = the Your book headline (session) = Your results' Made today (post).
//  7 Weekend: the lede's yield = the Results card's yield.
//  8 Payback: the month headline's % = the Payback card's %.
//  9 Dividends: one amount per name and ex-date on every card that shows it.
// 10 The book on screen: every name on a book card is a name this book holds.
// 11 Privacy: no book money in the privacy lede or headlines (prices, with cents, stay).
// 12 Owners only: the copy without orders carries no order, no To decide and no Tomorrow's orders.

import { NameBook, type Leg } from '../_shared/book-engine.ts';

type Row = Record<string, any>;
export interface Check { id: number; what: string; detail: string }

const text = (s: unknown): string => (Array.isArray(s) ? s.map((x: Row) => String(x?.t ?? '')).join('') : String(s ?? ''));
const NUMW: Record<string, number> = { no: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10 };
const count = (w: string) => (/^\d+$/.test(w) ? Number(w) : NUMW[w.toLowerCase()] ?? NaN);
const cards = (doc: Row): Row[] => (doc?.sections ?? []).flatMap((s: Row) => s.cards ?? []);
const section = (doc: Row, kicker: string): Row | undefined => (doc?.sections ?? []).find((s: Row) => s.kicker === kicker);
/** A book amount: money without exactly two cents ($1,234, $12K, $1.2K). A price always has cents ($40.07). */
const MONEY = { test: (s: string) => [...s.matchAll(/\$\d[\d,]*(\.\d+)?([KM])?/g)].some((m) => m[2] || (m[1] ?? '').length !== 3) };

export interface CheckIn {
  brief: Row;            // payload.brief (position, names, moment)
  full: Row;             // the owners' page
  open: Row;             // the page without orders
  inputs?: Row | null;   // payload.brief_inputs (for Positions at the Friday stop and the put cover)
  orders: Row[];         // this week's To do rows
}

export function checkInvariants(x: CheckIn): Check[] {
  const out: Check[] = [];
  const fail = (id: number, what: string, detail: string) => out.push({ id, what, detail });
  const B = x.brief, rows: Row[] = B?.position?.rows ?? [], names: Row[] = B?.names ?? [];
  const byT = new Map(names.map((n) => [String(n.t), n]));
  const moment = String(x.full?.moment ?? B?.moment ?? '');

  // 1 · the makes-the-most price
  for (const r of rows) {
    const n = byT.get(String(r.id));
    if ((n?.fp ?? null) !== (r.fp ?? null)) fail(1, 'makes-the-most price', `${r.id}: By name ${r.fp}, names list ${n?.fp}`);
    if (r.fp != null && r.st === 2 && !String(r.line).includes(`$${Number(r.fp).toFixed(2)}`) && !String(r.line).startsWith('Already past'))
      fail(1, 'makes-the-most price', `${r.id}: row line "${r.line}" without $${r.fp}`);
  }
  const td = cards(x.full).find((c) => c.type === 'toDecide' && /makes the most at \$/.test(String(c.subtitle)));
  if (td) {
    const m = String(td.subtitle).match(/^(.*) makes the most at \$([\d.]+)/);
    const r = rows.find((y) => y.name === m?.[1]);
    if (!m || !r || Number(m[2]).toFixed(2) !== Number(r.fp).toFixed(2)) fail(1, 'makes-the-most price', `To decide "${td.subtitle}" vs By name ${r?.fp}`);
  }
  const tdHead = text(section(x.full, 'To decide')?.headline);
  for (const m of tdHead.matchAll(/(\w[\w ]*?) makes the most at \$([\d.]+)/g)) {
    const r = rows.find((y) => y.name === m[1]);
    if (!r || Number(m[2]).toFixed(2) !== Number(r.fp).toFixed(2)) fail(1, 'makes-the-most price', `To decide headline "${m[0]}" vs By name ${r?.fp}`);
  }
  if (x.inputs?.names) {
    for (const n of x.inputs.names as Row[]) {
      const r = rows.find((y) => y.id === n.t); if (!r || r.fp == null || r.fp === n.S0) continue;
      const st = n.stops?.[n.fridayStop]; if (!st) continue;
      const nb = new NameBook({ t: n.t, S0: n.S0, P0: n.P0, iv: n.iv, legs: n.legs as Leg[], divs: n.divs, r: x.inputs.r, noIv: !!n.noIv });
      const hi = n.S0 * 1.12 * 1.05;
      if (r.fp > hi) continue;   // past the Positions chart's search: it shows no line there
      const p = nb.turnsShort(st.tt, hi)?.price ?? null;
      if (p == null || p.toFixed(2) !== Number(r.fp).toFixed(2)) fail(1, 'makes-the-most price', `${n.t}: Home $${r.fp}, Positions at ${st.short} $${p}`);
    }
  }

  // 2 · past its best: the rows, the strip's dots and the count
  const sRows = rows.filter((r) => r.st === 2).map((r) => r.id).sort().join(',');
  const sDots = names.filter((n) => n.short).map((n) => n.t).sort().join(',');
  if (sRows !== sDots) fail(2, 'past-its-best names', `By name [${sRows}] vs strip dots [${sDots}]`);
  const cm = String(B?.position?.count ?? '').match(/^(\d+) past/);
  const nS = rows.filter((r) => r.st === 2).length;
  if (B?.position && (cm ? Number(cm[1]) : 0) !== nS) fail(2, 'past-its-best names', `count "${B.position.count}" vs ${nS} rows`);

  // 3 · put cover
  if (x.inputs?.names && B?.position) {
    let sh = 0, cv = 0;
    for (const n of x.inputs.names as Row[]) {
      const s = (n.legs as Leg[]).filter((l) => l.kind === 'shares').reduce((a, l) => a + l.q, 0);
      const ins = (n.legs as Leg[]).filter((l) => l.kind === 'ins').reduce((a, l) => a + l.q * 100, 0);
      sh += s; cv += Math.min(s, ins);
    }
    const want = sh > 0 ? `${Math.round(cv / sh * 100)}%` : '';
    if (sh > 0 && !String(B.position.cover).includes(` ${want}.`)) fail(3, 'put cover', `"${B.position.cover}" vs ${want}`);
  }

  // 5 · To do counts
  const nOrders = x.orders.length, nSells = x.orders.filter((o) => o.kind === 'sell' || o.kind === 'put').length;
  const lede = text(x.full?.lede);
  const lo = lede.match(/(\w+) orders? to place at the open/);
  if (moment === 'pre' && names.length && (lo ? count(lo[1]) : 0) !== nOrders) fail(5, 'To do', `pre lede "${lo?.[0]}" vs ${nOrders} orders`);
  if (moment === 'post') {
    const h = text(section(x.full, 'Tomorrow')?.headline).match(/^(\w+) orders? to place/);
    const card = cards(x.full).find((c) => c.type === 'tomorrowOrders');
    if ((h ? count(h[1]) : 0) !== nOrders) fail(5, 'To do', `Tomorrow headline vs ${nOrders} orders`);
    if (nOrders && (!card || parseInt(String(card.count)) !== nOrders || card.rows?.length !== nOrders)) fail(5, 'To do', `Tomorrow's orders card ${card?.count} vs ${nOrders}`);
  }
  if (moment === 'weekend' && names.length) {
    const lw = lede.match(/, and (\w+) sales? comes? \w+day/), hw = text((section(x.full, 'Next week') ?? section(x.full, 'Coming up'))?.headline).match(/^(\w+) sales? \w+day/);
    if ((lw ? count(lw[1]) : 0) !== nSells) fail(5, 'To do', `weekend lede sales ${lw?.[1]} vs ${nSells}`);
    if (nSells && (hw ? count(hw[1]) : 0) !== nSells) fail(5, 'To do', `Next week headline vs ${nSells} sales`);
  }

  // 6 · the book today
  const AMT = '(\\$[\\d,]*\\d(?:\\.\\d+)?[KM]?|[\\d.]*\\d%)';
  const ledeMoney = (l: unknown) => text(l).match(new RegExp(`Your book (?:is (?:up|down)|lost|made) ${AMT}`))?.[1];
  const headMoney = (l: unknown) => text(l).match(new RegExp(`^(?:Up|Down) ${AMT}`))?.[1];
  if (['bell', 'open', 'last20', 'last5'].includes(moment)) {
    const sb = section(x.full, 'Your book');
    const hm = headMoney(sb?.headline), hp = headMoney(sb?.privacy?.headline);
    if (ledeMoney(x.full?.lede) !== hm) fail(6, 'book today', `lede ${ledeMoney(x.full?.lede)} vs headline ${hm}`);
    if (ledeMoney(x.full?.privacy?.lede) !== hp) fail(6, 'book today', `privacy lede ${ledeMoney(x.full?.privacy?.lede)} vs headline ${hp}`);
  }
  if (moment === 'post') {
    const yr = cards(x.full).find((c) => c.type === 'yourResults');
    const made = (yr?.bySegment?.Today?.stats ?? []).find((s: Row) => s.label === 'Made')?.value;
    const lm = ledeMoney(x.full?.lede);
    if (lm != null && made != null && lm !== made) fail(6, 'book today', `post lede ${lm} vs Your results Made ${made}`);
  }

  // 7 · the weekend yield
  if (moment === 'weekend') {
    const ly = lede.match(/^(?:So far, a|A) ([\d.]+%) week/)?.[1];
    const rc = cards(x.full).find((c) => c.type === 'results');
    const sub = String(rc?.bySegment?.['This week']?.bigSub ?? '');
    if (ly && !sub.includes(`${ly} yield`)) fail(7, 'weekend yield', `lede ${ly} vs Results "${sub}"`);
  }

  // 8 · payback
  for (const s of x.full?.sections ?? []) {
    const m = text(s.headline).match(/: ([\d.]+%) of what you bought is (paid|given) back/);
    if (!m) continue;
    const pb = (s.cards ?? []).find((c: Row) => c.type === 'payback');
    if (pb && pb.big !== m[1]) fail(8, 'payback', `headline ${m[1]} vs card ${pb.big}`);
  }

  // 9 · dividends: one amount per name and ex-date
  const seen = new Map<string, string>();
  const note = (key: string, amt: string, where: string) => {
    const was = seen.get(key);
    if (was && was !== amt) fail(9, 'dividends', `${key}: ${was} vs ${amt} (${where})`); else seen.set(key, amt);
  };
  const walk = (v: unknown) => {
    if (Array.isArray(v)) { v.forEach(walk); return; }
    if (!v || typeof v !== 'object') return;
    const o = v as Row;
    // The amount in K and M since 8 Nov 2026 ($2.5K); a dividend a share keeps its cents ($0.41).
    if (o.title === 'Dividends' && o.line) { const m = text(o.line).match(/^Next: (.+?), ex \w+ (\w+ \d+), (\$[\d,.]*\d[KM]?)/); if (m) note(`${m[1]} ${m[2]}`, m[3], 'Dividends line'); }
    if (Array.isArray(o.text) && o.date) { const m = text(o.text).match(/^(.+?) goes ex-dividend · \$[\d.]+ a share, (\$[\d,.]*\d[KM]?)/); if (m) note(`${m[1]} ${String(o.date).replace(/^\w+ /, '')}`, m[2], 'Coming up'); }
    for (const k of Object.keys(o)) walk(o[k]);
  };
  walk(x.full?.sections);

  // 10 · only this book's names on the book's cards
  const held = new Set(names.map((n) => String(n.t)));
  for (const c of cards(x.full)) {
    if (c.type === 'whatsMoving') for (const r of c.rows ?? []) if (!held.has(String(r.ticker))) fail(10, 'the book on screen', `What's moving shows ${r.ticker}`);
    if (c.type === 'yourNames') {
      const yn = (c.pages ?? []).find((p: Row) => p.title === 'Your names');
      for (const tl of yn?.tiles ?? []) if (tl.ticker && !held.has(String(tl.ticker))) fail(10, 'the book on screen', `Your names shows ${tl.ticker}`);
    }
  }

  // 11 · privacy
  if (MONEY.test(text(x.full?.privacy?.lede))) fail(11, 'privacy', `privacy lede "${text(x.full.privacy.lede)}"`);
  for (const s of x.full?.sections ?? []) {
    const h = s.privacy?.headline ?? s.headline;
    if (MONEY.test(text(h))) fail(11, 'privacy', `${s.kicker} headline "${text(h)}"`);
  }

  // 12 · owners only
  const ol = text(x.open?.lede);
  if (/to place at the open|sales? comes? Monday/.test(ol)) fail(12, 'owners only', `open lede "${ol}"`);
  for (const c of cards(x.open)) if (c.type === 'toDecide' || c.type === 'tomorrowOrders') fail(12, 'owners only', `open copy has ${c.type}`);
  for (const s of x.open?.sections ?? []) for (const c of s.cards ?? []) if (c.type === 'remember' && (c.rows ?? []).some((r: Row) => /to place/.test(text(r.text)))) fail(12, 'owners only', 'open Remember has sales to place');

  return out;
}

// ── Overview's half (README 12: 2, 3, 4, 5, 9 across both books) ──
export interface OverviewSide { id: string; name: string; brief: Row | null; inputs: Row | null; orders: Row[] }
export function checkOverview(o: Row, books: OverviewSide[], divs: Row[] = []): Check[] {
  const out: Check[] = [];
  const fail = (id: number, what: string, detail: string) => out.push({ id, what, detail });
  const chk = (name: string) => (o?.checks ?? []).find((c: Row) => c.name === name);
  const chip = (name: string, who: string) => ((chk(name)?.chips ?? []) as string[]).find((c) => c.startsWith(`${who} `));
  for (const b of books) {
    const rows: Row[] = b.brief?.position?.rows ?? [];
    if (!rows.length) continue;
    // 2 · past its best: the Delta chip = that book's By name rows
    const nS = rows.filter((r) => r.st === 2).length, nT = rows.filter((r) => r.st === 1).length;
    const want = [nS ? `${nS} past ${nS === 1 ? 'its' : 'their'} best` : '', nT ? `${nT} thin` : ''].filter(Boolean).join(' · ') || 'all long';
    if (chip('Delta', b.name) !== `${b.name} ${want}`) fail(2, 'past-its-best names', `Overview "${chip('Delta', b.name)}" vs ${b.name}'s By name "${want}"`);
    // 3 · put cover: the Downside chip = that book's Your position line
    const cov = String(b.brief?.position?.cover ?? '').match(/ (\d+)%\./)?.[1];
    if (cov && chip('Downside', b.name) !== `${b.name} ${cov}%`) fail(3, 'put cover', `Overview "${chip('Downside', b.name)}" vs ${b.name}'s Your position ${cov}%`);
    // 4 · calls at work: sold calls / (shares / 100), capped at 100% a name, from the legs
    let sh = 0, cv = 0;
    const F = String(b.brief?.friday ?? '');
    for (const n of (b.inputs?.names ?? []) as Row[]) {
      const s = (n.legs as Row[]).filter((l) => l.kind === 'shares').reduce((a, l) => a + l.q, 0);
      const c = (n.legs as Row[]).filter((l) => l.kind === 'sc' && String(l.ex) <= F).reduce((a, l) => a - l.q * 100, 0);
      if (s > 0) { sh += s; cv += Math.min(s, c); }
    }
    if (sh > 0 && chip('Calls at work', b.name) !== `${b.name} ${Math.round(cv / sh * 100)}%`) fail(4, 'calls at work', `Overview "${chip('Calls at work', b.name)}" vs ${Math.round(cv / sh * 100)}% from ${b.name}'s legs`);
    // 5 · To do per account = that book's orders
    if (chip('To do', b.name) !== `${b.name} ${b.orders.length}`) fail(5, 'To do', `Overview "${chip('To do', b.name)}" vs ${b.orders.length} orders in ${b.name}'s`);
  }
  // 9 · dividends: Coming in = shares x per share, book by book
  if (o?.comingIn?.raw) {
    for (const b of books) {
      let a = 0;
      for (const n of (b.inputs?.names ?? []) as Row[]) {
        const s = (n.legs as Row[]).filter((l) => l.kind === 'shares').reduce((x, l) => x + l.q, 0);
        if (s > 0) for (const d of divs.filter((x) => String(x.ticker).toUpperCase() === n.t)) a += s * Number(d.cash_amount);
      }
      const got = (o.comingIn.raw as Row[]).find((r) => r.id === b.id)?.amount ?? 0;
      if (Math.round(a) !== got) fail(9, 'dividends', `Coming in ${b.name} ${got} vs ${Math.round(a)} from shares x per share`);
    }
  }
  return out;
}
