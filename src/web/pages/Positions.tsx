/* eslint-disable @typescript-eslint/no-explicit-any */
// Positions (README "2 · Positions page"): the whole book's totals, one name at a time from the strip, its P&L by
// price at a date (the payoff, zoomable), the What if, and the tables. /positions opens the first name in the rail's
// order (short first, then thin, then the rest: Home's position rows); /positions/:t opens that name.
//
// Data, real only: Home's snapshot for the book (totals, names, the inputs the server priced on) and sunny-positions
// for the name's grid (usePositions, asked again when Home rebuilds), and sunny-sd for the SD layer (useSd, only while
// that layer is on: the card under the chart and its lines on the chart). The phone sums the same grid the same way
// (PositionsModel.swift); positions/model.ts is that port.
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { BOOK_NAME } from '../components/AccountMenu';
import { CountUp } from '../components/CountUp';
import { clock12, ny, shortDate } from '../lib/clock';
import { useHome, usePositions, usePrefetchPositions, useSd, useTicker, type J } from '../lib/data';
import { arrow, count, level, money, pct, price } from '../lib/format';
import { useWeb } from '../lib/state';
import { PayoffChart, ZS, FIT, type Line } from '../positions/PayoffChart';
import { SdCard } from '../positions/sd/SdCard';
import { NO_PICK, sdView, type SdPick, type SdReply } from '../positions/sd/model';
import { Compare, EveryLeg, Lists, PriceDateGrid, type CmpRow, type LegFilter, type LegRow } from '../positions/Tables';
import { WhatIfPanel } from '../positions/WhatIfPanel';
import { PosModel, Pricer, expLabel, fk, updn, type GridW, type Inputs, type PLeg, type Seg } from '../positions/model';
import { closedDays, draftLines, legLines } from '../positions/sd/legs';
import { useWhatIf, type Draft } from '../positions/whatif';
import { bookTotals, nameTotals, roleOf } from '../positions/totals';
import { PositionBar } from '../positions/TotalsTable';
import { DateSeg, Chip, G, HAIR, HAIR_S, K, MU, O, R, PosStyles, cl, kicker } from '../positions/ui';

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
  // The rail's order: Home's position rows (short first, then thin, closest to turning first).
  const order: string[] = useMemo(() => {
    const rows: J[] = brief?.position?.rows ?? [];
    const held = new Set(names.map((n) => n.t));
    const o = rows.map((r) => r.id).filter((id: string) => held.has(id));
    return o.length ? o : [...names].sort((a, b) => (b.st ?? 0) - (a.st ?? 0)).map((n) => n.t);
  }, [brief, names]);
  const want = (tParam ?? '').toUpperCase();
  const t = names.some((n) => n.t === want) ? want : null;
  useEffect(() => {
    if (names.length && !t && order[0]) nav(`/positions/${order[0]}${loc.search}`, { replace: true });
  }, [names.length, t, order, nav, loc.search]);

  // Read the other names ahead once the page is up (smooth switching); the rail order, from the name on screen on.
  const ahead = useMemo(() => { const i = Math.max(0, order.indexOf(t ?? '')); return [...order.slice(i + 1), ...order.slice(0, i)]; }, [order, t]);
  usePrefetchPositions(book, ahead, !!t);
  const subtitle = book ? `${BOOK_NAME[book]}’s book${payload ? ' · ' + asOf(payload.fresh?.marks) : ''}` : '';
  // The position bar (handoff 2026-11-11, 145b): every name from its own legs, the book their sum, so they always add
  // up. One view; no switch.
  const nt = useMemo(() => nameTotals(payload), [payload]);
  const bt = useMemo(() => bookTotals(nt), [nt]);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
      <PosStyles />
      <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'baseline', gap: '12px 14px' }}>
        <h1 style={{ margin: 0, fontSize: 42, lineHeight: '48px', fontWeight: 700, letterSpacing: '-.03em' }}>Positions</h1>
        <span style={{ fontSize: 15, color: MU }}>{subtitle}</span>
      </div>
      {payload && !names.length && (
        // An empty book (the agreed lines, as on the phone).
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{ fontSize: 20, fontWeight: 700 }}>Nothing held yet</span>
          <span style={{ fontSize: 13, color: MU }}>Each name you hold shows here once IBKR reports it.</span>
        </div>
      )}
      {names.length > 0 && <PositionBar book={bt} name={t ? nt.get(t) ?? null : null} t={t} mask={mask} />}
      {names.length > 0 && <Strip names={names} t={t} go={(x) => nav(`/positions/${x}${loc.search}`)} />}
      {t && book && <Name key={book} book={book} t={t} name={names.find((n) => n.t === t)} payload={payload} />}
    </div>
  );
}

/* ── The name strip: one 50 px circle per name, a dot when short (red) or thin (orange) by Friday ── */
function Strip({ names, t, go }: { names: J[]; t: string | null; go: (t: string) => void }) {
  return (
    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
      {names.map((n) => {
        const on = n.t === t, dot = n.st === 2 ? R : n.st === 1 ? O : null;
        return (
          <button key={n.t} type="button" className="bare" onClick={() => go(n.t)} aria-current={on ? 'true' : undefined} aria-label={n.name ?? n.t}
            style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, width: 70 }}>
            <span style={{ position: 'relative', width: 50, height: 50, boxSizing: 'border-box', borderRadius: '50%', background: 'rgba(255,255,255,.07)',
              border: on ? '2px solid #F5F5F7' : '1px solid rgba(255,255,255,.12)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 700 }}>
              {n.t}
              {dot && <span style={{ position: 'absolute', right: 0, top: 0, width: 11, height: 11, borderRadius: '50%', background: dot, boxShadow: '0 0 0 2px #050706' }} />}
            </span>
            <span style={{ fontSize: 13, fontWeight: on ? 700 : 400, color: on ? K : MU }}>{n.t}</span>
          </button>
        );
      })}
    </div>
  );
}

/* ── One name: the name line, then everything that reads its grid ──────────── */
function Name({ book, t, name, payload }: { book: 'S' | 'N'; t: string; name: J; payload: J }) {
  const { mask, privacy } = useWeb();
  const q = usePositions(book, t, payload?.built_at);
  const grid = q.data as GridW | undefined;
  const ready = !!grid && grid.t === t && grid.stops?.length > 0 && grid.S?.length > 1;
  // ⚠ SMOOTH SWITCHING (Nik, 9 Nov 2026: "every time I click on one ticker to the next the page shifts and almost
  // reloads"): while the next name's grid is on its way the last name stays on screen, dimmed, so the page never
  // collapses; Detail is not remounted per name, so the numbers count on from the last value (the design's CountUp).
  const last = useRef<{ t: string; grid: GridW } | null>(null);
  if (ready) last.current = { t, grid: grid! };
  const shown = ready ? { t, grid: grid! } : last.current;
  const S0 = ready ? grid!.S0 : +name?.S0 || 0, P0 = ready ? grid!.P0 : +name?.P0 || S0, mv = P0 ? (S0 / P0 - 1) * 100 : 0;
  const strat = String(name?.strategy ?? '');
  // The days the market is shut (Home's calendar): the SD lines on each leg count trading days around them.
  const closed = useMemo(() => closedDays(payload?.calendar), [payload?.calendar]);
  const company = String(name?.name ?? t);
  return (
    <>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12, paddingTop: 6 }}>
        <span className="tnum" style={{ whiteSpace: 'nowrap' }}>
          <span style={{ fontSize: 30, fontWeight: 700, letterSpacing: '-.02em' }}>{t}</span>{' '}
          <span style={{ fontSize: 22, color: MU }}>{price(S0)}</span>{' '}
          <span style={{ fontSize: 16, fontWeight: 600, color: mv < 0 ? R : G }}>{arrow(mv)} {pct(mv)}</span>
        </span>
        <span style={{ fontSize: 15, color: MU }}>{company}{strat ? ' · ' + strat.charAt(0).toUpperCase() + strat.slice(1) : ''}</span>
      </div>
      {shown ? (
        <div aria-busy={!ready} style={{ display: 'flex', flexDirection: 'column', gap: 24, opacity: ready ? 1 : 0.55, transition: 'opacity .2s',
          pointerEvents: ready ? 'auto' : 'none' }}>
          {!ready && q.isError && <span style={{ fontSize: 13, color: MU }}>Could not load {t}.</span>}
          <Detail book={book} t={shown.t} company={shown.t === t ? company : String(shown.t)} grid={shown.grid} inputs={payload?.brief_inputs ?? null}
            fridayIso={payload?.brief?.friday ?? ''} mask={mask} privacy={privacy} closed={closed} />
        </div>
      ) : q.isError ? <span style={{ fontSize: 13, color: MU }}>Could not load {t}.</span>
        : <div style={{ minHeight: 600 }} />}
    </>
  );
}

// The page's own state, kept while the page is open and across names (README State: date, zoom, layer, legFilter).
const pageState = { day: null as string | null, layer: '' as Layer, lf: 'all' as LegFilter };
type Layer = '' | 'walls' | 'tech' | 'sd';

function Detail({ book, t, company, grid, inputs, fridayIso, mask, privacy, closed }:
  { book: 'S' | 'N'; t: string; company: string; grid: GridW; inputs: Inputs | null; fridayIso: string; mask: (s: string) => string; privacy: boolean; closed: Set<string> }) {
  const m = useMemo(() => new PosModel(grid, inputs), [grid, inputs]);
  // SD on your positions (handoff 2026-11-11-sd-on-positions, 139a): every option leg's three lines.
  const sdOf = useMemo(() => legLines(m, closed), [m, closed]);
  const wf = useWhatIf(book, t);
  const pr = useMemo(() => new Pricer(m, wf.trades), [m, wf.trades]);
  const S0 = m.S0;

  // The date: this Friday unless one is picked (kept by its day across names and rebuilds).
  const segs = useMemo(() => m.segments(), [m]);
  const [day, setDay] = useState<string | null>(pageState.day);
  const pick = (s: Seg) => { pageState.day = s.key; setDay(s.key); };
  const seg = segs.find((s) => s.key === day) ?? segs.find((s) => s.i === m.fridayStop) ?? segs[segs.length - 1];
  const D = { tt: seg.tt, row: seg.row }, dL = seg.label;
  const [zoom, setZoom] = useState(FIT);
  const widest = m.widest(ZS), zi = Math.min(zoom, widest), ZR = ZS[zi] / 100;
  const [layer, setLayerS] = useState(pageState.layer);
  const setLayer = (l: Layer) => { pageState.layer = l; setLayerS(l); };
  const [lf, setLfS] = useState(pageState.lf);
  const setLf = (f: LegFilter) => { pageState.lf = f; setLfS(f); };
  // The 50-day average lives with the ticker chart's data; asked for only while Technicals is on.
  const chart = useTicker(layer === 'tech' ? t : null, book);
  // The SD calculator (handoff 2026-11-11): asked for only while its layer is on. The pick (expiry, call SD, put SD)
  // belongs to the name it was made on; a new name opens on its own suggestion.
  const sdQ = useSd(book, layer === 'sd' ? t : null);
  const [sdPick, setSdPick] = useState<SdPick>(NO_PICK);
  const sdData = layer === 'sd' ? (sdQ.data as SdReply | undefined) : undefined;
  const sdV = useMemo(() => (sdData ? sdView(sdData, sdPick, setSdPick) : null), [sdData, sdPick]);

  // The book as it is, and with the What if (legs off, trades on).
  const off = useMemo(() => new Set(wf.off.filter((k) => m.legs.some((l) => l.k === k))), [wf.off, m]);
  const base = m.legs;
  const tradesOn = pr.trades.filter((l) => wf.trades.find((u) => u.id === l.trade)?.on);
  const wi: PLeg[] = useMemo(() => [...base.filter((l) => !off.has(l.k)), ...tradesOn], [base, off, pr, wf.trades]); // eslint-disable-line react-hooks/exhaustive-deps
  const nCh = off.size + tradesOn.length, chg = nCh > 0;
  const cashC = base.filter((l) => off.has(l.k)).reduce((a, l) => a + l.value, 0) + tradesOn.reduce((a, l) => a - l.value, 0);

  // The chart's prices: the grid's inside the zoom, both ends read between them.
  const ch = useMemo(() => {
    const X0 = S0 * (1 - ZR), X1 = S0 * (1 + ZR), e = (X1 - X0) * 1e-4;
    const xs = [X0, ...m.S.filter((x) => x > X0 + e && x < X1 - e), X1];
    const vB = xs.map((x) => pr.pl(base, x, D)), vW = chg ? xs.map((x) => pr.pl(wi, x, D)) : vB;
    return { xs, vB, vW };
  }, [m, pr, base, wi, chg, ZR, D.tt, D.row]); // eslint-disable-line react-hooks/exhaustive-deps
  const v0 = pr.pl(wi, S0, D), vb0 = pr.pl(base, S0, D);
  const gk = pr.greeks(wi, S0, D);
  const shW = pr.shortAt(wi, D, !chg), top = m.topPct;
  const xpS = (s: number) => (s / S0 - 1 + ZR) / (2 * ZR) * 100;
  // The move priced to the date: iv × √(trading days to it ÷ 252), Today counting one.
  const td = Math.max(1, seg.i + (m.stops[0]?.tt > 0 ? 1 : 0)), sdv = m.iv > 0 ? m.iv * Math.sqrt(td / 252) : 0;
  const band = sdv > 0 ? (() => { const l = Math.max(0, xpS(S0 * (1 - sdv))), r = Math.min(100, xpS(S0 * (1 + sdv))); return { l, w: Math.max(0, r - l), label: `Priced move by ${dL} · ±${(sdv * 100).toFixed(1)}%` }; })() : null;
  // ⚠ NEVER "short above" (Nik, 7 Nov 2026): it reads as a loss. Say where the P&L peaks, in the phone's words.
  const short = shW != null && xpS(shW) <= 100 ? { x: xpS(shW), label: 'makes the most at ' + price(shW) } : null;
  const inR = (k: number) => k >= S0 * (1 - ZR) && k <= S0 * (1 + ZR);
  const lines: Line[] = [];
  // No SD on the chart (Nik, 11 Nov 2026: "looks very busy"): the SD layer shows its card under the chart only.
  if (layer === 'walls') {
    const c = m.chainFor(seg.iso);
    if (c) ([['Ceiling', c.c], ['Floor', c.f]] as const).forEach(([l, w]) => { if (w && inR(w.k)) lines.push({ k: l, x: xpS(w.k), label: `${l} ${fk(w.k)} · ${c.label}`, kind: 'wall' }); });
  } else if (layer === 'tech') {
    const tc = (chart.data as J)?.tech ?? {};
    const s20 = m.tech?.sma20 ?? tc.sma20, s50 = tc.sma50;
    ([['20-day', s20], ['50-day', s50]] as const).forEach(([l, v]) => { if (v != null && inR(+v)) lines.push({ k: l, x: xpS(+v), label: `${l} ${level(+v)}`, kind: 'tech' }); });
  }

  // Compare: the book, and with changes.
  const cmp = (l: string, set: PLeg[], asIs: boolean): CmpRow => ({
    l, cells: [-10, -5, 0, 5, 10].map((p) => pr.pl(set, S0 * (1 + p / 100), D)), d: pr.delta(set, S0, D), sh: pr.shortAt(set, D, asIs),
    th: set.reduce((a, x) => a + pr.thL(x, S0, m.today), 0),
  });
  const cmpRows = [cmp('The book', base, true), ...(chg ? [cmp('With changes', wi, false)] : [])];
  // P&L by price and date: the first date, then each Friday.
  const cols = [segs[0], ...segs.filter((s, i) => i > 0 && s.friday)].slice(0, 7);

  // Every leg: today's delta and theta, so far since opened.
  // Filtered by Nik's groups (D4): Long the shares, Hedge what was bought, Income what was sold.
  const fOk = (l: PLeg) => lf === 'all' || roleOf(l) === lf;
  const soFar = (l: PLeg) => (l.ty === 'S' ? l.q * (S0 - l.K) : l.at != null ? (l.now - l.at) * l.q * 100 : 0);
  const legRows: LegRow[] = [
    ...base.filter(fOk).map((l) => ({ l, on: !off.has(l.k), toggle: () => wf.toggleLeg(l.k), added: false, sf: soFar(l), d: pr.dL(l, S0, m.today), th: pr.thL(l, S0, m.today), sd: sdOf(l) })),
    ...pr.trades.filter(fOk).map((l) => { const u = wf.trades.find((x) => x.id === l.trade)!; return { l, on: !!u?.on, toggle: () => wf.toggleTrade(l.trade!), added: true, sf: null, d: pr.dL(l, S0, m.today), th: pr.thL(l, S0, m.today), sd: sdOf(l) }; }),
  ];
  const ltot = { sf: base.filter((l) => !off.has(l.k)).reduce((a, l) => a + soFar(l), 0), d: pr.delta(wi, S0, m.today), th: wi.reduce((a, l) => a + pr.thL(l, S0, m.today), 0) };

  // Try a trade: strikes 20% either side on the name's step, the name's listed expiries, 10 (3 on Nicolay's book).
  const stp = S0 < 50 ? 0.5 : S0 < 200 ? 1 : 5;
  const strikes = useMemo(() => { const o: number[] = []; for (let x = Math.ceil(S0 * 0.8 / stp) * stp; x <= S0 * 1.2 + 1e-9; x = +(x + stp).toFixed(2)) o.push(x); return o; }, [S0, stp]);
  const expiries = useMemo(() => {
    const d0 = m.isoAt(0), otm = inputs?.names.find((n) => n.t === t)?.otm?.ex;
    const all = new Set<string>([...m.walls.map((c) => c.ex), ...m.legs.filter((l) => l.ty !== 'S').map((l) => l.ex), ...(otm ? [otm] : [])]);
    return [...all].filter((x) => x >= d0 && m.daysTo(x) > 0).sort();
  }, [m, inputs, t]);
  const fri = segs.find((s) => s.i === m.fridayStop)?.iso ?? fridayIso;
  const draft: Required<Draft> = {
    side: 's', ty: 'c', K: Math.ceil(S0 / stp) * stp, ex: expiries.find((x) => x > fri) ?? expiries[0] ?? fri, n: book === 'N' ? 3 : 10, ...wf.draft,
  } as Required<Draft>;
  if (!expiries.includes(draft.ex) && expiries.length) draft.ex = expiries.find((x) => x > fri) ?? expiries[0];
  const strikeList = strikes.includes(draft.K) ? strikes : [...strikes, draft.K].sort((a, b) => a - b);

  const legend = chg ? 'Solid: with your changes. Dashed: the book as it is. Shaded: the priced move.' : 'Your book, P&L from today. Shaded: the priced move. Hover to read any price.';
  const gks = [
    { l: 'Delta', v: (gk.d < 0 ? 'Short ' : 'Long ') + count(gk.d), c: gk.d < 0 ? R : K },
    { l: 'Theta a day', v: mask(money(gk.th)), c: cl(gk.th) },
    { l: 'Gamma', v: count(gk.g) + ' a $1', c: gk.g < 0 ? R : K },
    { l: 'Vega', v: mask(money(gk.vg)), c: gk.vg < 0 ? R : K },
  ];
  return (
    <>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 36, alignItems: 'flex-start' }}>
        <div style={{ flex: '4 1 560px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 16 }}>
            <span style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
              <CountUp v={mask(updn(v0))} style={{ fontSize: 42, lineHeight: '46px', fontWeight: 700, letterSpacing: '-.03em', color: cl(v0) }} />
              <span style={{ fontSize: 14, color: MU }}>from today, by {dL}, if {company} stays at {price(S0)}</span>
              {chg && <span style={{ fontSize: 13, fontWeight: 600 }}>{mask('The book as it is · ' + updn(vb0))}</span>}
            </span>
            <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', textAlign: 'right', gap: 2 }}>
              <span style={{ fontSize: 15, fontWeight: 600, color: shW != null ? O : K }}>{shW == null ? `Keeps making more past ↑${top}% by ${dL}` : shW <= S0 * 1.0005 ? `Already past its best by ${dL}` : `Makes the most at ${price(shW)} by ${dL}`}</span>
              <span style={{ fontSize: 13, color: MU }}>{shW == null ? `still rising at ↑${top}%` : shW <= S0 * 1.0005 ? `each $1 up costs you from ${price(S0)}` : `↑${pct((shW / S0 - 1) * 100)} from ${price(S0)}`}</span>
            </span>
          </div>
          <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(4,minmax(0,1fr))', padding: '12px 0', borderTop: HAIR, borderBottom: HAIR }}>
            {gks.map((x) => (
              <span key={x.l} style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                <span style={{ fontSize: 12, color: MU }}>{x.l} · {dL}</span>
                <span style={{ fontSize: 19, lineHeight: '24px', fontWeight: 600, color: x.c }}>{x.v}</span>
              </span>
            ))}
          </div>
          <PayoffChart xs={ch.xs} vW={ch.vW} vB={ch.vB} chg={chg} S0={S0} v0={v0} zi={zi} widest={widest} setZoom={setZoom}
            band={band} short={short} lines={lines} privacy={privacy} />
          <span style={{ fontSize: 12, lineHeight: '18px', color: MU, paddingTop: 6 }}>{legend} Pinch, − and + zoom from ±5% to ±50%; double-click or the reset arrow goes back to ±25%.</span>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <span style={{ fontSize: 15, fontWeight: 600 }}>By {dL}</span>
              <span style={{ fontSize: 12, color: MU }}>● an expiry you hold</span>
            </div>
            <div role="radiogroup" aria-label="Date" className="tnum"
              style={{ display: 'grid', gridTemplateColumns: `repeat(${segs.length},minmax(0,1fr))`, gap: 2, padding: 2, borderRadius: 16, background: 'rgba(118,118,128,.24)' }}>
              {segs.map((s) => <DateSeg key={s.i} on={s.i === seg.i} label={s.label} held={s.held} onPick={() => pick(s)} />)}
            </div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Chip on={layer === 'walls'} onPick={() => setLayer(layer === 'walls' ? '' : 'walls')}>Walls</Chip>
            <Chip on={layer === 'tech'} onPick={() => setLayer(layer === 'tech' ? '' : 'tech')}>Technicals</Chip>
            <Chip on={layer === 'sd'} onPick={() => setLayer(layer === 'sd' ? '' : 'sd')}>SD</Chip>
            <span style={{ fontSize: 12, color: MU }}>one at a time</span>
          </div>
          {layer === 'sd' && (
            <SdCard v={sdV} t={t} busy={sdQ.isPlaceholderData || (!!sdV && sdV.t !== t)} failed={sdQ.isError || (!!sdData && !sdV)} mask={mask}
              onTry={(x) => wf.setSd(x)} sdIn={wf.trades.filter((u) => u.src === 'sd')} />
          )}
          <Compare dL={dL} rows={cmpRows} top={top} mask={mask} />
        </div>
        <WhatIfPanel t={t} pr={pr} legs={base} off={off} trades={wf.trades} nCh={nCh} cashC={cashC} draft={draft} strikes={strikeList} expiries={expiries}
          mask={mask} toggleLeg={wf.toggleLeg} toggleTrade={wf.toggleTrade} remove={wf.remove} setDraft={wf.setDraft} add={wf.add} reset={wf.reset}
          sdOf={sdOf} tryLine={draftLines(m, closed, draft, expLabel(draft.ex, m.wholeDays(draft.ex)))} />
      </div>
      <PriceDateGrid t={t} pr={pr} set={wi} cols={cols} picked={seg.i} onPick={pick} chg={chg} mask={mask} />
      <EveryLeg rows={legRows} total={ltot} filter={lf} setFilter={setLf} mask={mask} />
      <Lists t={t} pr={pr} today={m.today} fridayIso={fri} />
    </>
  );
}
