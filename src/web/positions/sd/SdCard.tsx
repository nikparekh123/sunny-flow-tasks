// The SD calculator card on Positions (handoff 2026-11-11-sd-calculator, README 1.1 "Web" and 1.3; Explorations 137b).
// Markup copied from SunnySD.dc.html with `web` true: always dark, under the chart, full width of the left column.
// Top to bottom: the title and the IV line, the expiry control, the signals, the trade (strike rows, chance of profit
// and the timeline), Every SD.
import { useLayoutEffect, useRef, useState, type CSSProperties } from 'react';
import { money } from '../../lib/format';
import type { LadRow, SdView, SdZone } from './model';

const INK = '#F5F5F7', MU = '#98989D', MUT = '#AEAEB2';
const kick: CSSProperties = { fontSize: 11, lineHeight: '14px', fontWeight: 600, letterSpacing: '.05em', textTransform: 'uppercase', color: MUT };
const GLASS = 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)';
const GRID = '76px repeat(5,minmax(0,1fr))';

export function SdCard({ v, t, busy, failed, mask }: { v: SdView | null; t: string; busy: boolean; failed: boolean; mask: (s: string) => string }) {
  return (
    <div className="tnum" style={{ fontFamily: "'Inter',system-ui,-apple-system,sans-serif", color: INK }}>
      <section aria-label="SD calculator" aria-busy={busy}
        style={{ display: 'flex', flexDirection: 'column', gap: 20, paddingTop: 18, borderTop: '1px solid rgba(255,255,255,.14)', opacity: busy && v ? 0.55 : 1, transition: 'opacity .2s' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 20, lineHeight: '24px', fontWeight: 600 }}>SD calculator</span>
          {v && <span style={{ fontSize: 13, lineHeight: '18px', color: MU }}>IV {v.ivT} · 1 SD {v.sdP} · {v.sdD}</span>}
        </div>
        {!v ? (
          failed ? <span style={{ fontSize: 13, color: MU }}>Could not load {t}.</span> : <div style={{ minHeight: 640 }} />
        ) : <Body v={v} mask={mask} />}
      </section>
    </div>
  );
}

function Body({ v, mask }: { v: SdView; mask: (s: string) => string }) {
  return (
    <>
      {/* The expiry: a glass segmented control, 50 tall, the selected segment a glass thumb. */}
      <div role="radiogroup" aria-label="Expiry"
        style={{ display: 'grid', gridTemplateColumns: `repeat(${v.exps.length},minmax(0,1fr))`, padding: 2, borderRadius: 16, background: 'rgba(118,118,128,.24)' }}>
        {v.exps.map((e) => (
          <button key={e.key} type="button" role="radio" aria-checked={e.on} onClick={e.go} className="bare"
            style={{ boxSizing: 'content-box', height: 50, borderRadius: 14, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 1,
              color: e.on ? '#F5F5F7' : '#98989D', background: e.on ? 'rgba(255,255,255,.20)' : 'transparent', boxShadow: e.on ? GLASS : 'none' }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 14, lineHeight: '18px', fontWeight: e.on ? 600 : 500 }}>
              {e.t}
              {e.isE && <span title="Earnings before this expiry" style={{ width: 5, height: 5, borderRadius: 3, background: '#F2A93B' }} />}
            </span>
            <span style={{ fontSize: 11, lineHeight: '14px', fontWeight: 500, color: MU }}>{e.d}</span>
          </button>
        ))}
      </div>

      {/* The signals: the why, outlined so they never read as a strike tile; they scroll sideways. */}
      <div role="list" aria-label="Signals" className="noscroll" style={{ display: 'flex', gap: 10, overflowX: 'auto' }}>
        {v.sig.map((g) => (
          <div key={g.key} role="listitem"
            style={{ flex: 'none', width: 180, minHeight: 116, boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: 4, padding: '14px 16px 12px',
              borderRadius: 16, background: 'transparent', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.2)' }}>
            <span style={kick}>{g.k}</span>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, flexWrap: 'wrap' }}>
              <span style={{ fontSize: 22, lineHeight: '28px', fontWeight: 700, color: g.vc }}>{g.v}</span>
              <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: g.tagc }}>{g.tag}</span>
            </div>
            {g.s && <span style={{ fontSize: 12, lineHeight: '16px', color: MUT }}>{g.s}</span>}
            <div style={{ marginTop: 'auto', display: 'flex', flexDirection: 'column', gap: 1, paddingTop: 4 }}>
              {g.fx.map((x) => <span key={x.key} style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: x.c }}>→ {x.t}</span>)}
            </div>
          </div>
        ))}
      </div>

      {/* The trade: the strike rows (the suggestion preselected), chance of profit, the timeline. */}
      <section aria-label="The trade"
        style={{ display: 'flex', flexDirection: 'column', gap: 18, padding: '20px 22px 18px', borderRadius: 22, background: 'rgba(255,255,255,.045)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.08)' }}>
        {v.rng.map((rg) => (
          <div key={rg.key} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <span style={{ ...kick, display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ width: 8, height: 8, borderRadius: 4, background: rg.c }} />
              {rg.h}
              <span style={{ textTransform: 'none', letterSpacing: 0, fontWeight: 500, color: MU }}>{rg.rT}</span>
            </span>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {rg.o.map((o) => {
                const mc = o.on ? 'rgba(0,0,0,.6)' : MUT;
                return (
                  <button key={o.key} type="button" aria-pressed={o.on} onClick={o.go} className="bare"
                    style={{ flex: 'none', width: 98, boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: 1, padding: '10px 12px', borderRadius: 14,
                      background: o.on ? INK : 'rgba(118,118,128,.18)', color: o.on ? '#1C1C1E' : INK, fontVariantNumeric: 'tabular-nums', transition: 'background .2s,color .2s' }}>
                    <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 4, fontSize: 11, lineHeight: '14px', fontWeight: 600, color: mc }}>
                      {o.sd}
                      {o.sug && <span aria-label="suggested" style={{ width: 7, height: 7, borderRadius: 4, background: rg.c }} />}
                    </span>
                    <span style={{ fontSize: 22, lineHeight: '28px', fontWeight: 700 }}>{o.strike}</span>
                    <span style={{ fontSize: 12, lineHeight: '16px', color: mc }}>{o.pr}</span>
                    {/* "≈ 81.1% won" (A1) is a hair wider than the tile's 74 px: it runs into the padding, never wraps. */}
                    <span style={{ fontSize: 12, lineHeight: '16px', color: mc, minHeight: 16, whiteSpace: 'nowrap' }}>{o.won}</span>
                  </button>
                );
              })}
            </div>
          </div>
        ))}
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, flexWrap: 'wrap', paddingTop: 14, borderTop: '1px solid rgba(255,255,255,.08)' }}>
          <span style={kick}>Chance of profit</span>
          <span style={{ fontSize: 32, lineHeight: '38px', fontWeight: 700, letterSpacing: '-.02em', color: '#65C466' }}>{v.both.cop}</span>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 6, fontSize: 14, lineHeight: '20px', color: MUT }}>
            {/* Each part its own flex item, 6 apart, as the design renders it. */}
            <span>Total</span>
            <span style={{ fontSize: 20, lineHeight: '24px', fontWeight: 700, color: INK }}>{mask(money(v.both.tot))}</span>
            <span>for</span><span>{v.both.totN}</span><span>·</span><span>{v.both.prT}</span><span>a share</span>
          </span>
        </div>
        <Timeline z={v.pz} />
        {v.held && (
          <>
            {/* What you hold (Nik 11 Nov): your sold calls and puts of this expiry as a pair, at what you sold them for. */}
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, flexWrap: 'wrap', paddingTop: 14, borderTop: '1px solid rgba(255,255,255,.08)' }}>
              <span style={kick}>What you hold · {v.held.label}</span>
              <span style={{ fontSize: 32, lineHeight: '38px', fontWeight: 700, letterSpacing: '-.02em', color: '#65C466' }}>{v.held.cop}</span>
              <span style={{ display: 'flex', alignItems: 'baseline', gap: 6, flexWrap: 'wrap', fontSize: 14, lineHeight: '20px', color: MUT }}>
                <span>Taken in</span>
                <span style={{ fontSize: 20, lineHeight: '24px', fontWeight: 700, color: INK }}>{mask(money(v.held.tot))}</span>
                <span>for</span><span>{v.held.legsT}</span>
              </span>
            </div>
            <Timeline z={v.held.pz} />
          </>
        )}
      </section>

      <section aria-label="Every SD" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 600 }}>Every SD</span>
        <div role="table" aria-label="Strikes by SD" style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
          <div role="row" style={{ display: 'grid', gridTemplateColumns: GRID, gap: 8, padding: '0 14px 6px', fontSize: 12, lineHeight: '16px', fontWeight: 600, color: MU, textAlign: 'right' }}>
            <span role="columnheader" style={{ textAlign: 'left' }}>SD</span>
            <span role="columnheader">Strike</span>
            <span role="columnheader">Away</span>
            <span role="columnheader">Premium</span>
            <span role="columnheader">Breakeven</span>
            <span role="columnheader">In the money</span>
          </div>
          <span style={{ padding: '4px 14px', fontSize: 11, lineHeight: '14px', fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase', color: '#6FA0F6' }}>Calls</span>
          {v.ladC.map((r) => <Lad key={r.key} r={r} kc="#6FA0F6" />)}
          <div role="row" style={{ display: 'grid', gridTemplateColumns: '76px minmax(0,1fr)', gap: 8, alignItems: 'center', padding: '8px 14px' }}>
            <span role="rowheader" style={{ fontSize: 11, lineHeight: '14px', fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>Today</span>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <span style={{ flex: 1, height: 1, background: 'rgba(255,255,255,.28)' }} />
              <span style={{ fontSize: 14, lineHeight: '18px', fontWeight: 700 }}>{v.pxT}</span>
              <span style={{ flex: 1, height: 1, background: 'rgba(255,255,255,.28)' }} />
            </div>
          </div>
          <span style={{ padding: '4px 14px', fontSize: 11, lineHeight: '14px', fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase', color: '#D49A5A' }}>Puts</span>
          {v.ladP.map((r) => <Lad key={r.key} r={r} kc="#D49A5A" />)}
        </div>
        <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>Boxed: the range the rules allow · ≈ estimated · ! thin market</span>
      </section>
    </>
  );
}

function Lad({ r, kc }: { r: LadRow; kc: string }) {
  return (
    <div role="row"
      style={{ display: 'grid', gridTemplateColumns: GRID, gap: 8, alignItems: 'center', minHeight: 38, padding: '0 14px', borderRadius: r.rad, background: r.bg, boxShadow: r.ring,
        fontSize: 14, lineHeight: '18px', fontWeight: r.fw, textAlign: 'right' }}>
      <span role="rowheader" style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: MUT }}>
        {r.sdL}
        {r.sug && <span style={{ width: 6, height: 6, borderRadius: 3, background: r.dc }} />}
      </span>
      <span role="cell" style={{ color: kc }}>{r.K}</span>
      <span role="cell" style={{ color: MUT }}>{r.pct}</span>
      <span role="cell">{r.prT}</span>
      <span role="cell">{r.be}</span>
      <span role="cell">{r.itm}</span>
    </div>
  );
}

/** The profit zone (web 100 tall): the strikes on top, the distance lines, the bar, today, the breakevens under it
    as `36.54 (BE)` over `4.3% (1.2 SD)`. */
function Timeline({ z }: { z: SdZone }) {
  // The labels under the bar, each centred under its point, then pushed apart so none touch (10 apart).
  const box = useRef<HTMLDivElement>(null);
  const [bw, setBw] = useState(0);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setBw(el.clientWidth));
    ro.observe(el); setBw(el.clientWidth);
    return () => ro.disconnect();
  }, []);
  const at = bw ? spread(z.bot.map((x) => ({ c: parseFloat(x.x) / 100 * bw, w: Math.max(textW(x.l, 600, 12), textW(x.s, 400, 11)) })), bw) : null;
  return (
    <div ref={box} aria-label="Profit zone" style={{ position: 'relative', height: 100 }}>
      <span aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: 50, height: 8, borderRadius: 4, background: 'rgba(255,255,255,.08)' }} />
      <span aria-hidden="true" style={{ position: 'absolute', top: 50, height: 8, left: z.zL, width: z.zW, borderRadius: 4, background: 'rgba(101,196,102,.28)' }} />
      <span aria-hidden="true" style={{ position: 'absolute', top: 50, height: 8, left: z.mL, width: z.mW, background: 'rgba(101,196,102,.6)' }} />
      {z.dist.map((d) => (
        <div key={d.key} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
          <span style={{ position: 'absolute', top: 40, left: d.L, width: d.W, height: 2, borderRadius: 1, background: d.c, opacity: 0.6 }} />
          <span style={{ position: 'absolute', top: 20, left: d.x, transform: 'translateX(-50%)', fontSize: 12, lineHeight: '16px', fontWeight: 700, color: d.c, whiteSpace: 'nowrap' }}>{d.l}</span>
        </div>
      ))}
      {z.top.map((x) => (
        <div key={x.key} style={{ position: 'absolute', top: 0, left: x.x, transform: 'translateX(-50%)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 }}>
          <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 700, color: x.c, whiteSpace: 'nowrap' }}>{x.l}</span>
          <span style={{ width: 2, height: 34, borderRadius: 1, background: x.c }} />
        </div>
      ))}
      <span aria-hidden="true" style={{ position: 'absolute', top: 48, left: z.today, width: 12, height: 12, marginLeft: -6, borderRadius: 6, background: '#F5F5F7', boxShadow: '0 0 0 3px #0B0B0C' }} />
      {z.bot.map((x, i) => (
        <div key={x.key} style={{ position: 'absolute', top: 66, left: at ? at[i] : x.x, transform: 'translateX(-50%)', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, whiteSpace: 'nowrap' }}>{x.l}</span>
          <span style={{ fontSize: 11, lineHeight: '14px', color: MU, whiteSpace: 'nowrap' }}>{x.s}</span>
        </div>
      ))}
    </div>
  );
}

/** Centres pushed apart left to right, then back from the right edge, so no two labels touch; kept on the card. */
function spread(items: { c: number; w: number }[], W: number): number[] {
  const order = items.map((_, i) => i).sort((a, b) => items[a].c - items[b].c);
  const c = order.map((i) => items[i].c), w = order.map((i) => items[i].w);
  for (let i = 0; i < c.length; i++) c[i] = Math.max(c[i], i ? c[i - 1] + w[i - 1] / 2 + 10 + w[i] / 2 : w[i] / 2);
  for (let i = c.length - 1; i >= 0; i--) c[i] = Math.min(c[i], i < c.length - 1 ? c[i + 1] - w[i + 1] / 2 - 10 - w[i] / 2 : W - w[i] / 2);
  const out: number[] = [];
  order.forEach((i, j) => { out[i] = c[j]; });
  return out;
}
let measure: CanvasRenderingContext2D | null = null;
const textW = (s: string, wt: number, px: number) => {
  if (!measure && typeof document !== 'undefined') measure = document.createElement('canvas').getContext('2d');
  if (!measure) return s.length * px * 0.6;
  measure.font = `${wt} ${px}px Inter, system-ui, sans-serif`;
  return measure.measureText(s).width;
};
