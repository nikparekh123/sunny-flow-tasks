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
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { nameDot, soldInSd, stepOf } from '../../../supabase/functions/_shared/positions-engine.ts';
import { BOOK_NAME } from '../components/AccountMenu';
import { clock12, estWords, ny, shortDate } from '../lib/clock';
import { useHome, usePositions, usePrefetchPositions, useSd, useSdMany, useStrikes, useTicker, type J } from '../lib/data';
import { arrow, pct, price } from '../lib/format';
import { useWeb } from '../lib/state';
import type { PCRange } from '../../../supabase/functions/_shared/price-chart.ts';
import { ConeSwitch, Payoff, PriceChart, XR0, rangeWords, useCone } from '../positions/Band';
import { BookTotals } from '../positions/BookTotals';
import { EveryLeg, type LegFilter } from '../positions/EveryLeg';
import { Intelligence } from '../positions/Intelligence';
import { ivAtStrike, pickExpiry, requestIntelScroll, setIntelOpen, useIntelOpen, type SdReply } from '../positions/intel';
import { PosModel, Pricer, expLabel, type GridW, type Inputs, type PLeg } from '../positions/model';
import { SoldCapsule, SoldCard, closedDays, soldLegs } from '../positions/SoldInSd';
import { bookTotals, nameTotals } from '../positions/totals';
import { useTarget } from '../positions/target';
import { G, K, MU, O, PosStyles, R, Segmented, useReducedMotion } from '../positions/ui';
import { WhatIf } from '../positions/WhatIfPanel';
import { useWhatIf, type Draft } from '../positions/whatif';

/** "Fri Nov 6 close" for marks taken at or after the close (or on an earlier day), else "Mon Nov 9 · 11:42 AM ET". */
const asOf = (iso: string | undefined) => {
  if (!iso) return '';
  const n = ny(new Date(iso)), today = ny();
  return n.date < today.date || n.mins >= 16 * 60 ? `${shortDate(n.date)} close` : `${shortDate(n.date)} · ${clock12(n)} ET`;
};

/** A company's logo (public/logos/TICKER.png) at 60% of the disc; the ticker when there is no logo file. */
function Logo({ t }: { t: string }) {
  const [bad, setBad] = useState(false);
  useEffect(() => setBad(false), [t]);
  if (bad) return <span aria-hidden="true" style={{ fontSize: 10, lineHeight: '12px', fontWeight: 700, color: '#1D1D1F' }}>{t}</span>;
  return <img src={`/logos/${t}.png`} alt="" aria-hidden="true" draggable={false} onError={() => setBad(true)} style={{ width: '60%', height: '60%', objectFit: 'contain', pointerEvents: 'none' }} />;
}

export default function Positions() {
  const { t: tParam } = useParams();
  const rm = useReducedMotion();
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
  // Before the open and after the close the marks are estimates from pre-market or after-hours trades (18 Nov 2026).
  const est = estWords(payload?.brief_inputs?.prices_est ?? payload?.prices_est);
  const subtitle = book ? `${BOOK_NAME[book]}’s book${payload ? ' · ' + (est ?? asOf(payload.fresh?.marks)) : ''}` : '';
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
                  {/* Handoff 2026-11-18 §3.2: a white disc with the logo at 60%; the ring is an inset shadow, so the dot
                      (pinned to the top right) never moves when a name is picked. */}
                  <span style={{ position: 'relative', width: 50, height: 50, boxSizing: 'border-box', borderRadius: '50%', background: '#FFFFFF',
                    boxShadow: on ? 'inset 0 0 0 3px #F5F5F7' : 'inset 0 0 0 1.5px rgba(255,255,255,.2)', transition: rm ? 'none' : 'box-shadow .2s ease',
                    display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Logo t={n.t} />
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
  // The legs as the grid lists them (key and count), so a trade picked up asks for the grid at once.
  const legSig = ((payload?.brief_inputs?.names ?? []).find((n: J) => n.t === t)?.legs ?? []).map((l: J) => `${l.k}:${l.q}`).sort().join(',');
  const q = usePositions(book, t, { built: payload?.built_at, S: +name?.S0 || 0, legs: legSig });
  const grid = q.data as GridW | undefined;
  const ready = !!grid && grid.t === t && grid.stops?.length > 0 && grid.S?.length > 1;
  // ⚠ SMOOTH SWITCHING (Nik, 9 Nov 2026): while the next name's grid is on its way the last name stays on screen,
  // dimmed, so the page never collapses.
  const last = useRef<{ t: string; grid: GridW } | null>(null);
  if (ready) last.current = { t, grid: grid! };
  const shown = ready ? { t, grid: grid! } : last.current;
  // The header reads Home's price (every 15 s), not the grid's: the grid now refreshes on a real move or each minute.
  const S0 = +name?.S0 || (ready ? grid!.S0 : 0), P0 = +name?.P0 || (ready ? grid!.P0 : S0), mv = P0 ? (S0 / P0 - 1) * 100 : 0;
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

// The page's own state, kept across names and rebuilds: the Payoff date ('now', an ISO day, or null for this Friday)
// and range (±%), Price or Payoff, Chart or Table, the Price chart's range, the Every leg filter.
const pageState = { day: null as string | null, xr: XR0 as number, view: 'pay' as 'price' | 'pay', tab: 'chart' as 'chart' | 'table', rg: '1W' as PCRange, lf: 'all' as LegFilter };
function usePageState<K extends keyof typeof pageState>(k: K): [(typeof pageState)[K], (v: (typeof pageState)[K]) => void] {
  const [v, setV] = useState(pageState[k]);
  return [v, (x) => { pageState[k] = x; setV(x); }];
}

function Detail({ book, t, grid, payload, mask }: { book: 'S' | 'N'; t: string; grid: GridW; payload: J; mask: (s: string) => string }) {
  const inputs: Inputs | null = payload?.brief_inputs ?? null;
  const m = useMemo(() => new PosModel(grid, inputs), [grid, inputs]);
  const wf = useWhatIf(book, t);
  const S0 = m.S0;
  const [view, setView] = usePageState('view');
  const [tab, setTab] = usePageState('tab');
  const [rg, setRg] = usePageState('rg');
  const [lf, setLf] = usePageState('lf');
  const [day, setDay] = usePageState('day');
  const [xr, setXr] = usePageState('xr');
  const [cone, toggleCone] = useCone();
  const target = useTarget(book, t);
  const chart = useTicker(t, book);
  const sdQ = useSd(book, t);
  const sd = sdQ.data as SdReply | undefined;
  // A trade's IV, as the market prices it (18 Nov 2026): the chain's IV at that strike and expiry, as Intelligence
  // prices its sale. Past the chain (it reads about 75 days): the leg held at that expiry nearest the strike, else the
  // chain's last expiry at that strike. Never the name's one IV, which is this week's and carries any earnings.
  const ivOf = useCallback((ex: string, K: number): number | undefined => {
    const exps = sd?.t === t ? [...sd.exps].sort((a, b) => a.ex.localeCompare(b.ex)) : [];
    const e = exps.find((x) => x.ex === ex);
    if (e) return ivAtStrike(e, K);
    const held = (inputs?.names.find((n) => n.t === t)?.legs ?? []).filter((l) => l.ty !== 'S' && l.ex === ex && l.iv > 0.03)
      .sort((a, b) => Math.abs(a.K - K) - Math.abs(b.K - K));
    if (held[0]) return held[0].iv;
    const last = exps.filter((x) => x.ex < ex).pop();
    return last ? ivAtStrike(last, K) : undefined;
  }, [sd, t, inputs]);
  // Trades added before the chain's IV came in (or before 18 Nov 2026) take it now, so their payoff is the market's too.
  const pr = useMemo(() => new Pricer(m, wf.trades.map((u) => (u.iv && u.iv > 0.03 ? u : { ...u, iv: ivOf(u.ex, u.K) }))), [m, wf.trades, ivOf]);
  const intelOpen = useIntelOpen();

  // The grid's dates (What if's default expiry reads this Friday from them).
  const segs = useMemo(() => m.segments(), [m]);

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

  // Try a trade: the strikes the chain lists for the expiry picked, 85% to 120% of the price (Nik, 20 Nov 2026: "show
  // the real strikes for each ticker, not just assume 1 dollar increment"), the name's expiries, 10 (3 on Nicolay's
  // book). An expiry sunny-sd's reply does not carry asks for its own list; the step guess stands in only when no
  // list comes back.
  const stp = stepOf(S0);
  const expiries = useMemo(() => {
    const d0 = m.isoAt(0), otm = inputs?.names.find((n) => n.t === t)?.otm?.ex;
    const all = new Set<string>([...(sd?.t === t ? sd.exps.map((e) => e.ex) : []), ...m.walls.map((c) => c.ex), ...m.legs.filter((l) => l.ty !== 'S').map((l) => l.ex), ...(otm ? [otm] : [])]);
    return [...all].filter((x) => x >= d0 && m.daysTo(x) > 0).sort();
  }, [m, inputs, t, sd]);
  const fri = segs.find((s) => s.i === m.fridayStop)?.iso ?? payload?.brief?.friday ?? '';
  const draft: Required<Draft> = { side: 's', ty: 'c', K: NaN, ex: expiries.find((x) => x > fri) ?? expiries[0] ?? fri, n: book === 'N' ? 3 : 10, ...wf.draft } as Required<Draft>;
  if (!expiries.includes(draft.ex) && expiries.length) draft.ex = expiries.find((x) => x > fri) ?? expiries[0];
  const sdKs = sd?.t === t ? sd.exps.find((e) => e.ex === draft.ex)?.ks : undefined;
  const need = sd?.t === t && !sdKs?.length;
  const ksQ = useStrikes(book, t, draft.ex, need);
  const listed = sdKs?.length ? sdKs : ksQ.data?.ok ? ksQ.data.ks : null;
  // While an expiry's list is on its way: only the strike already picked, so no guessed strike shows.
  const hold = need && ksQ.isPending && Number.isFinite(draft.K) ? draft.K : null;
  const strikes = useMemo(() => {
    const lo = S0 * 0.85, hi = S0 * 1.2 + 1e-9;
    if (listed?.length) { const o = listed.filter((k) => k >= lo && k <= hi); if (o.length) return o; }
    if (hold != null) return [hold];
    const o: number[] = [];
    for (let x = Math.ceil(lo / stp) * stp; x <= hi; x = +(x + stp).toFixed(2)) o.push(x);
    return o;
  }, [listed, S0, stp, hold]);
  // The strike: the one picked when this expiry lists it, else the listed strike nearest it; to start, the first
  // listed about 3% out.
  if (!Number.isFinite(draft.K)) draft.K = strikes.find((k) => k >= S0 * 1.03) ?? strikes[strikes.length - 1] ?? Math.ceil((S0 * 1.03) / stp) * stp;
  else if (strikes.length && !strikes.includes(draft.K)) draft.K = strikes.reduce((a, b) => (Math.abs(b - draft.K) < Math.abs(a - draft.K) ? b : a));
  const strikeList = strikes;
  const expL = (iso: string) => expLabel(iso, m.wholeDays(iso));
  const closed = useMemo(() => closedDays(payload?.calendar), [payload?.calendar]);
  // The Price chart's SD and the 1 SD cone read this week's IV: the name's IV on the Friday chain at the strike nearest
  // the price (Home's brief_inputs, the same IV as the Payoff's priced move).
  const rw = view === 'price' ? rangeWords(chart.data, S0, closed, rg, m.iv) : null;
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
            {/* Payoff first and open on it, Price second (Nik, 20 Nov 2026). */}
            <Segmented label="Payoff or price" items={[['pay', 'Payoff'], ['price', 'Price']]} value={view} onPick={setView} width={184} />
            {view === 'price' ? (rw && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                <span style={{ fontSize: 13, color: MU }}>{rw.l} <span style={{ fontWeight: 600, color: rw.c }}>{rw.v}</span></span>
                {rw.coneOk && <ConeSwitch on={cone} toggle={toggleCone} />}
              </div>
            )) : <Segmented label="Chart or table" items={[['chart', 'Chart'], ['table', 'Table']]} value={tab} onPick={setTab} width={170} size={13} />}
          </div>
          {view === 'price'
            ? <PriceChart chart={chart.data} failed={chart.isError} S0={S0} closed={closed} legs={optLegs} trades={tradesOn} sold={soldHere} rg={rg} setRg={setRg} iv={m.iv} cone={cone} />
            : <Payoff t={t} pr={pr} base={start} wi={wi} chg={viewChg} tab={tab} mask={mask} iv={m.iv} closed={closed} day={day} setDay={setDay} xr={xr} setXr={setXr}
                tg={target.tg} setTg={target.set} />}
        </div>
        <WhatIf pr={pr} base={base} off={shut} trades={wf.trades} draft={draft} ivOf={ivOf} strikes={strikeList} expiries={expiries} expL={expL} nCh={nCh} cashC={cashC} mask={mask}
          setDraft={wf.setDraft} add={wf.add} remove={wf.remove} reset={wf.reset} />
      </div>
      <EveryLeg t={t} pr={pr} base={base} off={viewOff} note={viewChg ? 'with your changes' : 'income only'} trades={wf.trades} toggleLeg={wf.toggleLeg} toggleTrade={wf.toggleTrade} filter={lf} setFilter={setLf} mask={mask} />
      <Intelligence book={book} t={t} d={sd?.t === t ? sd : undefined} busy={sdQ.isFetching} failed={sdQ.isError} friday={payload?.brief?.friday ?? fri} chains={m.walls}
        pr={pr} base={base} off={shut} trades={wf.trades} setSd={wf.setSd} open={intelOpen} setOpen={setIntelOpen} mask={mask} />
    </>
  );
}
