// Positions (handoff 2026-11-13-positions, Web Dark v2's Positions page), top to bottom:
//   1 the title and the book on screen · 2 Book totals (five cells, D7; whole book and the name) · 3 the name strip
//   with the Sold, in SD box · 4 Sold, in SD (folded) · 5 the name header · 6 the band: Price | Payoff and What if,
//   one height · 7 Every leg · 8 Intelligence (a capsule that opens into the full window).
// /positions opens the name that needs a look first (Home's position rows), /positions/:t opens that name.
//
// Data, real only:
//   Home's snapshot (useHome): the names (brief.names: the strip, st for the red dot), the legs Home priced
//     (brief_inputs: Book totals, Sold in SD), the calendar and the marks' time.
//   sunny-positions (usePositions): the name's grid of P&L by price and date (Payoff, Greeks, Every leg, What if).
//   sunny-chart (useTicker): the name's daily closes for the Price chart.
//   sunny-sd (useSd): the name's chain, the rule and the levels for Intelligence; the other names' replies only once
//     Sold in SD is opened (their SD when sold).
// The maths is supabase/functions/_shared/positions-engine.ts (shared with the phone), book-engine.ts and sd-engine.ts.
import { useEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { nameDot, soldInSd, stepOf } from '../../../supabase/functions/_shared/positions-engine.ts';
import { BOOK_NAME } from '../components/AccountMenu';
import { clock12, ny, shortDate } from '../lib/clock';
import { useHome, usePositions, usePrefetchPositions, useSd, useSdMany, useTicker, type J } from '../lib/data';
import { arrow, pct, price } from '../lib/format';
import { useWeb } from '../lib/state';
import type { PCRange } from '../../../supabase/functions/_shared/price-chart.ts';
import { Payoff, PriceChart, rangeWords } from '../positions/Band';
import { BookTotals } from '../positions/BookTotals';
import { EveryLeg, type LegFilter } from '../positions/EveryLeg';
import { Intelligence } from '../positions/Intelligence';
import { pickExpiry, requestIntelScroll, setIntelOpen, useIntelOpen, type SdReply } from '../positions/intel';
import { PosModel, Pricer, expLabel, type GridW, type Inputs, type PLeg, type Seg } from '../positions/model';
import { SoldCapsule, SoldCard, closedDays, soldLegs } from '../positions/SoldInSd';
import { bookTotals, nameTotals } from '../positions/totals';
import { G, K, MU, O, PosStyles, R, Segmented } from '../positions/ui';
import { WhatIf } from '../positions/WhatIfPanel';
import { useWhatIf, type Draft } from '../positions/whatif';

/** "Fri Nov 6 close" for marks taken at or after the close (or on an earlier day), else "Mon Nov 9 · 11:42 AM ET". */
const asOf = (iso: string | undefined) => {
  if (!iso) return '';
  const n = ny(new Date(iso)), today = ny();
  return n.date < today.date || n.mins >= 16 * 60 ? `${shortDate(n.date)} close` : `${shortDate(n.date)} · ${clock12(n)} ET`;
};

export default function Positions() {
  const { t: tParam } = useParams();
  const nav = useNavigate();
  const loc = useLocation();
  const { book, mask } = useWeb();
  const home = useHome(book);
  const payload: J = home.data?.payload;
  const brief: J = payload?.brief;
  const names: J[] = useMemo(() => brief?.names ?? [], [brief]);
  // The name that needs a look first opens /positions: Home's position rows (short first, then thin).
  const first: string | null = useMemo(() => {
    const rows: J[] = brief?.position?.rows ?? [], held = new Set(names.map((n) => n.t));
    return rows.map((r) => r.id).find((id: string) => held.has(id)) ?? [...names].sort((a, b) => (b.st ?? 0) - (a.st ?? 0))[0]?.t ?? null;
  }, [brief, names]);
  const want = (tParam ?? '').toUpperCase();
  const t = names.some((n) => n.t === want) ? want : null;
  useEffect(() => {
    if (names.length && !t && first) nav(`/positions/${first}${loc.search}`, { replace: true });
  }, [names.length, t, first, nav, loc.search]);
  const order = useMemo(() => names.map((n) => String(n.t)), [names]);
  const ahead = useMemo(() => { const i = Math.max(0, order.indexOf(t ?? '')); return [...order.slice(i + 1), ...order.slice(0, i)]; }, [order, t]);
  usePrefetchPositions(book, ahead, !!t);

  const nt = useMemo(() => nameTotals(payload), [payload]);
  const bt = useMemo(() => bookTotals(nt), [nt]);

  // Sold, in SD: rows from Home's legs at once; each name's SD when sold once the card is opened.
  const [sdo, setSdo] = useState(false);
  const soldNames = useMemo(() => [...new Set(soldLegs(payload, new Map()).map((l) => l.t))], [payload]);
  const sdMany = useSdMany(book, soldNames, sdo) as Map<string, SdReply | undefined>;
  const sold = useMemo(() => soldInSd(soldLegs(payload, sdMany)), [payload, sdMany]);
  useEffect(() => {
    if (!sdo) return;
    const f = (ev: KeyboardEvent) => { if (ev.key === 'Escape') setSdo(false); };
    window.addEventListener('keydown', f);
    return () => window.removeEventListener('keydown', f);
  }, [sdo]);
  const go = (x: string) => nav(`/positions/${x}${loc.search}`);
  // A row tap: that name, Intelligence open on that expiry, scrolled into view.
  const onPick = (x: string, ex: string) => {
    if (book) pickExpiry(book, x, ex);
    setIntelOpen(true);
    requestIntelScroll();
    if (x !== t) go(x);
  };
  const subtitle = book ? `${BOOK_NAME[book]}’s book${payload ? ' · ' + asOf(payload.fresh?.marks) : ''}` : '';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
      <PosStyles />
      <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'baseline', gap: '12px 14px' }}>
        <h1 style={{ margin: 0, fontSize: 42, lineHeight: '48px', fontWeight: 700, letterSpacing: '-.03em' }}>Positions</h1>
        <span style={{ fontSize: 15, color: MU }}>{subtitle}</span>
      </div>
      {payload && !names.length && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{ fontSize: 20, fontWeight: 700 }}>Nothing held yet</span>
          <span style={{ fontSize: 13, color: MU }}>Each name you hold shows here once IBKR reports it.</span>
        </div>
      )}
      {names.length > 0 && <BookTotals book={bt} name={t ? nt.get(t) ?? null : null} t={t} mask={mask} />}
      {names.length > 0 && (
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16, flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {names.map((n) => {
              const on = n.t === t, dot = nameDot(n.st, sold.rows, n.t);
              return (
                <button key={n.t} type="button" className="bare" onClick={() => go(n.t)} aria-current={on ? 'true' : undefined}
                  aria-label={`${n.name ?? n.t}${dot === 'red' ? ', short at the priced move by Friday' : dot === 'orange' ? ', a sold leg within 0.5 SD' : ''}`}
                  style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, width: 70 }}>
                  <span style={{ position: 'relative', width: 50, height: 50, borderRadius: '50%', background: 'rgba(255,255,255,.07)',
                    border: on ? '3px solid #F5F5F7' : '1.5px solid rgba(255,255,255,.2)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 700 }}>
                    {n.t}
                    {dot && <span style={{ position: 'absolute', right: 0, top: 0, width: 11, height: 11, borderRadius: '50%', background: dot === 'red' ? R : O, boxShadow: '0 0 0 2px #050706' }} />}
                  </span>
                  <span style={{ fontSize: 13, fontWeight: on ? 700 : 400, color: on ? K : MU }}>{n.t}</span>
                </button>
              );
            })}
          </div>
          <SoldCapsule rows={sold.rows} open={sdo} toggle={() => setSdo(!sdo)} />
        </div>
      )}
      {sold.rows.length > 0 && <SoldCard rows={sold.rows} within={sold.within} inTheMoney={sold.inTheMoney} open={sdo} close={() => setSdo(false)} onPick={onPick} />}
      {t && book && <Name key={book} book={book} t={t} name={names.find((n) => n.t === t)} payload={payload} />}
    </div>
  );
}

/* ── One name: the header, then everything that reads its grid ──────────── */
function Name({ book, t, name, payload }: { book: 'S' | 'N'; t: string; name: J; payload: J }) {
  const { mask } = useWeb();
  const q = usePositions(book, t, payload?.built_at);
  const grid = q.data as GridW | undefined;
  const ready = !!grid && grid.t === t && grid.stops?.length > 0 && grid.S?.length > 1;
  // ⚠ SMOOTH SWITCHING (Nik, 9 Nov 2026): while the next name's grid is on its way the last name stays on screen,
  // dimmed, so the page never collapses.
  const last = useRef<{ t: string; grid: GridW } | null>(null);
  if (ready) last.current = { t, grid: grid! };
  const shown = ready ? { t, grid: grid! } : last.current;
  const S0 = ready ? grid!.S0 : +name?.S0 || 0, P0 = ready ? grid!.P0 : +name?.P0 || S0, mv = P0 ? (S0 / P0 - 1) * 100 : 0;
  const strat = String(name?.strategy ?? ''), company = String(name?.name ?? t);
  return (
    <>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12, paddingTop: 4, flexWrap: 'wrap' }}>
        <span className="tnum" style={{ whiteSpace: 'nowrap' }}>
          <span style={{ fontSize: 30, fontWeight: 700, letterSpacing: '-.02em' }}>{t}</span>{' '}
          <span style={{ fontSize: 22, color: MU }}>{price(S0)}</span>{' '}
          <span style={{ fontSize: 16, fontWeight: 600, color: mv < 0 ? R : G }}>{arrow(mv)} {pct(mv)}</span>
        </span>
        <span style={{ fontSize: 15, color: MU }}>{company}{strat ? ' · ' + strat.charAt(0).toUpperCase() + strat.slice(1) : ''}</span>
      </div>
      {shown ? (
        <div aria-busy={!ready} style={{ display: 'flex', flexDirection: 'column', gap: 28, opacity: ready ? 1 : 0.55, transition: 'opacity .2s', pointerEvents: ready ? 'auto' : 'none' }}>
          {!ready && q.isError && <span style={{ fontSize: 13, color: MU }}>Could not load {t}.</span>}
          <Detail book={book} t={shown.t} grid={shown.grid} payload={payload} mask={mask} />
        </div>
      ) : q.isError ? <span style={{ fontSize: 13, color: MU }}>Could not load {t}.</span> : <div style={{ minHeight: 600 }} />}
    </>
  );
}

// The page's own state, kept across names and rebuilds: the date, Price or Payoff, Chart or Table, the range, the
// Every leg filter.
const pageState = { day: null as string | null, view: 'price' as 'price' | 'pay', tab: 'chart' as 'chart' | 'table', rg: '1W' as PCRange, lf: 'all' as LegFilter };
function usePageState<K extends keyof typeof pageState>(k: K): [(typeof pageState)[K], (v: (typeof pageState)[K]) => void] {
  const [v, setV] = useState(pageState[k]);
  return [v, (x) => { pageState[k] = x; setV(x); }];
}

function Detail({ book, t, grid, payload, mask }: { book: 'S' | 'N'; t: string; grid: GridW; payload: J; mask: (s: string) => string }) {
  const inputs: Inputs | null = payload?.brief_inputs ?? null;
  const m = useMemo(() => new PosModel(grid, inputs), [grid, inputs]);
  const wf = useWhatIf(book, t);
  const pr = useMemo(() => new Pricer(m, wf.trades), [m, wf.trades]);
  const S0 = m.S0;
  const [view, setView] = usePageState('view');
  const [tab, setTab] = usePageState('tab');
  const [rg, setRg] = usePageState('rg');
  const [lf, setLf] = usePageState('lf');
  const [day, setDay] = usePageState('day');
  const chart = useTicker(t, book);
  const sdQ = useSd(book, t);
  const sd = sdQ.data as SdReply | undefined;
  const intelOpen = useIntelOpen();

  // The date: this Friday unless one is picked (kept by its day across names and rebuilds).
  const segs = useMemo(() => m.segments(), [m]);
  const seg = segs.find((s) => s.key === day) ?? segs.find((s) => s.i === m.fridayStop) ?? segs[segs.length - 1];
  const pick = (s: Seg) => setDay(s.key);
  const dLong = (s: Seg) => m.stops[s.i]?.long.replace(/ close$/, '') ?? s.label;

  // The switches (Nik, 13 Nov 2026: "by default only keep income on and rest off", every name): a leg sold starts on,
  // shares and legs bought start off; `flip` holds the legs switched away from that. Payoff, its Greeks and Every leg
  // follow the switches. What if and Intelligence count only real changes (Nik: "Only what I flip"): an income leg
  // switched off is closed there (bought back); a leg bought or the shares switched on is already held, no change.
  const base = m.legs;
  const flip = useMemo(() => new Set(wf.flip.filter((k) => base.some((l) => l.k === k))), [wf.flip, base]);
  const startsOn = (l: PLeg) => l.q < 0;
  const viewOff = useMemo(() => new Set(base.filter((l) => startsOn(l) === flip.has(l.k)).map((l) => l.k)), [base, flip]);
  const shut = useMemo(() => new Set(base.filter((l) => startsOn(l) && flip.has(l.k)).map((l) => l.k)), [base, flip]);
  const tradesOn = useMemo(() => pr.trades.filter((l) => wf.trades.find((u) => u.id === l.trade)?.on), [pr, wf.trades]);
  const wi: PLeg[] = useMemo(() => [...base.filter((l) => !viewOff.has(l.k)), ...tradesOn], [base, viewOff, tradesOn]);
  const start: PLeg[] = useMemo(() => base.filter(startsOn), [base]);
  const nCh = shut.size + tradesOn.length, viewChg = flip.size + tradesOn.length > 0;
  const cashC = base.filter((l) => shut.has(l.k)).reduce((a, l) => a + l.value, 0) + tradesOn.reduce((a, l) => a - l.value, 0);

  // Try a trade: strikes 85% to 120% of the price on the chain's step, the name's expiries, 10 (3 on Nicolay's book).
  const stp = stepOf(S0);
  const strikes = useMemo(() => { const o: number[] = []; for (let x = Math.ceil((S0 * 0.85) / stp) * stp; x <= S0 * 1.2 + 1e-9; x = +(x + stp).toFixed(2)) o.push(x); return o; }, [S0, stp]);
  const expiries = useMemo(() => {
    const d0 = m.isoAt(0), otm = inputs?.names.find((n) => n.t === t)?.otm?.ex;
    const all = new Set<string>([...(sd?.t === t ? sd.exps.map((e) => e.ex) : []), ...m.walls.map((c) => c.ex), ...m.legs.filter((l) => l.ty !== 'S').map((l) => l.ex), ...(otm ? [otm] : [])]);
    return [...all].filter((x) => x >= d0 && m.daysTo(x) > 0).sort();
  }, [m, inputs, t, sd]);
  const fri = segs.find((s) => s.i === m.fridayStop)?.iso ?? payload?.brief?.friday ?? '';
  const draft: Required<Draft> = { side: 's', ty: 'c', K: Math.ceil((S0 * 1.03) / stp) * stp, ex: expiries.find((x) => x > fri) ?? expiries[0] ?? fri, n: book === 'N' ? 3 : 10, ...wf.draft } as Required<Draft>;
  if (!expiries.includes(draft.ex) && expiries.length) draft.ex = expiries.find((x) => x > fri) ?? expiries[0];
  const strikeList = strikes.includes(draft.K) ? strikes : [...strikes, draft.K].sort((a, b) => a - b);
  const expL = (iso: string) => expLabel(iso, m.wholeDays(iso));
  const closed = useMemo(() => closedDays(payload?.calendar), [payload?.calendar]);
  const rw = view === 'price' ? rangeWords(chart.data, S0, closed, rg) : null;
  // The Price chart keeps every strike held, whatever the switches (Nik, 13 Nov 2026).
  const optLegs = base.filter((l) => l.ty !== 'S');
  // This name's Sold in SD rows: the Price chart's sold tags wear their closeness (Nik, 14 Nov 2026).
  // (Closeness needs only the SD now, so no sunny-sd replies here.)
  const soldHere = useMemo(() => soldInSd(soldLegs(payload, new Map())).rows.filter((r) => r.t === t), [payload, t]);

  return (
    <>
      <div style={{ display: 'flex', gap: 36, alignItems: 'stretch' }}>
        <div style={{ flex: '4 1 560px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, minHeight: 34 }}>
            <Segmented label="Price or payoff" items={[['price', 'Price'], ['pay', 'Payoff']]} value={view} onPick={setView} width={184} />
            {view === 'price' ? (rw && <span style={{ fontSize: 13, color: MU }}>{rw.l} <span style={{ fontWeight: 600, color: rw.c }}>{rw.v}</span></span>)
              : <Segmented label="Chart or table" items={[['chart', 'Chart'], ['table', 'Table']]} value={tab} onPick={setTab} width={170} size={13} />}
          </div>
          {view === 'price'
            ? <PriceChart chart={chart.data} failed={chart.isError} S0={S0} closed={closed} legs={optLegs} trades={tradesOn} sold={soldHere} rg={rg} setRg={setRg} />
            : <Payoff t={t} pr={pr} base={start} wi={wi} chg={viewChg} segs={segs} seg={seg} dLong={dLong} pick={pick} tab={tab} mask={mask} iv={m.iv} />}
        </div>
        <WhatIf pr={pr} base={base} off={shut} trades={wf.trades} draft={draft} strikes={strikeList} expiries={expiries} expL={expL} nCh={nCh} cashC={cashC} mask={mask}
          setDraft={wf.setDraft} add={wf.add} remove={wf.remove} reset={wf.reset} />
      </div>
      <EveryLeg t={t} pr={pr} base={base} off={viewOff} note={viewChg ? 'with your changes' : 'income only'} trades={wf.trades} toggleLeg={wf.toggleLeg} toggleTrade={wf.toggleTrade} filter={lf} setFilter={setLf} mask={mask} />
      <Intelligence book={book} t={t} d={sd?.t === t ? sd : undefined} busy={sdQ.isFetching} failed={sdQ.isError} friday={payload?.brief?.friday ?? fri} chains={m.walls}
        pr={pr} base={base} off={shut} trades={wf.trades} setSd={wf.setSd} open={intelOpen} setOpen={setIntelOpen} mask={mask} />
    </>
  );
}
