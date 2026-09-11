/**
 * Payoff planner — sunnyfi.co/payoff. Handoff: design_handoff_payoff_planner.
 *
 * Two ideas the whole screen is built around, from the README:
 *
 *   The payoff date is DERIVED from the legs, never chosen freely. The chart
 *   shows the payoff at the nearest leg expiry and the Date slider scrubs from
 *   today to it.
 *
 *   Broker legs are IMMUTABLE. A plan is a set of draft legs layered on top;
 *   nothing here touches IBKR. Nik: "nothing gets saved from here. The planner
 *   gets saved, but it doesn't change the position."
 *
 * Self-gated like /positions and carrying its own header, because Nik wants
 * this page to look different from the rest of the site.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import Auth from '@/pages/Auth';
import { usePayoffBook, usePlans, DEV_FIXTURE } from './usePayoffBook';
import { Chart } from './Chart';
import type { TickerBook, Layers, LayerKey, SavedPlan } from './types';
import { DEFAULT_LAYERS } from './types';
import {
  type Leg, type Ctx, dteOf, fmtExp, fmtStamp, fmtLongDate, money, money2, priceLab, priceShort,
  signed, signed1, unrealized, netGreeks, premiumNow, premiumHistory, chance, bounds, moneyness,
  strikeStep, basisStep, entryOf, liveMark, parseISO,
} from './math';
import './payoff.css';

/** Where the last-read name is kept, so a reload does not reset the page. */
const TICK_KEY = 'sunnyfi.payoff.ticker';

const LAYER_META: { key: LayerKey; name: string; ink: string; band: boolean }[] = [
  { key: 'ema', name: 'EMA 20 / 50 / 200', ink: 'var(--hair)', band: false },
  { key: 'sr', name: 'Support · resistance', ink: 'var(--faint)', band: false },
  { key: 'last5', name: 'Last 5 days', ink: 'var(--ink-3)', band: true },
  { key: 'targets', name: 'Analyst target', ink: 'var(--plum)', band: true },
  { key: 'cone', name: 'Probability cone', ink: 'var(--update)', band: true },
  { key: 'hist', name: 'Time at price', ink: 'var(--hair)', band: true },
];

function legTitle(l: Leg): string {
  if (l.kind === 'stock') return `${Math.abs(l.qty)} shares`;
  return `${l.qty < 0 ? '−' : ''}${Math.abs(l.qty)} × ${priceShort(l.strike)} ${l.kind === 'call' ? 'Call' : 'Put'}`;
}

export default function PayoffPage() {
  const auth = useAuth();
  const user = DEV_FIXTURE ? { id: 'dev' } as typeof auth.user : auth.user;
  const loading = DEV_FIXTURE ? false : auth.loading;
  const { data, isLoading, error } = usePayoffBook();
  const { plans, save, update, remove } = usePlans(user?.id);

  /* ── state, as the README lists it ─────────────────────────────────── */
  /* ⚠ THE CHOSEN NAME SURVIVES A RELOAD. Nik, 2026-09-11: "when you refresh it
     should stay on the same ticker and not reset". It was state with no
     backing, so every reload landed on whichever name happened to sort first
     and he had to click back to the one he was reading. */
  const [tick, setTick] = useState<string | null>(() => {
    try { return localStorage.getItem(TICK_KEY); } catch { return null; }
  });
  const [planned, setPlanned] = useState<Leg[]>([]);
  const [seq, setSeq] = useState(1);
  const [planOn, setPlanOn] = useState<Record<string, boolean>>({});
  const [activePlan, setActivePlan] = useState<string | null>(null);
  const [dirty, setDirty] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [ivMult, setIvMult] = useState(1);
  const [rangePct, setRangePct] = useState(27);
  const [selLeg, setSelLeg] = useState<string | null>(null);
  const [off, setOff] = useState<Record<string, boolean>>({});
  const [openHist, setOpenHist] = useState<string | null>(null);
  const [addOpen, setAddOpen] = useState(false);
  const [layersOpen, setLayersOpen] = useState(false);
  const [closedOpen, setClosedOpen] = useState(false);
  const [layers, setLayers] = useState<Layers>(DEFAULT_LAYERS);
  const [closes, setCloses] = useState<Record<string, number[]>>({});
  const stripRef = useRef<HTMLDivElement>(null);

  const today = useMemo(() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; }, []);
  const books = data?.book ?? [];
  const book: TickerBook | undefined = books.find((b) => b.ticker === tick) ?? books[0];
  /* A saved name that is no longer in the book falls back rather than sticking:
     a position can be closed between one visit and the next. */
  useEffect(() => {
    if (!books.length) return;
    if (tick && books.some((b) => b.ticker === tick)) return;
    setTick(books[0].ticker);
  }, [books, tick]);
  useEffect(() => {
    if (!tick) return;
    try { localStorage.setItem(TICK_KEY, tick); } catch { /* private window */ }
  }, [tick]);
  useEffect(() => {
    if (book && (book as unknown as { closes?: number[] }).closes) {
      setCloses((c) => ({ ...c, [book.ticker]: (book as unknown as { closes: number[] }).closes }));
    }
  }, [book]);

  /* ── derived, in the order the README gives ─────────────────────────── */
  /* ⚠ MEMOIZED, OR THE WHOLE CHART RECOMPUTES ON EVERY MOUSE MOVE. Nik,
     2026-09-09: "it moves more like 99.93 it stay there and when you move
     through payoff it shows 88.93".

     A fresh object here invalidated the Chart's curve memo on every render,
     and every hover sets state, so each pixel of movement re-evaluated three
     221-point curves across every leg — thousands of Black-Scholes calls a
     frame. The pointer then updates only when a frame happens to land, which
     reads exactly as sticking and then jumping. */
  const ctx: Ctx | null = useMemo(
    () => (book ? { spot: book.spot, iv: book.iv, today, ivMult } : null),
    [book, today, ivMult]);
  /* ⚠ THESE TWO ARE MEMOIZED FOR THE SAME REASON `ctx` IS. Built inline they
     were a fresh array on every render, so `allLegs` and then `liveLegs` were
     fresh too, and the Chart's curve memo could never hold no matter what else
     was stabilised. The whole chain has to be stable or none of it is. */
  const myPlanned = useMemo(
    () => planned.filter((l) => l.id.startsWith(`${book?.ticker}:`)),
    [planned, book?.ticker]);
  const savedOnLegs = useMemo(
    () => plans.filter((p) => p.ticker === book?.ticker && planOn[p.id] && p.id !== activePlan)
      .flatMap((p) => p.legs.map((l) => ({ ...l, plan: true }))),
    [plans, book?.ticker, planOn, activePlan]);
  const bookLegs = useMemo(() => (book?.legs ?? []).filter((l) => !off[l.id]), [book, off]);
  const allLegs = useMemo(() => [...(book?.legs ?? []), ...myPlanned, ...savedOnLegs], [book, myPlanned, savedOnLegs]);
  const liveLegs = useMemo(() => allLegs.filter((l) => !off[l.id]), [allLegs, off]);
  const legExpiries = useMemo(() => {
    const s = new Set<string>(); liveLegs.forEach((l) => { if (l.expiry) s.add(l.expiry); });
    const out = [...s].sort();
    return out.length ? out : (book?.chain[0] ? [book.chain[0]] : []);
  }, [liveLegs, book]);
  /* ⚠ THE PAYOFF DATE IS ALWAYS THE NEAREST LIVE LEG EXPIRY, and cannot be
     chosen. Nik, 2026-09-09: "I shuold be able to get this if I swtich off the
     legs right".

     He is right, and it is why the "show payoff at" pills are gone. Picking a
     far date left the legs that expire BEFORE it still being priced at that
     date's price: at Mar 2027 the model still charged $5.95 of intrinsic on
     the 50 short calls expiring this Friday, because NKE was $44.95 in March.
     The curve went flat, because the phantom short lost exactly as fast as the
     LEAP gained.

     Unchecking a leg already recomputes `legExpiries`, so turning off the
     weeklies walks the date out to March and then to the LEAP, and every one
     of those views is arithmetically sound. The toggle does the work a date
     picker was doing badly. */
  const sel = legExpiries[0] ?? '';
  const dte = sel ? Math.max(0, dteOf(sel, today)) : 0;
  const planActive = myPlanned.length > 0 || savedOnLegs.length > 0;
  const picking = selLeg != null && myPlanned.some((l) => l.id === selLeg);

  /* ── the numbers ────────────────────────────────────────────────────── */
  const M = useMemo(() => {
    if (!ctx || !book) return null;
    const bnd = bounds(liveLegs, dte, ctx), bookBnd = planActive ? bounds(bookLegs, dte, ctx) : null;
    const ch = chance(liveLegs, dte, ctx), bookCh = planActive ? chance(bookLegs, dte, ctx) : null;
    const g = netGreeks(liveLegs, elapsed, ctx), bookG = planActive ? netGreeks(bookLegs, elapsed, ctx) : null;
    const pn = premiumNow(liveLegs, elapsed, ctx);
    const ph = premiumHistory(bookLegs, myPlanned, ctx);
    const net = liveLegs.reduce((s, l) => s + (l.kind === 'stock' ? 0 : -l.qty * 100 * entryOf(l, ctx)), 0);
    const unrl = unrealized(liveLegs, elapsed, ctx);
    const realized = book.closed.reduce((s, c) => s + c.pnl, 0);
    return { bnd, bookBnd, ch, bookCh, g, bookG, pn, ph, net, unrl, realized };
  }, [ctx, book, liveLegs, bookLegs, myPlanned, dte, elapsed, planActive]);

  /* ── actions ────────────────────────────────────────────────────────── */
  const pickTicker = (t: string) => {
    setTick(t); setActivePlan(null); setDirty(false); setElapsed(0);
    setOpenHist(null); setAddOpen(false); setSelLeg(null);
  };
  /* ⚠ THE STRIKE LADDER IS THE VENDOR'S, NOT ARITHMETIC. Nik, 2026-09-11: "it
     either shows 37.50 or 40 which is not true there is a strike 38 and 39 and
     in between".

     `strikeStep(spot)` was a hardcoded $2.50 under a $100 spot, so on a $36.62
     NKE the stepper walked 37.50 to 40.00 and could not land on a strike that
     exists. The grid is not uniform either: NKE's 18 Sep weekly runs half
     dollars near the money and whole dollars further out, and the Jan 2028
     LEAP is five dollars apart. Only the chain knows.

     `strikeStep` survives as the fallback for an expiry Polygon did not
     return, so the stepper always moves even when the ladder is missing. */
  const ladder = (exp: string): number[] => book?.strikes?.[exp] ?? [];
  const snapStrike = (exp: string, p: number): number => {
    const list = ladder(exp);
    if (!list.length) { const st = strikeStep(book?.spot ?? p); return Math.round(p / st) * st; }
    return list.reduce((a, b) => (Math.abs(b - p) < Math.abs(a - p) ? b : a), list[0]);
  };
  const nextStrike = (exp: string, cur: number, d: number): number => {
    const list = ladder(exp);
    if (list.length) {
      if (d > 0) { const k = list.find((v) => v > cur + 1e-6); if (k != null) return k; }
      else { for (let i = list.length - 1; i >= 0; i--) if (list[i] < cur - 1e-6) return list[i]; }
      /* Off the end of the ladder: stay put rather than invent a contract. */
      return cur;
    }
    return Math.round((cur + d * strikeStep(book?.spot ?? cur)) * 100) / 100;
  };

  const addLeg = (kind: 'call' | 'put' | 'stock', short: boolean) => {
    if (!book) return;
    const id = `${book.ticker}:p${seq}`; setSeq(seq + 1);
    const exp = sel || book.chain[0] || '';
    const leg: Leg = kind === 'stock'
      ? { id, kind, qty: short ? -100 : 100, strike: 0, expiry: '', premium: 0, mark: null, iv: null, basis: book.spot, history: [], plan: true }
      : { id, kind, qty: short ? -1 : 1, strike: snapStrike(exp, book.spot), expiry: exp, premium: 0, mark: null, iv: null, history: [], plan: true };
    if (kind !== 'stock' && ctx) leg.premium = Math.round(liveMark(leg, 0, ctx) * 100) / 100;
    setPlanned((p) => [...p, leg]); setSelLeg(id); setDirty(true); setAddOpen(false);
  };
  const editLeg = (id: string, f: (l: Leg) => Leg) => {
    setPlanned((p) => p.map((l) => (l.id === id ? f(l) : l))); setDirty(true);
  };
  const stepQty = (l: Leg, d: number) => {
    const unit = l.kind === 'stock' ? 100 : 1;
    let q = l.qty + d * unit; if (q === 0) q = d * unit;
    editLeg(l.id, (x) => ({ ...x, qty: q }));
  };
  const stepPrice = (l: Leg, d: number) => {
    if (!book || !ctx) return;
    if (l.kind === 'stock') { editLeg(l.id, (x) => ({ ...x, basis: Math.round(((x.basis ?? book.spot) + d * basisStep(book.spot)) * 100) / 100 })); return; }
    editLeg(l.id, (x) => {
      const nx = { ...x, strike: nextStrike(x.expiry, x.strike, d) };
      nx.premium = Math.round(liveMark(nx, 0, ctx) * 100) / 100;
      return nx;
    });
  };
  const setLegExpiry = (iso: string) => {
    if (!selLeg || !ctx) return;
    /* ⚠ AND THE STRIKE RE-SNAPS. A $38.50 that exists on this Friday's weekly
       is not a contract on the Jan 2028 LEAP, whose ladder is five dollars
       apart. Moving the date has to move the strike onto the new ladder or the
       leg quietly becomes one nobody can trade. */
    editLeg(selLeg, (x) => {
      const nx = { ...x, expiry: iso, strike: x.kind === 'stock' ? x.strike : snapStrike(iso, x.strike) };
      nx.premium = Math.round(liveMark(nx, 0, ctx) * 100) / 100; return nx;
    });
    setElapsed(0);
  };
  const removeLeg = (id: string) => {
    const l = planned.find((x) => x.id === id);
    if (l?.replaces) setOff((o) => { const n = { ...o }; delete n[l.replaces!]; return n; });
    setPlanned((p) => p.filter((x) => x.id !== id)); if (selLeg === id) setSelLeg(null); setDirty(true);
  };
  const discard = () => {
    myPlanned.forEach((l) => { if (l.replaces) setOff((o) => { const n = { ...o }; delete n[l.replaces!]; return n; }); });
    setPlanned((p) => p.filter((l) => !l.id.startsWith(`${book?.ticker}:`)));
    setActivePlan(null); setDirty(false); setSelLeg(null);
  };
  const savePlan = async () => {
    if (!book || !user) return;
    if (activePlan) { await update.mutateAsync({ id: activePlan, legs: myPlanned }); setPlanOn((o) => ({ ...o, [activePlan]: true })); }
    else {
      const name = `Plan ${String.fromCharCode(65 + plans.filter((p) => p.ticker === book.ticker).length)}`;
      const id = await save.mutateAsync({ ticker: book.ticker, name, legs: myPlanned });
      setPlanOn((o) => ({ ...o, [id]: true }));
    }
    setPlanned((p) => p.filter((l) => !l.id.startsWith(`${book.ticker}:`)));
    setActivePlan(null); setDirty(false); setSelLeg(null);
  };
  const editSaved = (p: SavedPlan) => {
    setPlanned((x) => [...x.filter((l) => !l.id.startsWith(`${p.ticker}:`)), ...p.legs.map((l) => ({ ...l, plan: true }))]);
    setActivePlan(p.id); setPlanOn((o) => ({ ...o, [p.id]: false })); setDirty(false);
  };

  /* ── gates ──────────────────────────────────────────────────────────── */
  if (loading) return <div className="po"><div className="po-empty">Signing in…</div></div>;
  if (!user) return <Auth />;
  if (isLoading) return <div className="po"><div className="po-empty">Loading the book…</div></div>;
  if (error || !data?.ok) return <div className="po"><div className="po-empty">The book did not answer. {String((error as Error)?.message ?? '')}</div></div>;
  if (!book || !ctx || !M) return <div className="po"><div className="po-empty">No open positions.</div></div>;

  /* ── header pieces ──────────────────────────────────────────────────── */
  const wkWord = book.wk52 ? (() => {
    const f = (book.spot - book.wk52[0]) / Math.max(book.wk52[1] - book.wk52[0], 0.01);
    return f > 0.85 ? 'near the high' : f > 0.6 ? 'upper half' : f > 0.4 ? 'mid range' : f > 0.15 ? 'lower half' : 'near the low';
  })() : '';
  const wkPos = book.wk52 ? Math.min(98, Math.max(2, ((book.spot - book.wk52[0]) / Math.max(book.wk52[1] - book.wk52[0], 0.01)) * 100)) : 50;

  /* ── calendar ───────────────────────────────────────────────────────── */
  const used = new Set(liveLegs.map((l) => l.expiry));
  const editing = selLeg ? myPlanned.find((l) => l.id === selLeg) : null;
  const marked = editing?.expiry || sel;
  const months: { key: string; label: string; days: string[] }[] = [];
  for (const iso of book.chain) {
    const k = iso.slice(0, 7); const d = parseISO(iso);
    let m = months.find((x) => x.key === k);
    if (!m) { m = { key: k, label: d.toLocaleDateString('en-US', { month: 'short', year: d.getFullYear() !== today.getFullYear() ? '2-digit' : undefined }), days: [] }; months.push(m); }
    m.days.push(iso);
  }

  /* ── metric strip ───────────────────────────────────────────────────── */
  const { bnd, bookBnd, ch, bookCh, g, bookG, pn, ph, net, unrl, realized } = M;
  const be0 = bnd.bes[0];
  const metrics = [
    { label: planActive ? (net < 0 ? 'Plan costs' : 'Plan pays') : (net < 0 ? 'Net debit' : 'Net credit'), value: money(Math.abs(net)), sub: net < 0 ? 'debit paid' : 'credit received' },
    { label: 'Max profit', value: bnd.gainUnbounded ? 'Unlimited' : money(bnd.max), sub: bookBnd ? `book ${bookBnd.gainUnbounded ? 'unlimited' : money(bookBnd.max)}` : `at ${fmtExp(sel, today)}` },
    { label: 'Max loss', value: bnd.lossUnbounded ? 'Unlimited' : money(bnd.min), ink: bnd.lossUnbounded ? 'var(--loss)' : undefined, sub: bookBnd ? `book ${bookBnd.lossUnbounded ? 'unlimited' : money(bookBnd.min)}` : `at ${fmtExp(sel, today)}` },
    { label: 'Breakeven', value: be0 ? priceLab(be0) : '–', sub: be0 ? `${signed1((be0 / book.spot - 1) * 100)}% from spot${bnd.bes.length > 1 ? ` · +${bnd.bes.length - 1} more` : ''}` : 'none in range' },
    { label: 'Chance of profit', value: `${Math.round(ch * 100)}%`, sub: bookCh != null ? `book ${Math.round(bookCh * 100)}%` : `at ${(book.iv * ivMult * 100).toFixed(1)}% vol` },
    { label: 'Realized to date', value: money(realized), sub: `${book.closed.length} closed legs` },
    { label: 'Credit collected', value: money(ph.got), sub: 'lifetime, open legs' },
    { label: pn.close >= 0 ? 'Credit to close' : 'Cost to close', value: money(Math.abs(pn.close)), sub: 'to unwind the options' },
    { label: 'Time value', value: money(pn.extrinsic), sub: pn.extrinsic < -1 ? 'short, decays to you' : pn.extrinsic > 1 ? 'long, decays away' : 'all decayed' },
    { label: 'This week', value: money(ph.week), sub: ph.last ? `last on ${new Date(ph.last).toLocaleDateString('en-US', { day: 'numeric', month: 'short' })}` : 'no credits this week' },
  ];

  const layerVal = (k: LayerKey): string => {
    if (k === 'ema') return book.emas.find((e) => e[0] === 'EMA 20') ? priceLab(book.emas.find((e) => e[0] === 'EMA 20')![1]) : '–';
    if (k === 'sr') return book.levels.length ? `${priceLab(Math.min(...book.levels.map((l) => l[1])))}–${priceLab(Math.max(...book.levels.map((l) => l[1])))}` : 'none set';
    if (k === 'last5') return book.d5 ? `${priceLab(book.d5[0])}–${priceLab(book.d5[1])}` : '–';
    if (k === 'targets') return book.target ? priceLab(book.target.median) : 'none';
    if (k === 'cone') { const s = book.iv * ivMult * Math.sqrt(Math.max(dte, 1) / 365); return `1σ ${priceLab(book.spot * Math.exp(-s))}–${priceLab(book.spot * Math.exp(s))}`; }
    return '52 wk';
  };
  const layerCount = LAYER_META.filter((m) => layers[m.key]).length;
  const myPlans = plans.filter((p) => p.ticker === book.ticker);
  const bookMeta = `${book.legs.length} from IBKR · Δ ${signed(netGreeks(book.legs.filter((l) => !off[l.id]), 0, ctx).delta)} · ${money(unrealized(book.legs.filter((l) => !off[l.id]), 0, ctx))} open`;

  return (
    <div className="po">
      <div className="po-page">
        {/* 1 · header */}
        <header className="po-head">
          <div className="po-brand"><span className="dia" /><span>Sunnyfi</span><span className="sl">/</span><span className="pg">Payoff</span></div>
          <nav className="po-nav">
            <a href="/portfolio">Portfolio</a>
            <a href="/positions">Positions</a>
            <a href="/income">Income</a>
            <a className="on">Payoff</a>
          </nav>
          <div className="po-stamp num">{fmtStamp(new Date())}</div>
        </header>

        {/* 2 · ticker strip + quote */}
        <div className="po-quote">
          <div className="po-rail">
            {books.map((b) => (
              <div key={b.ticker} className={'po-tk' + (b.ticker === book.ticker ? ' on' : '')} onClick={() => pickTicker(b.ticker)}>
                <div className="c">{b.ticker}</div>
                <div className="p num">{priceShort(b.spot)}</div>
              </div>
            ))}
          </div>
          <div className="po-name">
            <div className="lab" title={book.name}>{book.name}</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 6 }}>
              <span className="po-spot num">{priceLab(book.spot)}</span>
              <span className={'po-chg num ' + (book.chg < 0 ? 'loss' : 'gain')}>{signed1(book.chg)}%</span>
            </div>
          </div>
          {book.wk52 && (
            <div className="po-wk">
              <div className="lab">52 wk <span style={{ textTransform: 'none', letterSpacing: 0, color: 'var(--ink-2)', marginLeft: 6 }}>{wkWord}</span></div>
              <div className="trk"><div className="mk" style={{ left: `${wkPos}%` }} /></div>
              <div className="ends num"><span>{priceShort(book.wk52[0])}</span><span>{priceShort(book.wk52[1])}</span></div>
            </div>
          )}
          <div className="po-vr" />
          <div className="po-unrl">
            <div className="lab">Unrealized</div>
            <div className="v num" style={{ color: unrl < 0 ? 'var(--loss)' : 'var(--ink)' }}>{money(unrl)}</div>
          </div>
          <div className="po-feed"><span className="dot" />IBKR · {data.date}</div>
        </div>
        <div className="po-hr" />

        {/* 3 · expiration calendar */}
        <div>
          <div className="po-cal-head">
            <span className="lab">Expiration</span>
            <span className="exp">{sel ? fmtExp(sel, today) : '–'}</span>
            <span className="dte num">{dte}d out</span>
            {picking && <span className="po-pill warn">Setting {editing ? legTitle(editing) : 'leg'}</span>}
            <span className="sp" />
            {legExpiries.length > 1 && (
              /* Says what moves the date, now that nothing else does. */
              <span className="lab">turn a leg off to reach {fmtExp(legExpiries[1], today)}</span>
            )}
          </div>
          <div className="po-cal">
            {months.map((m) => (
              <div key={m.key} className="po-mon" style={{ flex: m.days.length }}>
                <div className="h">{m.label}</div>
                <div className="days">
                  {m.days.map((iso) => (
                    <div key={iso}
                      className={'po-day num' + (used.has(iso) ? ' used' : '') + (iso === marked ? ' sel' : '') + (picking ? ' pick' : '')}
                      onClick={() => picking && setLegExpiry(iso)}>
                      <span>{parseISO(iso).getDate()}</span><span className="d" />
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* 4 · metric strip */}
        <div className="po-strip-wrap">
          <div className="po-chev l" onClick={() => stripRef.current?.scrollBy({ left: -(stripRef.current.clientWidth - 80), behavior: 'smooth' })}>‹</div>
          <div className="po-strip" ref={stripRef}>
            {metrics.map((m) => (
              <div key={m.label} className="po-met">
                <div className="lab">{m.label}</div>
                <div className="v num" style={{ color: m.ink }}>{m.value}</div>
                <div className="s num">{m.sub}</div>
              </div>
            ))}
          </div>
          <div className="po-chev r" onClick={() => stripRef.current?.scrollBy({ left: stripRef.current.clientWidth - 80, behavior: 'smooth' })}>›</div>
        </div>

        {/* 5 · chart card */}
        <div className="po-chart">
          <div className="po-greeks">
            <div className="g"><span className="lab">Net delta</span><span className="v num">{signed(g.delta)}</span>{bookG && <span className="b num">book {signed(bookG.delta)}</span>}</div>
            <div className="g"><span className="lab">Theta</span><span className={'v num ' + (g.theta < 0 ? 'loss' : 'gain')}>{g.theta < 0 ? '−' : '+'}{money2(Math.abs(g.theta)).slice(1)}</span>{bookG && <span className="b num">book {bookG.theta < 0 ? '−' : '+'}{money2(Math.abs(bookG.theta)).slice(1)}</span>}</div>
            <div className="g"><span className="lab">Vega</span><span className={'v num ' + (g.vega < 0 ? 'loss' : 'gain')}>{g.vega < 0 ? '−' : '+'}{money(Math.abs(g.vega)).slice(1)}</span>{bookG && <span className="b num">book {bookG.vega < 0 ? '−' : '+'}{money(Math.abs(bookG.vega)).slice(1)}</span>}</div>
            <div className="g"><span className="lab">Implied vol</span><span className="v num">{(book.iv * ivMult * 100).toFixed(1)}%</span></div>
          </div>
          <Chart book={book} ctx={ctx} liveLegs={liveLegs} bookLegs={bookLegs} planActive={planActive}
            elapsed={elapsed} dte={dte} sel={sel} rangePct={rangePct} layers={layers} closes={closes[book.ticker] ?? []} />
          <div className="po-showing">
            <span className="lab">Showing</span>
            <span className="po-sw"><span className="b" style={{ height: 3, background: 'var(--gain)' }} />{elapsed === 0 ? 'Value today' : elapsed >= dte ? 'At expiration' : `${dte - elapsed}d left`}</span>
            {LAYER_META.filter((m) => layers[m.key]).map((m) => (
              <span key={m.key} className="po-sw click" onClick={() => setLayers((l) => ({ ...l, [m.key]: false }))}>
                <span className="b" style={{ height: m.band ? 10 : 3, background: m.ink }} />{m.name} · <span className="v num">{layerVal(m.key)}</span>
              </span>
            ))}
          </div>
        </div>

        {/* 6 · legs card */}
        <div className="po-legs">
          <div className="po-legs-head">
            <span className="sec">Legs</span>
            <span className="meta num">{bookMeta}</span>
            {myPlanned.length > 0 && <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--warn-deep)' }}>{activePlan ? myPlans.find((p) => p.id === activePlan)?.name : 'NEW PLAN'} <span style={{ fontWeight: 400, color: 'var(--warn-ink)' }}>{myPlanned.length} leg{myPlanned.length > 1 ? 's' : ''}</span></span>}
            <span className="sp" />
            {myPlans.filter((p) => p.id !== activePlan).map((p) => {
              const pl = p.legs.reduce((s, l) => s + (l.kind === 'stock' ? 0 : -l.qty * 100 * l.premium), 0);
              return (
                <span key={p.id} className="po-plan-pill">
                  <span className={'tg' + (planOn[p.id] ? ' on' : '')} onClick={() => setPlanOn((o) => ({ ...o, [p.id]: !o[p.id] }))}>{planOn[p.id] ? '✓' : ''}</span>
                  <span className="nm">{p.name}</span>
                  <span className="sm num">{pl >= 0 ? 'Pays' : 'Costs'} {money(Math.abs(pl))} · Δ {signed(netGreeks(p.legs, 0, ctx).delta)}</span>
                  <span className="ed" onClick={() => editSaved(p)}>EDIT</span>
                  <span className="x" onClick={() => { remove.mutate(p.id); setPlanOn((o) => { const n = { ...o }; delete n[p.id]; return n; }); }}>×</span>
                </span>
              );
            })}
            {myPlanned.length > 0 && (
              <>
                <button className="po-btn ink btn-lab" onClick={savePlan} disabled={save.isPending || update.isPending}>{activePlan ? 'Save changes' : 'Save'}</button>
                <button className="po-btn warn btn-lab" onClick={discard}>Discard</button>
              </>
            )}
            <button className={'po-btn btn-lab ' + (myPlanned.length ? 'warn' : 'neon')} onClick={() => { setAddOpen((o) => !o); setLayersOpen(false); }}>Add a leg</button>
            <button className="po-btn ghost" onClick={() => setClosedOpen(true)}>
              <span className="btn-lab-sm">Closed</span>
              <span className="num" style={{ fontSize: 11, color: 'var(--mute-2)' }}>{book.closed.length} closed · {money(realized)} realized</span>
            </button>
            {addOpen && (
              <div className="po-menu">
                {([['Buy', 'call', false], ['Sell', 'call', true], ['Buy', 'put', false], ['Sell', 'put', true]] as const).map(([s, k, sh]) => (
                  <div key={s + k} className="row" onClick={() => addLeg(k, sh)}><span className="s">{s}</span><span className="i">{k === 'call' ? 'Call' : 'Put'}</span></div>
                ))}
                <div className="hr" />
                <div className="row" onClick={() => addLeg('stock', false)}><span className="s">Buy</span><span className="i">{book.ticker}</span><span className="s">100 shares</span></div>
                <div className="row" onClick={() => addLeg('stock', true)}><span className="s">Sell</span><span className="i">{book.ticker}</span><span className="s">100 shares</span></div>
              </div>
            )}
          </div>

          <div className="po-legrow" style={{ marginTop: 14 }}>
            {allLegs.map((l) => {
              const isOff = !!off[l.id];
              const pl = l.kind === 'stock' ? l.qty * (book.spot - (l.basis ?? book.spot))
                : l.qty * 100 * ((elapsed === 0 && l.mark != null ? l.mark : liveMark(l, elapsed, ctx)) - entryOf(l, ctx));
              const mn = moneyness(l, ctx);
              const d = Math.round(l.kind === 'stock' ? l.qty : l.qty * 100 * (liveMark(l, elapsed, ctx) > 0 ? 1 : 0) * 0 + netGreeks([l], elapsed, ctx).delta);
              return (
                <div key={l.id} className={'po-leg' + (isOff ? ' off' : '') + (selLeg === l.id ? ' sel' : '')} onClick={() => l.plan && setSelLeg(l.id)}>
                  <div className="r1">
                    <span className={'tg' + (isOff ? '' : ' on')} onClick={(e) => { e.stopPropagation(); setOff((o) => ({ ...o, [l.id]: !o[l.id] })); }}>{isOff ? '' : '✓'}</span>
                    {l.plan ? <span className="po-tag-plan">Plan</span> : <span className={'po-side ' + (l.qty < 0 ? 'loss' : 'gain')}>{l.qty < 0 ? 'Sold' : 'Bought'}</span>}
                    <span className="sp" />
                    {l.plan
                      ? <span className="ib x" onClick={(e) => { e.stopPropagation(); removeLeg(l.id); }}>×</span>
                      : <span className="ib" onClick={(e) => { e.stopPropagation(); setOpenHist((h) => (h === l.id ? null : l.id)); }}>{openHist === l.id ? '−' : '…'}</span>}
                  </div>
                  <div className="r2">
                    <span className="ttl num">{legTitle(l)}</span>
                    <span className={'pl num ' + (Math.abs(pl) < 1 ? '' : pl < 0 ? 'loss' : 'gain')} style={Math.abs(pl) < 1 ? { color: 'var(--mute)' } : undefined}>{money(pl)}</span>
                  </div>
                  <div className="r3 num">
                    {mn.risk === 'assign' && <span className="po-risk assign">Could be assigned</span>}
                    {mn.risk === 'near' && <span className="po-risk near">Near the strike</span>}
                    <span>Δ {signed(d)}{l.expiry ? ` · ${fmtExp(l.expiry, today)} · ${dteOf(l.expiry, today)}d` : l.basis != null ? ` · basis ${priceLab(l.basis)}` : ''}</span>
                  </div>
                  {l.plan && (
                    <div className="po-step num" onClick={(e) => e.stopPropagation()}>
                      <span className="sb" onClick={() => stepQty(l, -1)}>−</span><span className="q">{signed(l.qty)}</span><span className="sb" onClick={() => stepQty(l, 1)}>+</span>
                      <span className="gap" />
                      <span className="sb" onClick={() => stepPrice(l, -1)}>‹</span><span className="k">{priceShort(l.kind === 'stock' ? (l.basis ?? book.spot) : l.strike)}</span><span className="sb" onClick={() => stepPrice(l, 1)}>›</span>
                    </div>
                  )}
                  {openHist === l.id && !l.plan && (
                    <div className="po-hist">
                      {l.history.map((h, i) => (
                        <div key={i} className="e">
                          <div className="t"><span>{h[0]}</span><span className={'a num'} style={{ color: h[2] > 0 ? 'var(--gain)' : 'var(--ink)' }}>{money(h[2])}</span></div>
                          <div className="d">{h[1]}</div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* 7 · control row */}
        <div className="po-ctl">
          <div className="c" style={{ flex: 1.6 }}>
            <span className="lab">Date</span>
            <div className="hd"><span className="v">{fmtLongDate(new Date(today.getTime() + elapsed * 864e5))}</span><span className="s num">{elapsed === 0 ? 'today' : elapsed >= dte ? 'at expiration' : `${dte - elapsed}d left`}</span></div>
            <input type="range" min={0} max={Math.max(dte, 1)} step={1} value={Math.min(elapsed, dte)} onChange={(e) => setElapsed(+e.target.value)} />
          </div>
          <div className="c" style={{ flex: 1 }}>
            <span className="lab">Range</span>
            <div className="hd"><span className="v num">±{rangePct}%</span></div>
            <input type="range" min={10} max={60} step={1} value={rangePct} onChange={(e) => setRangePct(+e.target.value)} />
          </div>
          <div className="c" style={{ flex: 1 }}>
            <span className="lab">Implied vol</span>
            <div className="hd"><span className="v num">{(book.iv * ivMult * 100).toFixed(1)}%</span><span className="po-reset btn-lab-sm" style={{ opacity: ivMult === 1 ? 0 : 1, pointerEvents: ivMult === 1 ? 'none' : 'auto' }} onClick={() => setIvMult(1)}>Reset</span></div>
            <input type="range" min={50} max={220} step={5} value={Math.round(ivMult * 100)} onChange={(e) => setIvMult(+e.target.value / 100)} />
          </div>
          <div style={{ position: 'relative', flex: 'none' }}>
            <button className="po-btn ghost" style={{ padding: '10px 16px', boxShadow: 'inset 0 0 0 1px var(--hair)' }} onClick={() => { setLayersOpen((o) => !o); setAddOpen(false); }}>
              <span className="btn-lab">Layers</span><span className="num" style={{ fontSize: 11, color: 'var(--mute-2)' }}>{layerCount} of 6</span><span>▾</span>
            </button>
            {layersOpen && (
              <div className="po-layers-pop">
                {LAYER_META.map((m) => (
                  <div key={m.key} className={'po-lay' + (layers[m.key] ? ' on' : '')} onClick={() => setLayers((l) => ({ ...l, [m.key]: !l[m.key] }))}>
                    <span className="sw" style={{ height: m.band ? 10 : 3, background: layers[m.key] ? m.ink : 'var(--rule-2)' }} />
                    <span className="n">{m.name}</span>
                    <span className="pt"><i /></span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* 8 · closed-legs modal */}
      {closedOpen && (
        <>
          <div className="po-scrim" onClick={() => setClosedOpen(false)} />
          <div className="po-modal" role="dialog">
            <div className="hd">
              <span className="sec">Closed legs</span>
              <span className="num" style={{ fontSize: 12, color: 'var(--mute-2)' }}>{book.closed.length} closed · {money(realized)} realized</span>
              <span className="sp" />
              <span className="num" style={{ fontSize: 11, color: 'var(--faint)' }}>{book.closed.filter((c) => c.pnl > 0).length} green · {book.closed.filter((c) => c.pnl < 0).length} red</span>
              <span className="x" onClick={() => setClosedOpen(false)}>×</span>
            </div>
            <div className="body">
              {[...new Set(book.closed.map((c) => c.closedOn.slice(0, 4)))].map((yr) => (
                <div key={yr}>
                  <div className="yr">{yr}</div>
                  {book.closed.filter((c) => c.closedOn.startsWith(yr)).map((c, i) => (
                    <div key={i} className="po-crow">
                      <span className="t num">{c.side === 'sold' ? 'Short' : 'Long'} {c.title}</span>
                      <span className={'o ' + (c.outcome === 'Assigned' || c.outcome === 'Exercised' ? 'warn' : 'mute')}>{c.outcome}</span>
                      <span className="w">{c.when}</span>
                      <span className={'p num ' + (c.pnl < 0 ? 'loss' : 'gain')}>{money(c.pnl)}</span>
                    </div>
                  ))}
                </div>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
