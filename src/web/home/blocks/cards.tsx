// Every brief card that sits in a section's two-column grid, by its type (the phone's BriefCardView switch),
// drawn with the design's card blocks. Money in the server's words is written in K and M (tidy) and hidden with
// privacy (mask); market numbers stay.
import { useState, type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePrefetchTicker, type J } from '../../lib/data';
import { useWeb } from '../../lib/state';
import { C, clean, named, pct } from '../../lib/format';
import { Bars, Big, Caption, Card, Line, MapTiles, Rows, Stats, Text, Words, type Bar, type MapTile, type Row, type Stat } from './Card';
import { move, plain, pmove, spans, tidy, type Mo } from './util';

export interface Ctx {
  mo: Mo;
  mask: (s: string) => string;
  /** payload.brief.position: Your position from the one book engine. */
  position: J;
  /** Ticker to company name, from the brief's names. */
  company: Record<string, string>;
}

/** The book's money in a server string: K and M, then hidden with privacy. */
const bm = (cx: Ctx, s: unknown) => cx.mask(tidy(s == null ? '' : String(s)));
const col = (c: string | null | undefined, fb: string = C.ink) => (c ? named(c, fb) : fb);
const cap1 = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);

/** The grid cards one doc card becomes (Your names and the watchlist are two). */
export function gridCards(card: J, cx: Ctx, key: string): ReactNode[] {
  switch (card.type) {
    case 'yourNames': return (card.pages ?? []).map((p: J, i: number) => <NamesMap key={key + i} page={p} cx={cx} />);
    case 'yourPosition': return [<YourPosition key={key} card={card} cx={cx} />];
    case 'whatsMoving': return [<WhatsMoving key={key} card={card} cx={cx} />];
    case 'toDecide': return [<ToDecide key={key} card={card} cx={cx} />];
    case 'comingUp': case 'remember': return [<Dated key={key} card={card} cx={cx} />];
    case 'yourResults': case 'results': return [<Results key={key} card={card} cx={cx} />];
    case 'tomorrowOrders': return [<Orders key={key} card={card} cx={cx} />];
    case 'thetaMonth': return [<Theta key={key} card={card} cx={cx} />];
    case 'payback': return [<Payback key={key} card={card} cx={cx} />];
    // Performance (10 Nov 2026): this month's realized, a bar per month, this month's names; the payback card's shape.
    case 'performance': return [<Payback key={key} card={card} cx={cx} />];
    case 'earningsAhead': return [<EarningsAhead key={key} card={card} cx={cx} />];
    case 'closedRolled': return [<ClosedRolled key={key} card={card} cx={cx} />];
    default: return [<Generic key={key} card={card} cx={cx} />];
  }
}

/* ── Your names and the watchlist: flex tiles sized by weight; a tile opens its ticker page ── */
function NamesMap({ page, cx }: { page: J; cx: Ctx }) {
  const navigate = useNavigate();
  const pre = usePrefetchTicker(useWeb().book);
  const watch = page.kind === 'watchlist';
  const mv = move(page.move, page.moveColor, page.moveSigned);
  const when = cx.mo === 'pre' ? 'Before the bell' : cx.mo === 'weekend' ? 'The week' : 'Today';
  const tiles: MapTile[] = (page.tiles ?? []).map((x: J) => {
    const t = clean(x.ticker), p = +x.move || 0, m = pmove(p);
    return { k: t, t, m, p, g: Math.max(1, +x.weight || 1), aria: `${clean(x.name) || t} ${m}`, go: () => navigate('/t/' + t, { state: { from: 'home' } }), pre: () => pre(t) };
  });
  return (
    <Card title={clean(page.title)} sub={watch ? 'by market cap' : `${when} ${mv.t}`}>
      <MapTiles tiles={tiles} />
    </Card>
  );
}

/* ── Your position: the book by Friday if the whole market moves together ── */
function YourPosition({ card, cx }: { card: J; cx: Ctx }) {
  const navigate = useNavigate();
  const m = cx.position;
  const ok = !card.empty && m && Array.isArray(m.grid) && Array.isArray(m.friday) && m.grid.length === m.friday.length && m.grid.length > 1;
  if (!ok) {
    return (
      <Card title="Your position" sub={clean(card.subtitle) || 'Nothing held yet'} wide>
        <Text>Once shares or options are in the book, this shows where it stands by Friday’s close if the whole market moves together.</Text>
      </Card>
    );
  }
  const f: number[] = m.friday.map(Number);
  const hi = Math.max(0, ...f), lo = Math.min(0, ...f), pad = (hi - lo) * 0.08 || 1;
  const y = (v: number) => (hi + pad - v) / (hi - lo + 2 * pad) * 100;
  const stats: Stat[] = (m.stats ?? []).map((s: J) => {
    const l = clean(s.l).replace(/^if\s+/i, '');
    return { l: cap1(l), v: bm(cx, s.v), c: col(s.c) };
  });
  const rows: Row[] = (m.rows ?? []).map((r: J) => ({
    k: r.id, l: clean(r.name), s: bm(cx, r.line), sc: col(r.lineColor, C.ink2), v: clean(r.right), c: col(r.rightColor),
    go: () => navigate('/positions/' + r.id), aria: `${clean(r.name)}, ${clean(r.line)}, ${clean(r.right)}. Opens Positions`,
  }));
  const short = m.shortAt != null && isFinite(+m.shortAt) ? ` · makes the most at ↑${(+m.shortAt).toFixed(1)}%` : '';
  return (
    <Card title="Your position" sub={clean(card.subtitle ?? m.subtitle)} wide aria="Your position">
      {stats.length ? <Stats stats={stats} /> : null}
      <Line pts={f.map(y)} z={y(0)} cap={'↓10% · today · ↑10%' + short} />
      {m.sentence ? <Text><Words runs={spans(m.sentence).map((r) => ({ ...r, t: tidy(r.t) }))} mask={cx.mask} /></Text> : null}
      {rows.length ? <Rows rows={rows} /> : null}
    </Card>
  );
}

/* ── What's moving: each name's move against the move priced for today ── */
function WhatsMoving({ card, cx }: { card: J; cx: Ctx }) {
  const rows: Row[] = (card.rows ?? []).map((r: J) => {
    const t = clean(r.ticker), mv = +r.movePct || 0;
    return {
      k: t, l: cx.company[t] ?? t,
      s: r.pricedPct != null ? `Priced to move ${pct(+r.pricedPct)} today` : undefined,
      v: pmove(mv), c: col(r.moveColor),
    };
  });
  return (
    <Card title={clean(card.title)} sub={clean(card.subtitle)}>
      {card.body ? <Text>{bm(cx, plain(card.body))}</Text> : null}
      <Rows rows={rows} />
    </Card>
  );
}

/* ── To decide ── */
function ToDecide({ card, cx }: { card: J; cx: Ctx }) {
  return (
    <Card title={clean(card.title)} sub={bm(cx, card.subtitle)} wide>
      {card.body ? <Text><Words runs={spans(card.body).map((r) => ({ ...r, t: tidy(r.t) }))} mask={cx.mask} /></Text> : null}
      {card.footer ? <Text><Words runs={spans(card.footer).map((r) => ({ ...r, t: tidy(r.t) }))} mask={cx.mask} /></Text> : null}
      {Array.isArray(card.rows) && card.rows.length ? <Rows rows={genericRows(card.rows, cx)} /> : null}
    </Card>
  );
}

/* ── Coming up and Remember for next week: a date over what happens, or one line ── */
function Dated({ card, cx }: { card: J; cx: Ctx }) {
  const rows: Row[] = (card.rows ?? []).map((r: J, i: number) => ({ k: String(i), l: clean(r.date), s: bm(cx, plain(r.text)) }));
  return (
    <Card title={clean(card.title)} sub={clean(card.subtitle)}>
      {card.line ? <Text><Words runs={spans(card.line).map((r) => ({ ...r, b: false, t: tidy(r.t) }))} mask={cx.mask} /></Text> : null}
      {rows.length ? <Rows rows={rows} /> : null}
    </Card>
  );
}

/* ── Results and Your results: a range switch, the big number, three stats, dividends, the week's bars ── */
function Results({ card, cx }: { card: J; cx: Ctx }) {
  const segs: string[] = (card.segments ?? []).map(String);
  const [pick, setPick] = useState<string>(card.selected ?? segs[0] ?? '');
  const s: J = card.bySegment?.[pick] ?? card.bySegment?.[card.selected] ?? {};
  const stats: Stat[] = (s.stats ?? []).map((x: J) => ({ l: clean(x.label), v: bm(cx, x.value), u: bm(cx, x.sub), c: col(x.valueColor) }));
  const dv = s.dividends;
  const none = /^none/i.test(clean(dv?.right));
  const flat = (s.charts ?? []).filter((c: J) => Array.isArray(c.bars) && c.bars.length);
  const paired = (s.charts ?? []).find((c: J) => Array.isArray(c.groups) && c.groups.length);
  const body = card.type === 'yourResults' ? plain(s.body) : '';
  const sub = segs.length > 1 ? (
    <span role="radiogroup" aria-label={clean(card.title) + ' range'}>
      {segs.map((g, i) => (
        <span key={g}>
          {i ? ' | ' : ''}
          <button type="button" role="radio" aria-checked={g === pick} className="bare swb-seg" onClick={() => setPick(g)}
            style={{ color: g === pick ? C.ink : C.ink2 }}>{g}</button>
        </span>
      ))}
    </span>
  ) : clean(segs[0]);
  return (
    <Card title={clean(card.title)} sub={sub} wide={card.type === 'results'}>
      {s.big ? <Big v={bm(cx, s.big)} c={col(s.bigColor)} sub={bm(cx, s.bigSub)} /> : null}
      {stats.length ? <Stats stats={stats} /> : null}
      {paired?.title ? <Text>{bm(cx, paired.title)}</Text> : null}
      {body ? <Text>{bm(cx, body)}</Text> : null}
      {dv ? <Rows rows={[{ l: clean(dv.title) || 'Dividends', s: bm(cx, plain(dv.line)), v: bm(cx, dv.right), c: none ? C.ink : col(dv.rightColor) }]} /> : null}
      {flat.map((c: J, i: number) => (
        <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <Bars bars={(c.bars as J[]).map((b, j) => barOf(b, j, cx))} />
          {c.title ? <Caption>{bm(cx, [c.title, c.sub].filter(Boolean).join(' · '))}</Caption> : null}
        </div>
      ))}
    </Card>
  );
}

const barOf = (b: J, j: number, cx: Ctx): Bar => ({
  k: String(j), l: clean(b.label), v: bm(cx, b.value), cur: !!b.highlight,
  h: Math.abs(b.signed ?? b.n ?? parseFloat(String(b.value ?? '').replace(/[^\d.]/g, '')) ?? 0) || 0,
  vc: b.valueColor && b.valueColor !== 'ink' ? col(b.valueColor) : C.ink,
});

/* ── Tomorrow's orders ── */
function Orders({ card, cx }: { card: J; cx: Ctx }) {
  const rows: Row[] = (card.rows ?? []).map((r: J, i: number) => {
    const cr = r.amountLabel === 'credit';
    return { k: String(i), l: clean(r.order), s: clean(r.why), v: bm(cx, r.amount) + (r.amountLabel ? (cr ? ' in' : ' out') : ''), c: cr ? C.green : C.ink };
  });
  return (
    <Card title={clean(card.title)} sub={clean(card.count)}>
      {card.subtitle ? <Text>{bm(cx, card.subtitle)}</Text> : null}
      <Rows rows={rows} />
      {card.footer ? <Caption>{bm(cx, plain(card.footer))}</Caption> : null}
    </Card>
  );
}

/* ── Theta · month: collected over paid in decay, week by week ── */
function Theta({ card, cx }: { card: J; cx: Ctx }) {
  const bars: Bar[] = (card.weeks ?? []).map((w: J, j: number) => ({
    k: String(j), l: clean(w.label), v: clean(w.ratio), cur: !!w.highlight, h: parseFloat(String(w.ratio ?? '').replace(/[^\d.]/g, '')) || 0,
  }));
  return (
    <Card title={clean(card.title)} sub={clean(card.subtitle)}>
      {card.body ? <Text>{bm(cx, plain(card.body))}</Text> : null}
      {bars.length ? <Bars bars={bars} /> : null}
    </Card>
  );
}

/* ── Payback ── */
function Payback({ card, cx }: { card: J; cx: Ctx }) {
  const rows: Row[] = (card.rows ?? []).map((r: J, i: number) => ({
    k: String(i), l: bm(cx, r.label), s: r.sub ? bm(cx, r.sub) : undefined, v: bm(cx, [r.value, r.valueSub].filter(Boolean).join(' ')), c: col(r.valueColor),
  }));
  const ch = card.chart;
  return (
    <Card title={clean(card.title)} sub={clean(card.subtitle)}>
      {card.big ? <Big v={bm(cx, card.big)} c={col(card.bigColor)} sub={bm(cx, card.bigSub)} /> : null}
      {rows.length ? <Rows rows={rows} /> : null}
      {ch?.bars?.length ? <Bars bars={(ch.bars as J[]).map((b, j) => barOf(b, j, cx))} /> : null}
      {ch?.title ? <Caption>{bm(cx, ch.title)}</Caption> : null}
      {card.footer ? <Caption>{bm(cx, plain(card.footer))}</Caption> : null}
    </Card>
  );
}

/* ── Earnings ahead ── */
function EarningsAhead({ card, cx }: { card: J; cx: Ctx }) {
  const stats: Stat[] = (card.stats ?? []).map((s: J) => ({ l: clean(s.label), v: bm(cx, s.value) }));
  const notes = (card.notes ?? []).map((n: J) => bm(cx, plain(n.text))).filter(Boolean);
  return (
    <Card title={clean(card.title)} sub={clean(card.subtitle)}>
      {stats.length ? <Stats stats={stats} /> : null}
      {notes.length ? <Text>{notes.join(' ')}</Text> : null}
      {card.name ? <Rows rows={[{ l: clean(card.name), s: clean(card.when) }]} /> : null}
    </Card>
  );
}

/* ── Closed and rolled today ── */
function ClosedRolled({ card, cx }: { card: J; cx: Ctx }) {
  const rows: Row[] = (card.rows ?? []).map((r: J, i: number) => ({ k: String(i), l: clean(r.title), s: bm(cx, r.sub), v: bm(cx, r.value), c: col(r.valueColor) }));
  return (
    <Card title={clean(card.title)} sub={bm(cx, card.subtitle)}>
      <Rows rows={rows} />
      {card.footer ? <Caption>{bm(cx, plain(card.footer))}</Caption> : null}
    </Card>
  );
}

/* ── Any other card: its title and sub line, words, rows and footer, so nothing in it goes missing ── */
function genericRows(rows: J[], cx: Ctx): Row[] {
  return rows.map((r: J, i: number) => {
    if (Array.isArray(r)) return { k: String(i), l: bm(cx, plain(r[0])), s: r.length > 2 ? bm(cx, plain(r[1])) : undefined, v: r.length > 1 ? bm(cx, plain(r[r.length - 1])) : undefined };
    if (r && typeof r === 'object') {
      return {
        k: String(i), l: bm(cx, plain(r.label ?? r.name ?? r.date ?? r.t ?? r.title ?? r.order ?? '')),
        s: (r.sub ?? r.line ?? r.text ?? r.what ?? r.why) != null ? bm(cx, plain(r.sub ?? r.line ?? r.text ?? r.what ?? r.why)) : undefined,
        v: bm(cx, plain(r.value ?? r.amount ?? r.v ?? r.right ?? '')), c: col(r.valueColor ?? r.rightColor),
      };
    }
    return { k: String(i), l: bm(cx, String(r ?? '')) };
  });
}

function Generic({ card, cx }: { card: J; cx: Ctx }) {
  const body = card.body ?? card.text ?? card.line;
  return (
    <Card title={clean(card.title ?? card.label)} sub={bm(cx, card.subtitle ?? card.sub)}>
      {body ? <Text><Words runs={spans(body).map((r) => ({ ...r, t: tidy(r.t) }))} mask={cx.mask} /></Text> : null}
      {Array.isArray(card.rows) && card.rows.length ? <Rows rows={genericRows(card.rows, cx)} /> : null}
      {card.footer ? <Caption>{bm(cx, plain(card.footer))}</Caption> : null}
    </Card>
  );
}
