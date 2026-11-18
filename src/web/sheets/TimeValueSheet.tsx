// The Time value panel is the receipt (handoff 2026-11-18 §3.5; CHANGES Nov 16 "App · Time value sheet" and Nov 17
// "Web Time value sheet is the receipt"; SunnyHomeChart view="tv" tvSheet="receipt"). From the right, 580 wide, sheet
// glass over a scrim; the scrim, ✕ or Escape closes it. Top to bottom:
//   the week ("This week · ends Fri Nov 20")
//   one sentence on what needs you; a tap opens the strikes to roll, each with why and a Roll tag
//   Coming in · from what you sold: Calls sold, Puts sold, the time value left with "N% captured of $Y" under it
//   Going out · a week of your hedges: Hedge calls, Hedge puts, in red
//   Net by Friday = the time value left less that week of hedges
//   In the money on its own line (the time value leaves it out)
// Every line opens to its names. No bars. The design's small line per name is left out: there is no series per leg
// to draw it from. Data: brief.timeValue (sunny-home brief.ts): every sold leg still open (`legs`, tvLeft is the time
// value left, intr the in-the-money part a share, `ready` the server's needs-you rule: in the money, 90% captured or
// under 5 cents of time value) and every option bought (`hedges`, a week of decay each, total `hedgeWeek`).
import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { useHome, type J } from '../lib/data';
import { C, money, pct } from '../lib/format';
import { useWeb } from '../lib/state';
import { readyToRoll, strike, tvHedges, tvLeftTotal, tvLegs, type TvHedge, type TvLeg } from '../home/rail/model';

const MU = C.ink2, LN = '1px solid rgba(255,255,255,.08)', OR = '#F2A93B';
/** The pills (dark): grey for time value still to come, red for what goes out or sits in the money. */
const GREY = ['rgba(118,118,128,.32)', C.ink], RED = [C.red, '#000000'];
const sum = <T,>(xs: T[], f: (x: T) => number) => xs.reduce((a, x) => a + f(x), 0);
/** Time value captured: 0% when nothing is (or the legs are worth more than they were sold for). */
const captured = (left: number, col: number) => {
  if (!(col > 0)) return '0%';
  const x = Math.max(0, (1 - left / col) * 100);
  return x < 0.05 ? '0%' : pct(x);
};
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** "This week · ends Fri Nov 20": the Friday of the week on screen (next week's on a weekend); a Friday the market is
    shut ends on the Thursday before. */
function weekWords(p: J): string {
  const today = String(p?.today ?? '');
  const [y, m, d] = today.split('-').map(Number);
  if (!y || !m || !d) return 'This week';
  const t0 = Date.UTC(y, m - 1, d), wd = new Date(t0).getUTCDay();
  const weekend = wd === 0 || wd === 6;
  let end = t0 + (wd === 6 ? 6 : 5 - wd) * 864e5;
  const closed = new Set(((Array.isArray(p?.calendar) ? p.calendar : []) as J[]).filter((c) => c?.kind === 'closed').map((c) => String(c.date)));
  if (closed.has(new Date(end).toISOString().slice(0, 10))) end -= 864e5;
  const e = new Date(end);
  return `${weekend ? 'Next week' : 'This week'} · ends ${DOW[e.getUTCDay()]} ${MON[e.getUTCMonth()]} ${e.getUTCDate()}`;
}

interface Item { k: string; t: string; nm: string; sub: string; v: number; pill: string[] }
interface Line { k: string; l: string; bar: string; v: number; vc: string; col?: number; items: Item[]; aria: string }

/** One row a name, most first; `sub` lists what the name holds on the line. */
function byName<T extends { t: string; name: string }>(xs: T[], v: (x: T) => number, part: (x: T) => string, pill: string[]): Item[] {
  const m = new Map<string, T[]>();
  for (const x of xs) m.set(x.t, [...(m.get(x.t) ?? []), x]);
  return [...m.values()].map((g) => {
    const parts = [...new Set(g.map(part))];
    return { k: g[0].t, t: g[0].t, nm: g[0].name, sub: parts.join(' · '), v: sum(g, v), pill };
  }).sort((a, b) => b.v - a.v);
}

/** The Coming in lines: what was sold, by calls and by puts. Strikes low to high, then "calls" or "puts" once. */
function soldLine(k: string, l: string, bar: string, legs: TvLeg[]): Line | null {
  if (!legs.length) return null;
  const v = sum(legs, (x) => x.tvLeft), col = sum(legs, (x) => x.col), word = legs[0].put ? ' puts' : ' calls';
  const m = new Map<string, TvLeg[]>();
  for (const x of legs) m.set(x.t, [...(m.get(x.t) ?? []), x]);
  const items = [...m.values()].map((g) => {
    const ks = [...new Set(g.map((x) => x.K))].sort((a, b) => a - b).map(strike);
    const gl = sum(g, (x) => x.tvLeft), gc = sum(g, (x) => x.col);
    return { k: g[0].t, t: g[0].t, nm: g[0].name, sub: `${ks.join(' · ')}${word} · ${captured(gl, gc)} captured`, v: gl, pill: GREY };
  }).sort((a, b) => b.v - a.v);
  return { k, l, bar, v, vc: C.ink, col, items, aria: `${l}, ${money(v)} left to earn, ${captured(v, col)} captured of ${money(col)} sold` };
}

/** The Going out lines: a week of decay on the hedges. */
function hedgeLine(k: string, l: string, bar: string, hs: TvHedge[]): Line | null {
  if (!hs.length) return null;
  const word = hs[0].put ? ' puts' : ' calls';
  const v = sum(hs, (x) => x.week);
  return { k, l, bar, v, vc: C.red, aria: `${l}, ${money(v)} a week`,
    items: byName(hs, (x) => x.week, (x) => `${strike(x.K)}${word}${x.exLabel ? ' · ' + x.exLabel : ''}`, RED) };
}

/** Pins each list's order the first time it is drawn while the panel is open, so the rows never move under the eye
    as the numbers tick (Nik: stable while viewing). New rows join at the end. */
function useStable() {
  const seen = useRef(new Map<string, string[]>());
  return <T extends { k: string }>(id: string, xs: T[]): T[] => {
    const by = new Map(xs.map((x) => [x.k, x]));
    const keys = (seen.current.get(id) ?? []).filter((k) => by.has(k));
    for (const x of xs) if (!keys.includes(x.k)) keys.push(x.k);
    seen.current.set(id, keys);
    return keys.map((k) => by.get(k)!);
  };
}

export default function TimeValueSheet() {
  const { book, setTvOpen, mask } = useWeb();
  const { data } = useHome(book);
  const p = data?.payload;
  const close = () => setTvOpen(false);
  const xRef = useRef<HTMLButtonElement>(null);
  const [rollOpen, setRollOpen] = useState(false);
  const [open, setOpen] = useState<string | null>(null);
  const stable = useStable();

  useEffect(() => {
    const was = document.activeElement as HTMLElement | null;
    xRef.current?.focus({ preventScroll: true });
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') setTvOpen(false); };
    window.addEventListener('keydown', key);
    // The page behind stays put while the panel is open.
    const html = document.documentElement, ov = html.style.overflow;
    html.style.overflow = 'hidden';
    return () => { window.removeEventListener('keydown', key); html.style.overflow = ov; was?.focus?.({ preventScroll: true }); };
  }, [setTvOpen]);
  // Another account on screen: everything closes and reads the new book.
  useEffect(() => { setRollOpen(false); setOpen(null); }, [book]);

  const r = useMemo(() => {
    const legs = tvLegs(p).filter((l) => l.wk), hedges = tvHedges(p);   // this week's sold strikes only
    const left = tvLeftTotal(p) ?? 0;
    const hedgeWeek = p?.brief?.timeValue?.hedgeWeek != null ? Number(p.brief.timeValue.hedgeWeek) : sum(hedges, (h) => h.week);
    const ready = readyToRoll(legs), ok = legs.filter((l) => !l.ready);
    const inn = [soldLine('c', 'Calls sold', '#327133', legs.filter((l) => !l.put)), soldLine('p', 'Puts sold', '#2E5ECA', legs.filter((l) => l.put))]
      .filter((x): x is Line => !!x);
    const out = [hedgeLine('oc', 'Hedge calls', C.green, hedges.filter((h) => !h.put)), hedgeLine('ip', 'Hedge puts', '#73B6F9', hedges.filter((h) => h.put))]
      .filter((x): x is Line => !!x);
    const itmLegs = legs.filter((l) => l.intr > 0);
    const itmV = sum(itmLegs, (l) => l.intr * l.q * 100);
    const itm: Line | null = itmLegs.length ? {
      k: 'itm', l: 'In the money', bar: C.red, v: itmV, vc: C.red, aria: `In the money, ${money(itmV)}`,
      items: byName(itmLegs, (l) => l.intr * l.q * 100, (l) => `${strike(l.K)} ${l.put ? 'puts' : 'calls'} sold · by ${l.intr.toFixed(2)}`, RED),
    } : null;
    return { any: legs.length > 0, when: weekWords(p), legs, ready, ok, left, okLeft: sum(ok, (l) => l.tvLeft), inn, out, itm, net: left - hedgeWeek };
  }, [p]);

  /** The sentence (159b): what needs you, then what is on track. */
  const sn = (() => {
    const n = r.ready.length, nO = r.ok.length, nA = r.legs.length;
    if (n) return { lead: `${n} ${n === 1 ? 'strike needs you.' : 'strikes need you.'}`, r1: nO ? ` The other ${nO} ${nO === 1 ? 'is' : 'are'} on track, ` : '', m: nO ? r.okLeft : null, r2: nO ? ' to earn by Friday.' : '' };
    return { lead: 'Nothing needs you this week.', r1: nA === 1 ? ' Your one strike is on track, ' : ` All ${nA} strikes are on track, `, m: r.left, r2: ' to earn by Friday.' };
  })();
  const snText = sn.lead + sn.r1 + (sn.m != null ? money(sn.m) : '') + sn.r2;

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 30, display: 'flex', justifyContent: 'flex-end' }}>
      <style>{TV_CSS}</style>
      <button type="button" aria-label="Close" tabIndex={-1} className="bare scrim" onClick={close} style={{ position: 'absolute', inset: 0 }} />
      <div role="dialog" aria-modal="true" aria-label="Time value" className="glass-sheet tnum"
        style={{ position: 'relative', width: 580, maxWidth: '100%', height: '100%', padding: '28px 30px 32px', display: 'flex', flexDirection: 'column', gap: 20,
          overflowY: 'auto', overscrollBehavior: 'contain' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
          <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
            <span role="heading" aria-level={2} style={{ fontSize: 22, lineHeight: '28px', fontWeight: 700, letterSpacing: '-.01em' }}>Time value</span>
            {p && <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 500, color: MU }}>{r.when}</span>}
          </span>
          <button ref={xRef} type="button" onClick={close} aria-label="Close" className="xbtn"
            style={{ flex: 'none', width: 32, height: 32, fontSize: 13, color: '#AEAEB2' }}>✕</button>
        </div>

        {!p ? null : !r.any ? (
          // An account with nothing sold: the phone's one line, no zero lines.
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <span style={{ fontSize: 20, fontWeight: 700 }}>Nothing sold yet</span>
            <span style={{ fontSize: 15, color: MU }}>Time value shows here once calls or puts are sold.</span>
          </div>
        ) : (
          <>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {/* The sentence; with strikes to roll it opens them. */}
              <button type="button" className="bare tv-tap" onClick={r.ready.length ? () => setRollOpen((o) => !o) : undefined}
                aria-expanded={r.ready.length ? rollOpen : undefined} aria-label={mask(snText)}
                style={{ cursor: r.ready.length ? 'pointer' : 'default', display: 'block', fontSize: 19, lineHeight: '26px', fontWeight: 400, textWrap: 'pretty' } as CSSProperties}>
                <span style={{ fontWeight: 600 }}>{sn.lead}</span>
                {r.ready.length > 0 && <Chev open={rollOpen} size={13} style={{ display: 'inline-block', verticalAlign: -1, margin: '0 2px 0 5px' }} />}
                <span>{sn.r1}</span>{sn.m != null && <span>{mask(money(sn.m))}</span>}<span>{sn.r2}</span>
              </button>
              {rollOpen && r.ready.length > 0 && (
                <div role="list" aria-label="Strikes to roll" className="tv-in"
                  style={{ display: 'flex', flexDirection: 'column', padding: '0 16px', borderRadius: 18, background: 'rgba(255,255,255,.06)', boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.1)' }}>
                  {r.ready.map((l, i) => {
                    const itm = l.intr > 0 || l.itm;
                    const why = itm ? `In the money by ${l.intr.toFixed(2)}` : `${Math.abs(l.cap)}% ${l.cap < 0 ? 'lost' : 'captured'} · `;
                    return (
                      <div key={`${l.t}|${l.put ? 'p' : 'c'}|${l.K}|${l.ex}`} role="listitem"
                        style={{ display: 'grid', gridTemplateColumns: '32px minmax(0,1fr) auto', gap: 12, alignItems: 'center', padding: '14px 0', borderTop: i ? LN : 'none' }}>
                        <Logo t={l.t} size={32} />
                        <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                          <span style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'baseline', gap: '2px 6px' }}>
                            <span style={{ fontSize: 15, lineHeight: '19px', fontWeight: 600 }}>{l.name}</span>
                            <span style={{ fontSize: 13, lineHeight: '17px', fontWeight: 500, color: MU }}>{strike(l.K)} {l.put ? 'puts' : 'calls'} sold ×{l.q}</span>
                          </span>
                          <span style={{ fontSize: 13, lineHeight: '17px', fontWeight: 600, color: itm ? C.red : OR }}>
                            {why}{!itm && <>{mask(money(l.tvLeft))} left</>}
                          </span>
                        </span>
                        <span style={{ flex: 'none', height: 24, padding: '0 10px', borderRadius: 12, display: 'inline-flex', alignItems: 'center',
                          fontSize: 12, fontWeight: 600, color: OR, background: 'rgba(242,169,59,.18)' }}>Roll</span>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            <div style={{ display: 'flex', flexDirection: 'column' }}>
              <Kicker>Coming in · from what you sold</Kicker>
              {r.inn.map((l) => (
                <LineRow key={l.k} l={l} tall open={open === l.k} toggle={() => setOpen(open === l.k ? null : l.k)} items={stable(l.k, l.items)}
                  sub={<>{captured(l.v, l.col ?? 0)} captured of {mask(money(l.col))}</>} unit="left" />
              ))}
              {r.out.length > 0 && <>
                <Kicker top>Going out · a week of your hedges</Kicker>
                {r.out.map((l) => (
                  <LineRow key={l.k} l={l} open={open === l.k} toggle={() => setOpen(open === l.k ? null : l.k)} items={stable(l.k, l.items)} />
                ))}
              </>}
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12, marginTop: 10, padding: '14px 22px 0 0', borderTop: `1.5px solid ${C.ink}` }}>
                <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 700 }}>Net by Friday</span>
                <span style={{ fontSize: 24, lineHeight: '28px', fontWeight: 800, letterSpacing: '-.01em', color: Math.round(r.net) < 0 ? C.red : C.ink }}>{mask(money(r.net))}</span>
              </div>
            </div>

            {r.itm && (
              <div style={{ display: 'flex', flexDirection: 'column', paddingTop: 6, borderTop: '1px solid rgba(255,255,255,.14)' }}>
                <LineRow l={r.itm} dot open={open === 'itm'} toggle={() => setOpen(open === 'itm' ? null : 'itm')} items={stable('itm', r.itm.items)} />
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}

const TV_CSS = `@keyframes tvFade{from{opacity:0}to{opacity:1}}.sw .tv-in{animation:tvFade .25s ease both}.sw .tv-tap:active{opacity:.6}`;

function Kicker({ children, top }: { children: ReactNode; top?: boolean }) {
  return <span style={{ padding: top ? '14px 0 2px' : '0 0 2px', fontSize: 13, lineHeight: '18px', fontWeight: 600, color: MU }}>{children}</span>;
}

function Chev({ open, size = 12, style }: { open: boolean; size?: number; style?: CSSProperties }) {
  return (
    <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24"
      style={{ flex: 'none', color: MU, transform: open ? 'rotate(90deg)' : 'none', transition: 'transform .25s ease', ...style }}>
      <path d="M9 6l6 6-6 6" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 3, strokeLinecap: 'round', strokeLinejoin: 'round' }} />
    </svg>
  );
}

/** A receipt line: a colour bar (a dot for In the money), the label (and its captured line), the figure and a chevron;
    open, its names: logo, name, what, and a pill. */
function LineRow({ l, open, toggle, items, sub, unit, tall, dot }:
  { l: Line; open: boolean; toggle: () => void; items: Item[]; sub?: ReactNode; unit?: string; tall?: boolean; dot?: boolean }) {
  const { mask } = useWeb();
  return (
    <div style={{ display: 'flex', flexDirection: 'column' }}>
      <button type="button" className="bare tv-tap" onClick={toggle} aria-expanded={open} aria-label={mask(l.aria)}
        style={{ display: 'grid', gridTemplateColumns: `${dot ? 8 : 4}px minmax(0,1fr) auto 12px`, gap: 10, alignItems: 'center', minHeight: 46, padding: tall ? '6px 0' : 0 }}>
        <span aria-hidden="true" style={dot ? { width: 8, height: 8, borderRadius: '50%', background: l.bar } : { height: tall ? 32 : 16, borderRadius: 2, background: l.bar }} />
        <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <span style={{ fontSize: dot ? 15 : 16, lineHeight: '20px', fontWeight: 500 }}>{l.l}</span>
          {sub && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 500, color: MU }}>{sub}</span>}
        </span>
        <span style={{ whiteSpace: 'nowrap' }}>
          <span style={{ fontSize: dot ? 15 : 16, lineHeight: '20px', fontWeight: 600, color: l.vc }}>{mask(money(l.v))}</span>
          {unit && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 500, color: MU }}> {unit}</span>}
        </span>
        <Chev open={open} />
      </button>
      {open && (
        <div role="list" aria-label={`${l.l} by name`} className="tv-in" style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: `2px 22px 14px ${dot ? 18 : 14}px` }}>
          {items.map((i) => (
            <div key={i.k} role="listitem" style={{ display: 'grid', gridTemplateColumns: '24px minmax(0,1fr) auto', gap: 10, alignItems: 'center', minHeight: 40 }}>
              <Logo t={i.t} size={24} />
              <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
                <span style={{ fontSize: 14, lineHeight: '18px', fontWeight: 600 }}>{i.nm}</span>
                <span style={{ fontSize: 12, lineHeight: '15px', fontWeight: 500, color: MU, textWrap: 'pretty' } as CSSProperties}>{i.sub}</span>
              </span>
              <span style={{ minWidth: 68, height: 28, padding: '0 9px', borderRadius: 7, display: 'flex', alignItems: 'center', justifyContent: 'center',
                background: i.pill[0], color: i.pill[1], fontSize: 13, lineHeight: '16px', fontWeight: 600, whiteSpace: 'nowrap' }}>{mask(money(i.v))}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/** A company logo (public/logos/TICKER.png) at 74% of a white disc; the ticker when there is no logo. */
function Logo({ t, size }: { t: string; size: number }) {
  const [bad, setBad] = useState(false);
  useEffect(() => setBad(false), [t]);
  return (
    <span aria-hidden="true" style={{ width: size, height: size, borderRadius: '50%', background: '#FFFFFF', boxShadow: '0 0 0 .5px rgba(0,0,0,.12)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
      {bad
        ? <span style={{ fontSize: size > 28 ? 9 : 7, lineHeight: '10px', fontWeight: 700, color: '#1D1D1F' }}>{t.slice(0, 4)}</span>
        : <img src={`/logos/${encodeURIComponent(t)}.png`} alt="" draggable={false} onError={() => setBad(true)}
            style={{ width: '74%', height: '74%', objectFit: 'contain', pointerEvents: 'none' }} />}
    </span>
  );
}
