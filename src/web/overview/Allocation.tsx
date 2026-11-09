// Overview · Allocation (README 3.5): both books side by side (auto-fit, min 600), each a 300 tall map of its
// five largest blocks beside a ranked list with thin bars, weighted by capital bought. A block of a name opens
// Positions on that name for that book.
//
// The views are the design's, kept honest: By stock, By strategy and P&L by position have data; By sector does
// not (the Home payload carries no sector for every name), so it is not offered.
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { BOOK_NAME } from '../components/AccountMenu';
import type { BookId } from '../lib/data';
import { C, money, pct } from '../lib/format';
import { useWeb } from '../lib/state';
import type { AlRow } from './model';
import { Seg } from './Seg';

type View = 'stock' | 'strat' | 'pl';
const KIND: Record<View, string> = { stock: 'ticker', strat: 'strategy', pl: 'position' };
/** The design's block places by count (x, y, w, h in %). */
const PZ: number[][][] = [
  [],
  [[0, 0, 100, 100]],
  [[0, 0, 50, 100], [50, 0, 50, 100]],
  [[0, 0, 42, 100], [42, 0, 58, 50], [42, 50, 58, 50]],
  [[0, 0, 42, 100], [42, 0, 58, 50], [42, 50, 29, 50], [71, 50, 29, 50]],
  [[0, 0, 42, 100], [42, 0, 29, 50], [71, 0, 29, 50], [42, 50, 29, 50], [71, 50, 29, 50]],
];
const cl = (v: number) => (v >= 0 ? C.green : C.red);

interface Item { k: string; l: string; cap: number; pl: number; n: string[]; tk?: string }

export function Allocation({ sides }: { sides: { id: BookId; rows: AlRow[] | null }[] }) {
  const all = sides.flatMap((s) => s.rows ?? []);
  const views: [View, string][] = [['stock', 'By stock']];
  if (all.length && all.every((r) => r.strat)) views.push(['strat', 'By strategy']);
  views.push(['pl', 'P&L by position']);
  const [pick, setView] = useState<View>('stock');
  const al: View = views.some(([k]) => k === pick) ? pick : 'stock';
  const sub = al === 'pl' ? 'sized by capital bought, shaded by P&L so far on shares and options · a block opens Positions'
    : 'by capital bought: shares, LEAPS, OTM calls and puts at cost' + (al === 'stock' ? ' · a block opens Positions' : '');

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 18, paddingTop: 12 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', gap: 16, flexWrap: 'wrap' }}>
        <span style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
          <span style={{ fontSize: 20, fontWeight: 600 }}>Allocation</span>
          <span style={{ fontSize: 13, color: C.ink2 }}>{sub}</span>
        </span>
        <Seg<View> label="Allocation view" items={views} value={al} onChange={setView} />
      </div>
      <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(600px,1fr))', gap: 48,
        borderTop: '1px solid rgba(255,255,255,.14)', paddingTop: 18 }}>
        {sides.map((s) => <Book key={s.id} id={s.id} rows={s.rows} al={al} />)}
      </div>
      <style>{`.sw .sw-alb:hover{filter:brightness(1.15)}`}</style>
    </div>
  );
}

function Book({ id, rows, al }: { id: BookId; rows: AlRow[] | null; al: View }) {
  const { mask, pickAccount } = useWeb();
  const nav = useNavigate();
  const list0 = rows ?? [];
  const tot = list0.reduce((a, r) => a + r.cap, 0);
  const isPL = al === 'pl', isG = al === 'strat';
  let items: Item[];
  if (isG) {
    const g = new Map<string, Item>();
    for (const r of list0) {
      const x = g.get(r.strat) ?? { k: r.strat, l: r.strat, cap: 0, pl: 0, n: [] };
      x.cap += r.cap; x.pl += r.pl; x.n.push(r.t);
      g.set(r.strat, x);
    }
    items = [...g.values()];
  } else items = list0.map((r) => ({ k: r.t, l: r.t, cap: r.cap, pl: r.pl, n: [r.t], tk: r.t }));
  items.sort((a, b) => b.cap - a.cap);
  const mxPL = Math.max(1, ...items.map((x) => Math.abs(x.pl))), mxC = items.length ? items[0].cap : 1;
  const top = items.slice(0, 5), P = PZ[top.length];
  // A block opens Positions on that name, in that book (the design's goAl: account, then Positions).
  const open = (t: string) => { pickAccount(id); nav(`/positions/${t}`, { replace: true }); };
  const list = isPL ? items.slice().sort((a, b) => b.pl - a.pl) : items;
  const lh = (isPL ? 'P&L so far · ' : al === 'stock' ? 'Top holdings · ' : 'Strategies · ') + items.length;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10 }}>
        <span style={{ fontSize: 17, fontWeight: 600 }}>{BOOK_NAME[id]}</span>
        {rows && <span style={{ fontSize: 13, color: C.ink2 }}>{mask(`${money(tot)} bought`)}</span>}
      </div>
      {rows && !items.length && <span style={{ fontSize: 15, color: C.ink2 }}>Nothing held yet.</span>}
      {items.length > 0 && (
        <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'minmax(0,440px) minmax(180px,1fr)', gap: 24, alignItems: 'start' }}>
          <div style={{ position: 'relative', width: '100%', height: 300 }}>
            {top.map((q, i) => {
              const [x, y, w, h] = P[i];
              const v1 = isPL ? (q.pl >= 0 ? 'Up ' : 'Down ') + money(q.pl) : money(q.cap);
              const v2 = isPL ? pct((Math.abs(q.pl) / q.cap) * 100) : pct((q.cap / tot) * 100);
              const bg = isPL ? `rgba(${q.pl >= 0 ? '101,196,102' : '255,105,97'},${(0.06 + (0.2 * Math.abs(q.pl)) / mxPL).toFixed(3)})`
                : i === 0 ? 'rgba(255,255,255,.10)' : 'rgba(255,255,255,.05)';
              const go = q.tk ? () => open(q.tk!) : undefined;
              return (
                <button key={q.k} type="button" className="bare sw-alb" onClick={go} aria-label={mask(`${q.l}, ${v1}, ${v2}`)}
                  style={{ position: 'absolute', left: x + '%', top: y + '%', width: w + '%', height: h + '%', padding: 3, cursor: go ? 'pointer' : 'default' }}>
                  <span style={{ boxSizing: 'border-box', width: '100%', height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
                    padding: '10px 12px 12px', borderRadius: 14, background: bg,
                    boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.10),inset 1px 1px 0 -.5px rgba(255,255,255,.18)',
                    outline: i === 0 ? '1.5px solid rgba(245,245,247,.6)' : '1px solid rgba(255,255,255,.12)', outlineOffset: -1, overflow: 'hidden', color: '#F5F5F7' }}>
                    <span style={{ alignSelf: 'flex-end', fontSize: 11, lineHeight: '14px', fontWeight: 600, color: i === 0 ? '#F5F5F7' : '#98989D' }}>#{i + 1}</span>
                    <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
                      <span style={{ fontSize: 10, lineHeight: '14px', letterSpacing: '.08em', textTransform: 'uppercase', color: C.ink2 }}>{KIND[al]}</span>
                      <span style={{ fontSize: i === 0 ? 26 : 16, lineHeight: 1.15, fontWeight: 700, letterSpacing: '-.01em', textWrap: 'balance' } as React.CSSProperties}>{q.l}</span>
                      <span style={{ display: 'flex', flexWrap: 'wrap', columnGap: 6, fontSize: 12, lineHeight: '17px',
                        color: isPL ? (q.pl >= 0 ? '#A8DCA3' : '#F2A9A5') : '#AEAEB2' }}>
                        <span>{mask(v1)}</span><span>{v2}</span>
                      </span>
                    </span>
                  </span>
                </button>
              );
            })}
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
            <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: '.05em', textTransform: 'uppercase', color: C.ink2, paddingBottom: 6 }}>{lh}</span>
            {list.map((x, i) => {
              const w = ((isPL ? Math.abs(x.pl) / mxPL : x.cap / mxC) * 100).toFixed(1) + '%';
              const bb = isPL ? cl(x.pl) : i === 0 ? '#F5F5F7' : 'rgba(255,255,255,.32)';
              const vc = isPL ? cl(x.pl) : i === 0 ? '#F5F5F7' : '#AEAEB2';
              const v = isPL ? mask(money(x.pl)) : pct((x.cap / tot) * 100);
              const fw = i === 0 ? 700 : 400;
              const bar = (
                <span style={{ display: 'block', height: 4, borderRadius: 2, background: 'rgba(255,255,255,.08)', overflow: 'hidden' }}>
                  <span style={{ display: 'block', width: w, height: '100%', borderRadius: 2, background: bb }} />
                </span>
              );
              return (
                <div key={x.k} style={{ borderTop: '1px solid rgba(255,255,255,.08)' }}>
                  {isG ? (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, padding: '8px 0' }}>
                      <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                        <span style={{ fontSize: 14, fontWeight: fw, minWidth: 0 }}>{x.l}</span>
                        <span style={{ fontSize: 14, fontWeight: 600, color: vc, whiteSpace: 'nowrap' }}>{v}</span>
                      </span>
                      {bar}
                      <span style={{ fontSize: 11, color: C.ink2 }}>{x.n.join(' · ')}</span>
                    </div>
                  ) : (
                    <div className="tnum" style={{ display: 'grid', gridTemplateColumns: '52px minmax(0,1fr) 58px', gap: 10, alignItems: 'center', padding: '9px 0' }}>
                      <span style={{ fontSize: 14, fontWeight: fw }}>{x.l}</span>
                      {bar}
                      <span style={{ fontSize: 14, fontWeight: 600, color: vc, textAlign: 'right', whiteSpace: 'nowrap' }}>{v}</span>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
