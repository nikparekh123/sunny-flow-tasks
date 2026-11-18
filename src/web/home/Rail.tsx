// The Positions rail on Home as pills (handoff 2026-11-18: SunnyRail 167a, layout="pills"; CHANGES Nov 17 "The rail's
// row style" and "The rail as pills"; replaces By ticker | By leg, 148a). The header and See all; a glass What you
// hold | By name switch; "Showing" and a glass capsule naming what the pills show, which opens Display data (Today's
// return, Total return, Total percent change, Left to capture, Last price); then one glass card a section (Calls
// sold, Puts sold, Shares, Hedges, or one a name), one row a strike or name with a coloured pill: green made, red
// lost, grey neither. A tap on a name opens it on Positions; a tap on a pill opens Display data. The design's small
// line per row is left out: there is no intraday series per leg to draw it from. Follows the account on screen and
// privacy. Builder A places it: sticky on the right at 340, or under the main column when `narrow`.
import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePrefetchFromHome, type BookId, type J } from '../lib/data';
import { C, pct, price } from '../lib/format';
import { useWeb } from '../lib/state';
import { inSessionOrder, railNames } from './rail/model';
import { byHold, byName, pillLegs, pillOf, showLabel, SHOWS, totalOf, type Pill, type Show } from './rail/pills';

const MU = C.ink2, G = C.green, R = C.red, INK = C.ink;
const TONE: Record<Pill['tone'], string> = { g: G, r: R, n: MU };
const PILL: Record<Pill['tone'], [string, string]> = { g: [G, '#000000'], r: [R, '#000000'], n: ['rgba(118,118,128,.32)', INK] };
const CARD: CSSProperties = {
  boxSizing: 'border-box', display: 'flex', flexDirection: 'column', padding: '14px 16px 4px', borderRadius: 20,
  background: 'linear-gradient(160deg,rgba(255,255,255,.07) 0%,rgba(255,255,255,.025) 55%,rgba(255,255,255,.05) 100%)',
  boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.08),inset 1px 1px 0 -.5px rgba(255,255,255,.16)',
};
const CAPSULE: CSSProperties = {
  display: 'flex', alignItems: 'center', gap: 6, height: 32, padding: '0 12px', borderRadius: 999,
  background: 'linear-gradient(160deg,rgba(255,255,255,.20) 0%,rgba(255,255,255,.09) 50%,rgba(255,255,255,.15) 100%)',
  boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.32),inset 1px 1px 0 -.5px rgba(255,255,255,.45),0 2px 8px rgba(0,0,0,.35)',
  fontSize: 13, lineHeight: '18px', fontWeight: 600, color: INK, whiteSpace: 'nowrap',
};
const CSS = `.sw .sw-rp-n:hover{opacity:.8}.sw .sw-rp-p{transition:background .25s ease}.sw .sw-rp-p:active{transform:scale(.96)}
.sw .sw-rp-o:hover{background:rgba(255,255,255,.06)}.sw .sw-rail-see:hover{color:${INK}!important}`;
const NOTE = 'For what you sold, Total return is what you have captured, Total percent change the share captured, Left to capture the time value still to come. Green made, red lost, grey neither. A tap on a name opens it on Positions.';

const readShow = (): Show => { try { const v = localStorage.getItem('sw-rail-show'); return SHOWS.some((s) => s[0] === v) ? (v as Show) : 'td'; } catch { return 'td'; } };
const writeShow = (v: Show) => { try { localStorage.setItem('sw-rail-show', v); } catch { /* private window */ } };

export default function Rail({ payload, book, narrow }: { payload: J; book: BookId; narrow: boolean }) {
  const { mask, railView, setRailView } = useWeb();
  const nav = useNavigate();
  // The session order Home has drawn the names in (they never re-sort as prices move).
  const names = useMemo(() => inSessionOrder(book, railNames(payload)), [payload, book]);
  const legs = useMemo(() => pillLegs(payload), [payload]);
  const byNm = railView === 'name';
  const secs = useMemo(() => (byNm ? byName(book, legs, names.map((n) => ({ t: n.t, px: n.px, mv: n.mv }))) : byHold(book, legs)), [byNm, book, legs, names]);
  // Once Home is up, read ahead what a click here opens: each name on Positions, in the rail's order.
  const ahead = useMemo(() => {
    const held = new Set(legs.map((x) => x.t));
    return [...names.map((n) => n.t), ...held].filter((t, i, a) => held.has(t) && a.indexOf(t) === i);
  }, [names, legs]);
  usePrefetchFromHome(book, ahead, ahead.length > 0);

  const [show, setShowS] = useState<Show>(readShow);
  const setShow = (v: Show) => { setShowS(v); writeShow(v); };
  const [menu, setMenu] = useState(false);
  const capRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const cur = showLabel(show);
  const openMenu = (fromPill: boolean) => {
    setMenu((m) => !m);
    // A pill far down the rail: bring the capsule (and its menu) into view.
    if (fromPill) capRef.current?.scrollIntoView({ block: 'nearest', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
  };
  useEffect(() => {
    if (!menu) return;
    (menuRef.current?.querySelector('[aria-checked="true"]') as HTMLElement | null)?.focus({ preventScroll: true });
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); setMenu(false); capRef.current?.focus(); } };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [menu]);

  const open = (t: string) => nav('/positions/' + encodeURIComponent(t));

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
      <style>{CSS}</style>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, paddingBottom: 6 }}>
        <span style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-.01em' }}>Positions</span>
        <button type="button" className="bare sw-rail-see" onClick={() => nav('/positions')} style={{ fontSize: 13, color: MU }}>See all ›</button>
      </div>
      {legs.length === 0 ? (
        // A book with nothing held (the cousin's, until he trades): the phone's one line (PositionsScreen).
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, paddingTop: 8 }}>
          <span style={{ fontSize: 15, fontWeight: 600 }}>Nothing held yet</span>
          <span style={{ fontSize: 13, color: MU }}>Each name you hold shows here once IBKR reports it.</span>
        </div>
      ) : (
        <div className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingTop: 8 }}>
          <Seg value={byNm ? 'name' : 'hold'} set={setRailView} />
          <div style={{ position: 'relative', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, padding: '0 2px 4px' }}>
            <span style={{ fontSize: 13, lineHeight: '18px', color: MU }}>Showing</span>
            <button ref={capRef} type="button" className="bare" onClick={() => openMenu(false)} aria-haspopup="menu" aria-expanded={menu}
              aria-label={`Display data: ${cur}`} style={CAPSULE}>
              {cur}
              <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><path d="M3.5 6l4.5 4.5L12.5 6" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' }} /></svg>
            </button>
            {menu && <>
              <button type="button" aria-label="Close" tabIndex={-1} className="bare" onClick={() => setMenu(false)} style={{ position: 'fixed', inset: 0, zIndex: 40, cursor: 'default' }} />
              <div ref={menuRef} role="menu" aria-label="Display data" className="g2"
                style={{ position: 'absolute', right: 0, top: 40, zIndex: 41, width: 250, padding: '6px 0', borderRadius: 16 }}>
                <span style={{ display: 'block', padding: '8px 16px 6px', fontSize: 13, lineHeight: '18px', fontWeight: 600, color: MU }}>Display data</span>
                {SHOWS.map(([k, l]) => (
                  <button key={k} type="button" role="menuitemradio" aria-checked={k === show} className="bare sw-rp-o"
                    onClick={() => { setShow(k); setMenu(false); capRef.current?.focus({ preventScroll: true }); }}
                    style={{ width: '100%', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, minHeight: 44, padding: '0 16px',
                      borderTop: '1px solid rgba(255,255,255,.08)', fontSize: 15, lineHeight: '20px', fontWeight: k === show ? 600 : 400, color: INK }}>
                    {l}
                    <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true" style={{ opacity: k === show ? 1 : 0 }}>
                      <path d="M3 8.5l3.2 3.2L13 4.8" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round' }} />
                    </svg>
                  </button>
                ))}
              </div>
            </>}
          </div>
          {secs.map((s) => {
            const tot = totalOf(s.rows, show), hasPx = s.px != null && Number.isFinite(s.px);
            return (
              <section key={s.k} aria-label={s.h} style={CARD}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10, paddingBottom: 8 }}>
                  <span style={{ display: 'flex', alignItems: 'baseline', gap: 8, minWidth: 0 }}>
                    <span style={{ fontSize: 19, lineHeight: '24px', fontWeight: 700 }}>{s.h}</span>
                    {hasPx && (
                      <span style={{ fontSize: 13, lineHeight: '18px', color: MU, whiteSpace: 'nowrap' }}>
                        {price(s.px)} <span style={{ fontWeight: 600, color: TONE[(s.mv ?? 0) > 0 ? 'g' : (s.mv ?? 0) < 0 ? 'r' : 'n'] }}>{pct(s.mv)}</span>
                      </span>
                    )}
                  </span>
                  {tot.v && <span style={{ fontSize: 14, lineHeight: '18px', fontWeight: 600, color: TONE[tot.tone], whiteSpace: 'nowrap' }}>{mask(tot.v)}</span>}
                </div>
                {s.rows.map((x) => {
                  const pl = pillOf(x, show), [pb, pf] = PILL[pl.tone];
                  const dir = pl.tone === 'g' ? 'up ' : pl.tone === 'r' ? 'down ' : '';
                  return (
                    <div key={x.key} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: 10, alignItems: 'center', minHeight: 58, padding: '8px 0', borderTop: '1px solid rgba(255,255,255,.08)' }}>
                      <button type="button" className="bare sw-rp-n" onClick={() => open(x.t)} aria-label={`${x.l}, ${mask(x.q)}${x.ev ? ', ' + x.ev : ''}. Opens ${x.t} on Positions`}
                        style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0, textAlign: 'left' }}>
                        <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, color: INK, textWrap: 'pretty' } as CSSProperties}>{x.l}</span>
                        <span style={{ fontSize: 12, lineHeight: '16px', color: MU, textWrap: 'pretty' } as CSSProperties}>
                          {x.q}{x.ev && <span style={{ fontWeight: 600, color: C.orange }}> · {x.ev}</span>}
                        </span>
                      </button>
                      <button type="button" className="bare sw-rp-p" onClick={() => openMenu(true)} aria-label={`${cur} ${pl.v === '-' ? 'does not apply' : dir + (pl.money ? mask(pl.v) : pl.v)}. Change what the pills show`}
                        style={{ minWidth: 76, height: 32, padding: '0 10px', borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center',
                          background: pb, color: pf, fontSize: 14, lineHeight: '18px', fontWeight: 600, whiteSpace: 'nowrap' }}>
                        {pl.money ? mask(pl.v) : pl.v}
                      </button>
                    </div>
                  );
                })}
              </section>
            );
          })}
          <span style={{ padding: '0 2px', fontSize: 12, lineHeight: '17px', color: MU, textWrap: 'pretty' } as CSSProperties}>{NOTE}</span>
        </div>
      )}
      {narrow && <span aria-hidden="true" />}
    </div>
  );
}

/** The glass What you hold | By name control: a capsule track, a glass thumb that springs across (.42 s), 32 tall,
    14 px, the picked one 600. */
function Seg({ value, set }: { value: 'hold' | 'name'; set: (v: 'hold' | 'name') => void }) {
  const items: ['hold' | 'name', string][] = [['hold', 'What you hold'], ['name', 'By name']];
  return (
    <div role="radiogroup" aria-label="Group by"
      style={{ position: 'relative', display: 'grid', gridTemplateColumns: 'repeat(2,minmax(0,1fr))', padding: 2, borderRadius: 999, background: 'rgba(118,118,128,.24)' }}>
      <span aria-hidden="true" style={{ position: 'absolute', top: 2, left: 2, width: 'calc(50% - 2px)', height: 32, borderRadius: 999, background: 'rgba(255,255,255,.20)',
        boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)',
        transform: value === 'name' ? 'translateX(100%)' : 'translateX(0)', transition: 'transform .42s cubic-bezier(.34,1.36,.64,1)' }} />
      {items.map(([k, l]) => (
        <button key={k} type="button" role="radio" aria-checked={value === k} className="bare" onClick={() => set(k)}
          style={{ position: 'relative', cursor: 'pointer', height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, fontWeight: value === k ? 600 : 500, color: INK }}>
          {l}
        </button>
      ))}
    </div>
  );
}
