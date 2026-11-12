// The SD calculator card under the Positions chart: "What to sell" (handoff 2026-11-11-sd-whatif-totals, README 1;
// App Explorations 143a; SunnySD.dc.html with `web` true). Always dark. Top to bottom: the name and price, the expiry,
// the signals, how many to sell and at which strike, then what the sale does (Held, + New and = Both on one price
// scale), the Calls and Puts cards, the footer and Try in What if.
// The numbers come from sdView (model.ts), which runs the engine's sale() once per pick (Positions memoizes it).
// Labels never overlap: a label that would touch another moves to the next row (web gaps 11% for pills, 16% for
// breakevens, and never closer than their own widths), and is kept 9 to 91% along the bar and on the card.
import { useLayoutEffect, useState, type CSSProperties, type ReactNode } from 'react';
import type { Trade } from '../model';
import { P, STRIPES, type Be, type Lane, type Pill, type SdTrade, type SdView, type Side } from './model';

type Rows = Omit<Trade, 'id' | 'on'>[];
const EASE = 'cubic-bezier(.3,1.1,.4,1)';
// Positions move 0.45 s; nothing moves with Reduce Motion.
const CSS = `.sdm{transition:left .45s ${EASE},width .45s ${EASE}}@media (prefers-reduced-motion:reduce){.sdm{transition:none!important}}`
  + '.sdin:focus-visible{box-shadow:inset 0 0 0 1.5px #F5F5F7!important}';
const kick: CSSProperties = { fontSize: 11, lineHeight: '14px', fontWeight: 600, letterSpacing: '.05em', textTransform: 'uppercase', color: P.muT };
const pretty = { textWrap: 'pretty' } as CSSProperties;
const GLASS = 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)';
/** Collision gaps along the bar, in %: pills, breakevens, Both's breakevens (README 1.6, web). */
const GP = 11, GB = 16, GB2 = 19;

export function SdCard({ v, t, busy, failed, mask, onTry, sdIn }: {
  v: SdView | null; t: string; busy: boolean; failed: boolean; mask: (s: string) => string;
  /** Try in What if: the sale's rows, or null to take it off. */
  onTry?: (x: Rows | null) => void;
  /** The SD sale the What if holds for this name now. */
  sdIn?: Trade[];
}) {
  return (
    <div className="tnum" style={{ fontFamily: "'Inter',system-ui,-apple-system,sans-serif", color: P.ink }}>
      <style>{CSS}</style>
      <section aria-label="What to sell" aria-busy={busy}
        style={{ boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: 20, padding: '22px 24px', borderRadius: 22, background: P.bg,
          boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.10)', overflow: 'hidden', opacity: busy && v ? 0.55 : 1, transition: 'opacity .2s' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 20, lineHeight: '24px', fontWeight: 700 }}>{v ? v.tt : t}</span>
          {v && <span style={{ fontSize: 13, lineHeight: '18px', color: P.mu }}>{v.sub}</span>}
        </div>
        {!v ? (
          failed ? <span style={{ fontSize: 13, color: P.mu }}>Could not load {t}.</span> : <div style={{ minHeight: 640 }} />
        ) : <Body v={v} mask={mask} onTry={onTry} sdIn={sdIn} live={!busy && v.t === t} />}
      </section>
    </div>
  );
}

function Body({ v, mask, onTry, sdIn, live }: { v: SdView; mask: (s: string) => string; onTry?: (x: Rows | null) => void; sdIn?: Trade[]; live: boolean }) {
  return (
    <>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        {/* The expiry: a glass segmented control, 50 tall, the picked one a glass thumb; the dot marks earnings. */}
        <div role="radiogroup" aria-label="Expiry"
          style={{ display: 'grid', gridTemplateColumns: `repeat(${v.exps.length},minmax(0,1fr))`, padding: 2, borderRadius: 16, background: P.trk }}>
          {v.exps.map((e) => (
            <button key={e.key} type="button" role="radio" aria-checked={e.on} onClick={e.go} className="bare"
              style={{ boxSizing: 'content-box', height: 50, borderRadius: 14, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 1,
                color: e.on ? P.ink : P.mu, background: e.on ? 'rgba(255,255,255,.20)' : 'transparent', boxShadow: e.on ? GLASS : 'none', cursor: 'pointer' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 14, lineHeight: '18px', fontWeight: e.on ? 600 : 500 }}>
                {e.t}
                {e.isE && <span title="Earnings before this expiry" style={{ width: 5, height: 5, borderRadius: 3, background: P.OR }} />}
              </span>
              <span style={{ fontSize: 11, lineHeight: '14px', fontWeight: 500, color: P.mu }}>{e.d}</span>
            </button>
          ))}
        </div>
        {/* The signals: outlined so they never read as a strike tile; they scroll sideways. */}
        <div role="list" aria-label="Signals" className="noscroll" style={{ display: 'flex', gap: 8, overflowX: 'auto' }}>
          {v.sig.map((g) => (
            <div key={g.key} role="listitem"
              style={{ flex: 'none', width: 180, minHeight: 108, boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: 3, padding: '12px 14px 10px',
                borderRadius: 16, boxShadow: 'inset 0 0 0 1px ' + P.ring }}>
              <span style={kick}>{g.k}</span>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, flexWrap: 'wrap' }}>
                <span style={{ fontSize: 20, lineHeight: '26px', fontWeight: 700, color: g.vc }}>{g.v}</span>
                <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: g.tagc }}>{g.tag}</span>
              </div>
              {g.s && <span style={{ fontSize: 12, lineHeight: '16px', color: P.muT }}>{g.s}</span>}
              <div style={{ marginTop: 'auto', display: 'flex', flexDirection: 'column', gap: 1, paddingTop: 4 }}>
                {g.fx.map((x) => <span key={x.key} style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: x.c }}>→ {x.t}</span>)}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div aria-label="How many" style={{ display: 'flex', alignItems: 'flex-start', columnGap: 16, rowGap: 12, flexWrap: 'wrap' }}>
          {v.rng.map((s) => <Count key={s.key} s={s} mask={mask} />)}
        </div>
        {/* The strikes: calls then puts, one strip that scrolls sideways; the suggestion has a dot, the pick is inverted. */}
        <div aria-label="Strikes" className="noscroll" style={{ display: 'flex', alignItems: 'flex-start', gap: 16, overflowX: 'auto', margin: '0 -24px', padding: '0 24px' }}>
          {v.rng.map((s) => (
            <div key={s.key} style={{ flex: 'none', display: 'flex', flexDirection: 'column', gap: 6, paddingLeft: s.key === 'p' ? 16 : 0, borderLeft: s.key === 'p' ? '1px solid ' + P.rule : 'none' }}>
              <span style={{ fontSize: 11, lineHeight: '14px', fontWeight: 500, color: P.mu }}>{s.rT}</span>
              <div role="group" aria-label={s.h + ' strike'} style={{ display: 'flex', gap: 6 }}>
                {s.o.map((o) => {
                  const mc = o.on ? P.cdMu : P.muT;
                  return (
                    <button key={o.key} type="button" aria-pressed={o.on} onClick={o.go} className="bare"
                      style={{ flex: 'none', width: 92, boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: 1, padding: '10px 12px', borderRadius: 14, cursor: 'pointer',
                        background: o.on ? P.ink : P.tile, color: o.on ? P.cd : P.ink, fontVariantNumeric: 'tabular-nums', transition: 'background .2s,color .2s' }}>
                      <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 4, fontSize: 11, lineHeight: '14px', fontWeight: 600, color: mc }}>
                        {o.sd}
                        {o.sug && <span aria-label="suggested" style={{ width: 7, height: 7, borderRadius: 4, background: s.c }} />}
                      </span>
                      <span style={{ fontSize: 22, lineHeight: '28px', fontWeight: 700 }}>{o.strike}</span>
                      <span style={{ fontSize: 12, lineHeight: '16px', color: mc }}>{o.pr}</span>
                      {/* "≈ 81.1% won" is a hair wider than the tile: it runs into the padding, never wraps. */}
                      <span style={{ fontSize: 12, lineHeight: '16px', color: mc, minHeight: 16, whiteSpace: 'nowrap' }}>{o.won}</span>
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>

      <Sale v={v} mask={mask} onTry={onTry} sdIn={sdIn} live={live} />
      <span style={{ fontSize: 12, lineHeight: '16px', color: P.mu, ...pretty }}>{v.foot}</span>
    </>
  );
}

/** Sell call / Sell put: a number field and a − + stepper, then the hint (README 1.4). */
function Count({ s, mask }: { s: Side; mask: (x: string) => string }) {
  const [txt, setTxt] = useState<string | null>(null);
  const put = s.key === 'p', aria = put ? 'Puts to sell' : 'Calls to sell', can = s.n > 0;
  const step = (n: number) => { setTxt(null); s.set(n); };
  const btn: CSSProperties = { width: 44, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center', color: P.ink };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: put ? 'flex-end' : 'flex-start', gap: 6, marginLeft: put ? 'auto' : 0 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, minHeight: 32 }}>
        <span style={{ ...kick, flex: 'none', display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ width: 8, height: 8, borderRadius: 4, background: s.c }} />{s.h}
        </span>
        <div role="group" aria-label={aria} style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 8 }}>
          <input className="sdin" type="text" inputMode="numeric" pattern="[0-9]*" aria-label={aria} value={txt ?? String(s.n)}
            onChange={(e) => { const x = e.target.value.replace(/\D/g, '').slice(0, 3); setTxt(x); s.set(x === '' ? 0 : +x); }}
            onBlur={() => setTxt(null)} onFocus={(e) => e.currentTarget.select()}
            style={{ boxSizing: 'border-box', width: 52, height: 32, padding: '0 10px', margin: 0, border: 0, outline: 'none', borderRadius: 10, background: 'transparent',
              textAlign: 'right', fontFamily: 'inherit', fontSize: 17, lineHeight: '22px', fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: P.ink, boxShadow: 'inset 0 0 0 1px ' + P.ring }} />
          <div style={{ display: 'flex', alignItems: 'center', height: 32, borderRadius: 16, background: P.trk }}>
            <button type="button" className="bare" aria-label={put ? 'One fewer put' : 'One fewer call'} disabled={!can} onClick={() => step(s.n - 1)}
              style={{ ...btn, opacity: can ? 1 : 0.35, cursor: can ? 'pointer' : 'default' }}>
              <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><path d="M2.5 7h9" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round' }} /></svg>
            </button>
            <span aria-hidden="true" style={{ width: 1, height: 16, background: P.ring }} />
            <button type="button" className="bare" aria-label={put ? 'One more put' : 'One more call'} disabled={s.n >= 999} onClick={() => step(s.n + 1)} style={{ ...btn, cursor: 'pointer' }}>
              <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><path d="M2.5 7h9M7 2.5v9" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round' }} /></svg>
            </button>
          </div>
        </div>
      </div>
      {s.hint && <span style={{ fontSize: 12, lineHeight: '16px', color: s.hc }}>{mask(s.hint)}</span>}
    </div>
  );
}

/** A width that follows the element (a callback ref, so it starts once the element is there). */
function useWidth() {
  const [el, setEl] = useState<HTMLElement | null>(null);
  const [w, setW] = useState(0);
  useLayoutEffect(() => {
    if (!el) return;
    const ro = new ResizeObserver(() => setW(el.clientWidth));
    ro.observe(el); setW(el.clientWidth);
    return () => ro.disconnect();
  }, [el]);
  return [setEl, w] as const;
}

/** What the sale does (README 1.6 to 1.8): the sentence, the three lanes, the Calls and Puts cards, the footer. */
function Sale({ v, mask, onTry, sdIn, live }: { v: SdView; mask: (s: string) => string; onTry?: (x: Rows | null) => void; sdIn?: Trade[]; live: boolean }) {
  const [ref, pw] = useWidth();
  // Narrow (the panel under 600 wide): the lane labels sit above each bar, as in the app; the cards stack under 640.
  const narrow = pw > 0 && pw < 600, stack = pw > 0 && pw < 640;
  return (
    <div ref={ref} aria-label="What the sale does"
      style={{ display: 'flex', flexDirection: 'column', gap: 20, padding: 18, borderRadius: 20, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.16)' }}>
      <p style={{ margin: 0, fontSize: 17, lineHeight: '24px', ...pretty }}>
        {v.head.map((r, i) => <span key={i} style={{ fontWeight: r.w, color: r.c }}>{mask(r.t)}</span>)}
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', columnGap: 12, rowGap: 8, flexWrap: 'wrap' }}>
          <span style={kick}>{v.gT}</span>
          <div style={{ display: 'flex', alignItems: 'center', columnGap: 12, rowGap: 6, flexWrap: 'wrap' }}>
            {v.legend.map((x) => (
              <span key={x.key} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, lineHeight: '16px', color: P.muT }}>
                <span style={{ width: 16, height: 8, borderRadius: 4, boxSizing: 'border-box', background: x.bg, boxShadow: x.sh }} />{x.t}
              </span>
            ))}
          </div>
        </div>
        <Lanes v={v} narrow={narrow} mask={mask} />
      </div>
      {v.cards.length > 0 && (
        <div style={{ display: 'grid', gridTemplateColumns: stack ? 'minmax(0,1fr)' : 'repeat(2,minmax(0,1fr))', gap: 10 }}>
          {v.cards.map((cd) => (
            <div key={cd.key} style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 14, padding: 16, borderRadius: 18, background: 'rgba(255,255,255,.045)' }}>
              <span style={{ ...kick, display: 'flex', alignItems: 'center', gap: 8 }}><span style={{ width: 8, height: 8, borderRadius: 4, background: cd.col }} />{cd.h}</span>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2,minmax(0,1fr))' }}>
                {cd.cols.map((cl) => (
                  <div key={cl.key} style={{ minWidth: 0, display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 10,
                    padding: cl.key === 'h' ? '0 14px 0 0' : '0 0 0 14px', borderLeft: cl.key === 'h' ? 'none' : '1px solid ' + P.rule }}>
                    <Chip k={cl.key} />
                    {cl.legs.map((lg) => (
                      <div key={lg.key} style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                        <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 700, color: cd.col }}>{lg.K}</span>
                        <span style={{ fontSize: 12, lineHeight: '16px', color: P.muT }}>{mask(lg.pr)}</span>
                        <span style={{ fontSize: 12, lineHeight: '16px', color: P.mu }}>{lg.mv}</span>
                      </div>
                    ))}
                    {cl.legs.length ? (
                      <div style={{ marginTop: 'auto', display: 'flex', flexDirection: 'column', gap: 1 }}>
                        <span style={{ fontSize: 11, lineHeight: '14px', fontWeight: 600, color: P.mu }}>Breakeven</span>
                        <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 700 }}>{cl.be}</span>
                        <span style={{ fontSize: 11, lineHeight: '14px', color: P.mu }}>{cl.beS}</span>
                      </div>
                    ) : <span style={{ fontSize: 13, lineHeight: '18px', color: P.mu, ...pretty }}>{cl.emT}</span>}
                  </div>
                ))}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 8, paddingTop: 14, borderTop: '1px solid ' + P.rule }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, lineHeight: '14px', fontWeight: 700, letterSpacing: '.04em', textTransform: 'uppercase' }}>
                  <span style={{ fontSize: 15, lineHeight: '14px', fontWeight: 600, color: P.muT }}>=</span>Both · breakeven
                </span>
                <div style={{ display: 'flex', alignItems: 'baseline', columnGap: 8, rowGap: 2, flexWrap: 'wrap' }}>
                  {cd.from && <><span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, color: P.mu }}>{cd.from}</span><span style={{ fontSize: 15, lineHeight: '20px', color: P.mu }}>→</span></>}
                  <span style={{ fontSize: 26, lineHeight: '32px', fontWeight: 700, letterSpacing: '-.02em' }}>{cd.bV}</span>
                  <span style={{ fontSize: 13, lineHeight: '18px', color: P.muT }}>{cd.bS}</span>
                </div>
                {cd.ch && <span style={{ padding: '4px 10px', borderRadius: 10, fontSize: 13, lineHeight: '18px', fontWeight: 600, background: cd.ch.bg, color: cd.ch.c, ...pretty }}>{cd.ch.t}</span>}
              </div>
            </div>
          ))}
        </div>
      )}
      {v.gone && <span style={{ fontSize: 12, lineHeight: '16px', color: P.mu, ...pretty }}>{v.gone}</span>}
      {onTry && <TryIt v={v} onTry={onTry} sdIn={sdIn} live={live} />}
    </div>
  );
}

/** Held (outlined), New (filled ink), Both (grey). */
function Chip({ k, children }: { k: 'h' | 'n' | 'b'; children?: ReactNode }) {
  const s = k === 'h' ? { background: P.bg, color: P.ink, boxShadow: 'inset 0 0 0 1.5px ' + P.muT } : k === 'n' ? { background: P.ink, color: P.bg } : { background: P.nB, color: P.ink };
  return (
    <span style={{ flex: 'none', height: 20, padding: '0 8px', borderRadius: 10, boxSizing: 'border-box', display: 'inline-flex', alignItems: 'center',
      fontSize: 11, lineHeight: '14px', fontWeight: 700, letterSpacing: '.04em', textTransform: 'uppercase', ...s }}>
      {children ?? (k === 'h' ? 'Held' : k === 'n' ? 'New' : 'Both')}
    </span>
  );
}

/* ── Label layout ─────────────────────────────────────────────────────── */
let ctx: CanvasRenderingContext2D | null = null;
const textW = (s: string, wt: number, px: number) => {
  if (!ctx && typeof document !== 'undefined') ctx = document.createElement('canvas').getContext('2d');
  if (!ctx) return s.length * px * 0.6;
  ctx.font = `${wt} ${px}px Inter, system-ui, sans-serif`;
  return ctx.measureText(s).width;
};
type Placed<T> = T & { row: number; left: string };
/** Left to right, each label takes the first row where it touches nothing: closer than `gap` % along the bar, or
    than half their two widths plus 8 px. Kept 9 to 91% and on the bar. `max` rows; the last takes the rest. */
function lay<T extends { xv: number; w: number }>(items: T[], W: number, gap: number, max: number): Placed<T>[] {
  const rows: { xv: number; cx: number; w: number }[][] = [];
  return [...items].sort((a, b) => a.xv - b.xv).map((it) => {
    let cx = 0, left: string;
    if (W > 0) {
      const lo = Math.max(W * 0.09, it.w / 2), hi = Math.min(W * 0.91, W - it.w / 2);
      cx = lo > hi ? W / 2 : Math.min(hi, Math.max(lo, (it.xv / 100) * W));
      left = cx.toFixed(1) + 'px';
    } else left = Math.min(91, Math.max(9, it.xv)).toFixed(2) + '%';
    const hit = (o: { xv: number; cx: number; w: number }) => Math.abs(it.xv - o.xv) < gap || (W > 0 && Math.abs(cx - o.cx) < (it.w + o.w) / 2 + 8);
    let r = rows.findIndex((row) => row.every((o) => !hit(o)));
    if (r < 0) { if (rows.length < max) { rows.push([]); r = rows.length - 1; } else r = max - 1; }
    rows[r].push({ xv: it.xv, cx, w: it.w });
    return { ...it, row: r, left };
  });
}
const nRows = (xs: { row: number }[]) => (xs.length ? Math.max(...xs.map((x) => x.row)) + 1 : 0);
const pct = (x: number) => x.toFixed(3) + '%';

/** Held, + New, = Both on one price scale (143a): web labels in a 150 px column; today dashed through all three. */
function Lanes({ v, narrow, mask }: { v: SdView; narrow: boolean; mask: (s: string) => string }) {
  const [ref, W] = useWidth();
  const cols = narrow ? 'minmax(0,1fr)' : '150px minmax(0,1fr)';
  const [tl] = lay([{ xv: v.todayX, w: textW(v.todayT, 600, 11) }], W, 0, 1);
  return (
    <div aria-label="Held, New and Both" style={{ display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'grid', gridTemplateColumns: cols, columnGap: 20 }}>
        {!narrow && <span />}
        <div ref={ref} style={{ position: 'relative', height: 18 }}>
          <span className="sdm" style={{ position: 'absolute', top: 0, left: tl.left, transform: 'translateX(-50%)', fontSize: 11, lineHeight: '14px', fontWeight: 600, color: P.muT, whiteSpace: 'nowrap' }}>{v.todayT}</span>
        </div>
      </div>
      {v.lanes.map((ln, i) => <LaneRow key={ln.key} ln={ln} i={i} W={W} cols={cols} narrow={narrow} todayX={v.todayX} mask={mask} />)}
    </div>
  );
}

function LaneRow({ ln, i, W, cols, narrow, todayX, mask }: { ln: Lane; i: number; W: number; cols: string; narrow: boolean; todayX: number; mask: (s: string) => string }) {
  const isB = ln.key === 'b', thk = isB ? 14 : 10;
  const pills = lay(ln.pills.map((p) => ({ ...p, w: textW(p.l, 700, 11) + 14 })), W, GP, 3), tR = nRows(pills);
  const chipW = textW('HELD', 700, 10) + 14;
  const held = lay(ln.held.map((b) => ({ ...b, w: Math.max(chipW + 5 + textW(b.v, 700, 12), textW(b.s, 400, 11)) + 8 })), W, GP, 3), gR = nRows(held);
  const bes = lay(ln.bes.map((b) => ({ ...b, w: Math.max(textW(b.v, 700, isB ? 15 : 13), textW(b.s, 400, 11), b.ch ? textW(b.ch.t, 700, 11) : 0) + 8 })), W, isB ? GB2 : GB, 3), bR = nRows(bes);
  // The bar sits under the pills (22 a row) or Held's breakevens (34 a row); the breakevens hang under it.
  const bt = tR ? tR * 22 + 8 : gR ? gR * 34 + 6 : 6, beTop = bt + thk + 8, rowH = isB ? 52 : 38;
  const H = ln.on ? beTop + bR * rowH : bt + thk + 6, lt = Math.max(0, bt + thk / 2 - 10);
  return (
    <div style={{ display: 'grid', gridTemplateColumns: cols, columnGap: 20, rowGap: 8, alignItems: 'start',
      padding: i === 2 ? '14px 0 0' : i === 0 ? '0 0 12px' : '12px 0 14px', borderTop: i === 2 ? '1px solid ' + P.rule : 'none' }}>
      <div style={{ display: 'flex', flexDirection: narrow ? 'row' : 'column', alignItems: narrow ? 'baseline' : 'flex-start', columnGap: 10, rowGap: 4, flexWrap: 'wrap', paddingTop: narrow ? 0 : lt }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 6, alignSelf: narrow ? 'center' : undefined }}>
          <span style={{ width: 10, fontSize: 15, lineHeight: '20px', fontWeight: 600, color: P.muT }}>{ln.op}</span>
          <Chip k={ln.key}>{ln.name}</Chip>
        </span>
        {ln.on && <span style={{ fontSize: isB ? 30 : 20, lineHeight: 1.15, fontWeight: 700, letterSpacing: '-.02em', color: isB ? P.G : P.ink }}>{ln.cop}</span>}
        <span style={{ fontSize: 12, lineHeight: '16px', color: P.mu, ...pretty }}>{mask(ln.sub)}</span>
        {ln.ch && <span style={{ padding: '3px 8px', borderRadius: 10, fontSize: 12, lineHeight: '16px', fontWeight: 600, background: ln.ch.bg, color: ln.ch.c }}>{ln.ch.t}</span>}
      </div>
      <div style={{ position: 'relative', height: H }}>
        <span aria-hidden="true" className="sdm" style={{ position: 'absolute', top: 0, bottom: 0, left: pct(todayX), borderLeft: '1px dashed ' + P.ring }} />
        <div aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: bt, height: thk, borderRadius: thk / 2, overflow: 'hidden', background: P.trk }}>
          {ln.zones.map((z) => <span key={z.key} className="sdm" style={{ position: 'absolute', top: 0, bottom: 0, left: pct(z.L), width: pct(z.W), background: z.c }} />)}
          {ln.diff.map((z) => <span key={z.key} className="sdm" style={{ position: 'absolute', top: 0, bottom: 0, left: pct(z.L), width: pct(z.W), background: STRIPES }} />)}
        </div>
        {pills.map((p) => <PillMark key={p.key} p={p} y={(tR - 1 - p.row) * 22} bottom={bt + thk} />)}
        {held.map((b) => {
          const y = (gR - 1 - b.row) * 34;
          return (
            <div key={b.key} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
              <span aria-hidden="true" className="sdm" style={{ position: 'absolute', top: bt - 3, left: pct(b.xv), height: thk + 6, marginLeft: -1, borderLeft: '2px dashed ' + P.muT }} />
              <div className="sdm" style={{ position: 'absolute', top: y, left: b.left, transform: 'translateX(-50%)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 1,
                padding: '0 4px', borderRadius: 4, whiteSpace: 'nowrap', background: P.bg }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                  <span style={{ height: 16, padding: '0 6px', borderRadius: 8, boxSizing: 'border-box', display: 'inline-flex', alignItems: 'center', fontSize: 10, lineHeight: '12px', fontWeight: 700,
                    letterSpacing: '.04em', textTransform: 'uppercase', background: P.bg, color: P.ink, boxShadow: 'inset 0 0 0 1.5px ' + P.muT }}>Held</span>
                  <span style={{ fontSize: 12, lineHeight: '18px', fontWeight: 700, color: P.muT }}>{b.v}</span>
                </span>
                <span style={{ fontSize: 11, lineHeight: '14px', color: P.mu }}>{b.s}</span>
              </div>
            </div>
          );
        })}
        {bes.map((b) => <BeMark key={b.key} b={b} bt={bt} thk={thk} y={beTop + b.row * rowH} big={isB} />)}
        {isB && ln.on && (
          <span aria-hidden="true" className="sdm" style={{ position: 'absolute', top: bt + thk / 2 - 7, left: pct(todayX), width: 14, height: 14, marginLeft: -7, borderRadius: 7,
            background: P.ink, boxShadow: '0 0 0 3px ' + P.bg }} />
        )}
      </div>
    </div>
  );
}

/** A strike: the pill (outlined and dashed for Held, filled and solid for New) and its stem down through the bar. */
function PillMark({ p, y, bottom }: { p: Placed<Pill & { w: number }>; y: number; bottom: number }) {
  return (
    <div aria-hidden="true" style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      <span className="sdm" style={{ position: 'absolute', top: y + 18, left: pct(p.xv), height: Math.max(0, bottom - y - 18), marginLeft: -1, borderLeft: `2px ${p.nw ? 'solid' : 'dashed'} ${p.c}` }} />
      <span className="sdm" style={{ position: 'absolute', top: y, left: p.left, transform: 'translateX(-50%)', height: 18, padding: '0 7px', borderRadius: 9, boxSizing: 'border-box',
        display: 'flex', alignItems: 'center', fontSize: 11, lineHeight: '14px', fontWeight: 700, whiteSpace: 'nowrap',
        background: p.nw ? p.c : P.bg, color: p.nw ? '#000000' : p.c, boxShadow: p.nw ? 'none' : 'inset 0 0 0 1.5px ' + p.c }}>{p.l}</span>
    </div>
  );
}

/** A breakeven under its bar: the notch, the price, `↓ 9.3% · 1.34 SD`, and in Both the change against Held. */
function BeMark({ b, bt, thk, y, big }: { b: Placed<Be & { w: number }>; bt: number; thk: number; y: number; big: boolean }) {
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      <span aria-hidden="true" className="sdm" style={{ position: 'absolute', top: bt - 4, left: pct(b.xv), height: thk + 8, marginLeft: -1, borderLeft: '2px solid ' + P.ink }} />
      <div className="sdm" style={{ position: 'absolute', top: y, left: b.left, transform: 'translateX(-50%)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 1,
        padding: '0 4px', borderRadius: 4, whiteSpace: 'nowrap', background: P.bg }}>
        <span style={{ fontSize: big ? 15 : 13, lineHeight: '18px', fontWeight: 700 }}>{b.v}</span>
        <span style={{ fontSize: 11, lineHeight: '14px', color: P.mu }}>{b.s}</span>
        {b.ch && <span style={{ fontSize: 11, lineHeight: '14px', fontWeight: 700, color: b.ch.c }}>{b.ch.t}</span>}
      </div>
    </div>
  );
}

/** The What if holds exactly this sale: the same rows, whatever their order. */
const sameSale = (a: SdTrade[], b: Trade[]) =>
  a.length === b.length && a.every((x) => b.some((u) => u.side === x.side && u.ty === x.ty && Math.abs(u.K - x.K) < 1e-9 && u.ex === x.ex && u.n === x.n));

/** Try in What if (README 1.8 and 1.10, web only): one SD sale at a time. It sends the sale; when the What if holds
    exactly this sale the button reads ✓ In What if and takes it off; any other sale replaces the last. */
function TryIt({ v, onTry, sdIn, live }: { v: SdView; onTry: (x: Rows | null) => void; sdIn?: Trade[]; live: boolean }) {
  const x = v.tryIt, sent = !!x && !!sdIn?.length && sameSale(x.trades, sdIn), off = !x || !live;
  const cap = !x ? 'Add calls or puts first.'
    : sent ? `On the ${v.name} chart now: sell ${x.what}. Tap again to take it off.`
      : `Sell ${x.what}, on the ${v.name} payoff chart with your whole book.`;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', paddingTop: 14, borderTop: '1px solid ' + P.rule }}>
      <button type="button" className="bare" aria-pressed={sent} disabled={off} onClick={() => { if (x && live) onTry(sent ? null : x.trades); }}
        style={{ flex: 'none', height: 32, padding: '0 12px 0 14px', borderRadius: 16, boxSizing: 'border-box', display: 'inline-flex', alignItems: 'center', gap: 6,
          fontSize: 13, lineHeight: '18px', fontWeight: 600, color: P.ink, boxShadow: 'inset 0 0 0 1px ' + P.ring, opacity: off ? 0.4 : 1, cursor: off ? 'default' : 'pointer' }}>
        {sent ? '✓ In What if' : 'Try in What if'}
        <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><path d="M3.5 1.5 7 5l-3.5 3.5" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round' }} /></svg>
      </button>
      <span style={{ flex: 1, minWidth: 160, fontSize: 12, lineHeight: '16px', color: P.mu, ...pretty }}>{cap}</span>
    </div>
  );
}
