// The Positions totals table and its view switch (handoff 2026-11-08-web 2, README 2; Nik 9 Nov 2026), built to the
// design's markup: the whole book on top, the selected name under it with its share of the book, one click anywhere
// on the table cycles every number together (Time value → % change → $ change), the switch jumps straight to a view.
import { useLayoutEffect, useRef, useState } from 'react';
import { money, pct } from '../lib/format';
import { GROUPS, pctOfFig, type Cell, type GKey, type Row } from './totals';
import { G, K, MU, O, R } from './ui';

export type TView = 'tv' | 'pct' | 'usd';
export const TVIEWS: TView[] = ['tv', 'pct', 'usd'];
const WORD: Record<TView, string> = { tv: 'time value', pct: '% change', usd: '$ change' };
const SEG: Record<TView, string> = { tv: 'Time value', pct: '% change', usd: '$ change' };
export const nextView = (v: TView) => TVIEWS[(TVIEWS.indexOf(v) + 1) % 3];
const SG = 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)';

/** Time value | % change | $ change: three 88×28 segments, a glass thumb that slides with the rail switch's spring. */
export function TotalsSwitch({ view, set }: { view: TView; set: (v: TView) => void }) {
  const i = TVIEWS.indexOf(view);
  return (
    <div role="radiogroup" aria-label="Totals view" style={{ alignSelf: 'center', marginLeft: 'auto', position: 'relative', display: 'grid',
      gridTemplateColumns: 'repeat(3,88px)', padding: 2, borderRadius: 999, background: 'rgba(118,118,128,.24)' }}>
      <span aria-hidden="true" style={{ position: 'absolute', top: 2, left: 2, width: 88, height: 28, borderRadius: 999, background: 'rgba(255,255,255,.20)',
        boxShadow: SG, transform: `translateX(${i * 88}px)`, transition: 'transform .42s cubic-bezier(.34,1.36,.64,1)' }} />
      {TVIEWS.map((k) => (
        <button key={k} type="button" role="radio" aria-checked={k === view} className="bare" onClick={() => set(k)}
          onKeyDown={(e) => {
            if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
            e.preventDefault();
            set(TVIEWS[(TVIEWS.indexOf(view) + (e.key === 'ArrowRight' ? 1 : 2)) % 3]);
          }}
          style={{ position: 'relative', height: 28, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13,
            fontWeight: k === view ? 600 : 500, color: k === view ? K : MU, borderRadius: 999 }}>{SEG[k]}</button>
      ))}
    </div>
  );
}

interface Shown { v: string; c: string; s?: string }
const NBSP = ' ';

/** One cell as a view shows it: None in grey, To do in orange, else the figure in its colour. */
function show(c: Cell, key: GKey, sold: boolean, view: TView, mask: (s: string) => string): Shown {
  if (c === 'todo') return { v: 'To do', c: O };
  if (!c) return { v: 'None', c: MU };
  const x = view === 'tv' ? c.tv : view === 'usd' ? c.usd : pctOfFig(c);
  const col = view === 'tv' ? (key === 'sh' ? (x < 0 ? R : G) : sold ? G : K) : x > 0 ? G : x < 0 ? R : K;
  return { v: view === 'pct' ? pct(x) : mask(money(x)), c: col };
}

/** The name's share of the book in that column: Time value and $ change only; empty when the signs differ or it
    would pass 100% (a loss on one name inside a book that is up). */
function share(n: Cell, b: Cell, view: TView): string {
  if (view === 'pct' || !n || !b || n === 'todo' || b === 'todo') return NBSP;
  const a = view === 'tv' ? n.tv : n.usd, z = view === 'tv' ? b.tv : b.usd;
  const r = z ? a / z : 0;
  return r > 0 && r <= 1 ? `${pct(r * 100)} of book` : NBSP;
}

export function TotalsTable({ view, setView, book, name, t, mask }:
  { view: TView; setView: (v: TView) => void; book: Row; name: Row | null; t: string | null; mask: (s: string) => string }) {
  // Under 900 px of table width, Sold stacks under Long with its own row labels and no divider.
  const box = useRef<HTMLDivElement>(null);
  const [w, setW] = useState(9999);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    const f = () => setW(el.clientWidth);
    f();
    const ro = new ResizeObserver(f);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const stk = w < 900;
  const nx = nextView(view);
  const groups = [{ k: 'l', h: 'Long', a: 0, b: 4 }, { k: 's', h: 'Sold', a: 4, b: 6 }];

  return (
    <div ref={box} className="sw-tot tnum" onClick={() => setView(nx)} title={`Showing ${WORD[view]} · click for ${WORD[nx]}`}
      style={{ cursor: 'pointer', overflowX: 'auto', scrollbarWidth: 'none', padding: '18px 0', borderTop: '1px solid rgba(255,255,255,.14)',
        borderBottom: '1px solid rgba(255,255,255,.08)' }}>
      <div style={{ display: 'flex', flexDirection: stk ? 'column' : 'row', gap: stk ? 22 : 0, width: 'max-content' }}>
        {groups.map((g, gi) => {
          const showL = gi === 0 || stk;
          const cols = GROUPS.slice(g.a, g.b);
          const pr = (i: number) => (g.a + i === 3 || g.a + i === 5 ? 0 : 28);
          return (
            <div key={g.k} style={{ display: 'grid', gridTemplateColumns: (showL ? 'max-content ' : '') + `repeat(${g.b - g.a},max-content)`, alignItems: 'baseline',
              padding: `0 ${gi === 0 && !stk ? 40 : 0}px 0 ${gi && !stk ? 40 : 0}px`, borderLeft: gi && !stk ? '1px solid rgba(255,255,255,.08)' : 'none' }}>
              {showL && <span />}
              <span style={{ gridColumn: showL ? '2 / -1' : '1 / -1', paddingBottom: 10, fontSize: 12, fontWeight: 600, letterSpacing: '.05em', textTransform: 'uppercase', color: MU }}>{g.h}</span>
              {showL && <span />}
              {cols.map((c, i) => (
                <span key={'l' + c.key} style={{ padding: `0 ${pr(i)}px 6px 0`, fontSize: 12, color: MU, whiteSpace: 'nowrap' }}>
                  {c.l} · {view === 'tv' ? c.tvWord : WORD[view]}
                </span>
              ))}
              {showL && <span style={{ paddingRight: 32, fontSize: 13, color: MU, whiteSpace: 'nowrap' }}>Whole book</span>}
              {cols.map((c, i) => {
                const x = show(book[c.key], c.key, c.sold, view, mask);
                return <span key={'b' + c.key} style={{ padding: `0 ${pr(i)}px 0 0`, fontSize: 22, lineHeight: '28px', fontWeight: 600, whiteSpace: 'nowrap', color: x.c }}>{x.v}</span>;
              })}
              <span aria-hidden="true" style={{ gridColumn: '1 / -1', height: 1, margin: '12px 0', background: 'rgba(255,255,255,.08)' }} />
              {showL && <span style={{ paddingRight: 32, fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap' }}>{t ?? ''}</span>}
              {cols.map((c, i) => {
                const cell = name ? name[c.key] : null;
                const x = show(cell, c.key, c.sold, view, mask);
                return (
                  <span key={'n' + c.key} style={{ display: 'flex', flexDirection: 'column', gap: 2, padding: `0 ${pr(i)}px 0 0`, whiteSpace: 'nowrap' }}>
                    <span style={{ fontSize: 19, lineHeight: '24px', fontWeight: 600, color: x.c }}>{x.v}</span>
                    <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{share(cell, book[c.key], view)}</span>
                  </span>
                );
              })}
            </div>
          );
        })}
      </div>
      <style>{`.sw .sw-tot:hover{background:rgba(255,255,255,.025)}.sw .sw-tot::-webkit-scrollbar{display:none}`}</style>
    </div>
  );
}
