// The tables on Positions (README 2): Compare under the chart, then under both columns P&L by price and date, Every
// leg, and the two lists, Whole book and Walls by expiry. Each is drawn as the design draws it; every number is the
// book's, summed from the server's grid (and the engine for What if trades).
import { count, money, price } from '../lib/format';
import { fk, type ChainW, type DPt, type PLeg, type Pricer, type Seg } from './model';
import { HAIR, HAIR_S, K, MU, O, R, Seg as SegCtl, Switch, cl, kicker } from './ui';
import { LegSdLines } from './sd/LegLines';
import type { LegLines } from './sd/legs';

const tn = { fontVariantNumeric: 'tabular-nums' } as const;
const side = (d: number) => (d < 0 ? 'Short ' : 'Long ') + count(d);

/* ── Compare (130 · 5 × 1fr · 110 · 100 · 90) ───────────────────────────────── */
export interface CmpRow { l: string; cells: number[]; d: number; sh: number | null; th: number }
export function Compare({ dL, rows, top, mask }: { dL: string; rows: CmpRow[]; top: number; mask: (s: string) => string }) {
  const cols = '130px repeat(5,minmax(0,1fr)) 110px 100px 90px';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', paddingTop: 8 }}>
      <div style={{ ...tn, display: 'grid', gridTemplateColumns: cols, gap: 10, paddingBottom: 8, ...kicker }}>
        <span>By {dL}</span><span>↓10%</span><span>↓5%</span><span>Flat</span><span>↑5%</span><span>↑10%</span><span>Delta</span><span>Best at</span><span>Theta today</span>
      </div>
      {rows.map((r) => (
        <div key={r.l} style={{ ...tn, display: 'grid', gridTemplateColumns: cols, gap: 10, alignItems: 'baseline', padding: '10px 0', borderTop: HAIR }}>
          <span style={{ fontSize: 14, fontWeight: 600 }}>{r.l}</span>
          {r.cells.map((v, i) => <span key={i} style={{ fontSize: 14, fontWeight: 600, color: cl(v) }}>{mask(money(v))}</span>)}
          <span style={{ fontSize: 14, color: r.d < 0 ? R : K }}>{side(r.d)}</span>
          <span style={{ fontSize: 14 }}>{r.sh != null ? price(r.sh) : `past ↑${top}%`}</span>
          <span style={{ fontSize: 14, color: cl(r.th) }}>{mask(money(r.th))}</span>
        </div>
      ))}
    </div>
  );
}

/* ── P&L by price and date (150 · 7 columns) ──────────────────────────────── */
const SP = [10, 7.5, 5, 2.5, 0, -2.5, -5, -7.5, -10];
export function PriceDateGrid({ t, pr, set, cols, picked, onPick, chg, mask }:
  { t: string; pr: Pricer; set: PLeg[]; cols: Seg[]; picked: number; onPick: (s: Seg) => void; chg: boolean; mask: (s: string) => string }) {
  const S0 = pr.m.S0;
  const grid = SP.map((p) => cols.map((c) => pr.pl(set, S0 * (1 + p / 100), { tt: c.tt, row: c.row })));
  const gmx = Math.max(1, ...grid.map((r) => Math.max(...r.map(Math.abs))));
  const gc = `150px repeat(${cols.length},minmax(0,1fr))`;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', paddingTop: 28 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12, paddingBottom: 10 }}>
        <span style={{ fontSize: 17, fontWeight: 600 }}>P&amp;L by price and date</span>
        <span style={{ fontSize: 13, color: MU }}>{chg ? 'with your changes' : 'your book'} · from today · a date picks the chart</span>
      </div>
      <div style={{ ...tn, display: 'grid', gridTemplateColumns: gc, gap: 2, borderTop: HAIR_S }}>
        <span style={{ ...kicker, padding: '10px 0 8px' }}>If {t} is at</span>
        {cols.map((c) => {
          const on = c.i === picked;
          return (
            <button key={c.i} type="button" className="bare" onClick={() => onPick(c)} aria-pressed={on}
              style={{ textAlign: 'center', padding: '10px 0 8px', fontSize: 13, fontWeight: on ? 700 : 400, boxShadow: `inset 0 -2px 0 ${on ? K : 'transparent'}` }}>{c.label}</button>
          );
        })}
      </div>
      {SP.map((p, ri) => (
        <div key={p} style={{ ...tn, display: 'grid', gridTemplateColumns: gc, gap: 2, paddingTop: 2 }}>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 6, padding: '7px 0' }}>
            <span style={{ fontSize: 14, fontWeight: p === 0 ? 700 : 400 }}>{price(S0 * (1 + p / 100))}</span>
            <span style={{ fontSize: 12, color: MU }}>{p === 0 ? 'flat' : (p > 0 ? '↑' : '↓') + Math.abs(p) + '%'}</span>
          </span>
          {grid[ri].map((v, j) => {
            const a = Math.abs(v) / gmx, z = Math.abs(v) < 0.5, on = cols[j].i === picked;
            return (
              <button key={j} type="button" className="bare swp-cell" onClick={() => onPick(cols[j])}
                style={{ textAlign: 'center', padding: '7px 0', borderRadius: 5, fontSize: 13, fontWeight: on ? 700 : 600,
                  color: z ? MU : v > 0 ? '#A8DCA3' : '#F2A9A5',
                  background: z ? 'transparent' : (v > 0 ? 'rgba(101,196,102,' : 'rgba(255,105,97,') + (0.05 + 0.22 * a).toFixed(3) + ')',
                  boxShadow: on ? 'inset 0 0 0 100px rgba(255,255,255,.08)' : 'none' }}>{z ? mask('$0') : mask(money(v))}</button>
            );
          })}
        </div>
      ))}
    </div>
  );
}

/* ── Every leg (52 · 1fr · 140 · 96 · 64 · 64 · 80 · 80 · 76 · 160) ───────── */
/** `sd`: SD on your positions (139a; Nik D1, 11 Nov 2026: a new column at the right end with the three lines). */
export interface LegRow { l: PLeg; on: boolean; toggle: () => void; added: boolean; sf: number | null; d: number; th: number; sd?: LegLines | null }
export function EveryLeg({ rows, total, filter, setFilter, mask }:
  { rows: LegRow[]; total: { sf: number; d: number; th: number }; filter: 'all' | 'sold' | 'long'; setFilter: (f: 'all' | 'sold' | 'long') => void; mask: (s: string) => string }) {
  const cols = '52px minmax(0,1fr) 140px 96px 64px 64px 80px 80px 76px 160px';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', paddingTop: 28 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingBottom: 10 }}>
        <span style={{ fontSize: 17, fontWeight: 600 }}>Every leg</span>
        <SegCtl label="Legs" items={[['all', 'All'], ['sold', 'Sold'], ['long', 'Long']]} value={filter} onPick={setFilter} />
      </div>
      <div style={{ ...tn, display: 'grid', gridTemplateColumns: cols, gap: 10, padding: '10px 0 8px', borderTop: HAIR_S, ...kicker }}>
        <span>On</span><span>Leg</span><span>Contract</span><span>Count</span><span>At</span><span>Now</span><span>So far</span><span>Delta</span><span>Theta a day</span><span />
      </div>
      {rows.map((r) => {
        const op = r.on ? 1 : 0.45;
        return (
          <div key={(r.added ? 'a' : 'b') + r.l.k} style={{ ...tn, display: 'grid', gridTemplateColumns: cols, gap: 10, alignItems: 'center', padding: '11px 0', borderTop: HAIR }}>
            <Switch on={r.on} label={(r.on ? 'Switch off ' : 'Switch on ') + r.l.lb} onToggle={r.toggle} />
            <span style={{ display: 'flex', flexDirection: 'column', opacity: op }}>
              <span style={{ fontSize: 15 }}>{r.l.lb}</span>
              {r.added && <span style={{ fontSize: 11, fontWeight: 600, color: O }}>added, a what if</span>}
            </span>
            <span style={{ fontSize: 14, opacity: op }}>{r.l.ct}</span>
            <span style={{ fontSize: 14, opacity: op }}>{r.l.qt}</span>
            <span style={{ fontSize: 14, color: MU, opacity: op }}>{r.l.at != null ? price(r.l.at) : ''}</span>
            <span style={{ fontSize: 14, opacity: op }}>{price(r.l.now)}</span>
            <span style={{ fontSize: 14, fontWeight: 600, color: r.sf == null ? MU : cl(r.sf), opacity: op }}>{r.sf == null ? 'new' : mask(money(r.sf))}</span>
            <span style={{ fontSize: 14, color: r.d < 0 ? R : K, opacity: op }}>{count(r.d)}</span>
            <span style={{ fontSize: 14, color: r.th >= 0 ? '#65C466' : R, opacity: op }}>{mask(money(r.th))}</span>
            <span style={{ justifySelf: 'end', opacity: op }}>{r.sd && <LegSdLines v={r.sd} />}</span>
          </div>
        );
      })}
      <div style={{ ...tn, display: 'grid', gridTemplateColumns: cols, gap: 10, alignItems: 'center', padding: '12px 0 0', borderTop: HAIR_S }}>
        <span /><span style={{ fontSize: 14, fontWeight: 600 }}>Switched on</span><span /><span /><span /><span />
        <span style={{ fontSize: 14, fontWeight: 600, color: cl(total.sf) }}>{mask(money(total.sf))}</span>
        <span style={{ fontSize: 14, fontWeight: 600, color: total.d < 0 ? R : K }}>{count(total.d)}</span>
        <span style={{ fontSize: 14, fontWeight: 600, color: cl(total.th) }}>{mask(money(total.th))}</span>
      </div>
    </div>
  );
}

/* ── Whole book and Walls by expiry, side by side (auto-fit, min 360) ──────── */
export function Lists({ t, pr, today, fridayIso }: { t: string; pr: Pricer; today: DPt; fridayIso: string }) {
  const m = pr.m, legs = m.legs;
  const dOf = (ls: PLeg[]) => ls.reduce((a, l) => a + pr.dL(l, m.S0, today), 0);
  const long = legs.filter((l) => l.group === 'l'), sold = legs.filter((l) => l.group === 's');
  const kinds = [['shares', 'shares'], ['leaps', 'LEAPS'], ['otm', 'OTM calls'], ['ins', 'puts']].filter(([k]) => long.some((l) => l.kind === k)).map(([, w]) => w);
  const soldWhat = sold.some((l) => l.ty === 'C') && sold.some((l) => l.ty === 'P') ? 'calls and puts' : sold.some((l) => l.ty === 'P') ? 'puts' : sold.length ? 'calls' : 'calls and puts';
  const exs = [...new Set(sold.map((l) => l.exL))];
  const on = exs.length ? ' on ' + (exs.length === 1 ? exs[0] : exs.slice(0, -1).join(', ') + ' and ' + exs[exs.length - 1]) : '';
  const dl = dOf(long), ds = dOf(sold), dn = dl + ds;
  const book = [
    { l: 'Long', s: kinds.join(', '), v: side(dl) + ' Δ', c: dl < 0 ? R : K },
    { l: 'Sold', s: soldWhat + on, v: sold.length ? side(ds) + ' Δ' : 'None yet', c: sold.length ? (ds < 0 ? R : K) : MU },
    { l: 'Net today', s: 'what moves with the price', v: side(dn) + ' Δ', c: dn < 0 ? R : K },
  ];
  const wall = (c: ChainW) => {
    const w = [c.c ? 'Ceiling ' + fk(c.c.k) : '', c.f ? 'Floor ' + fk(c.f.k) : ''].filter(Boolean);
    if (w.length) return w.join(' · ');
    return c.a ? 'Accelerator ' + fk(c.a.k) : 'No walls saved';
  };
  return (
    <div style={{ ...tn, display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(360px,1fr))', gap: '28px 48px', paddingTop: 28 }}>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        <span style={{ fontSize: 17, fontWeight: 600, paddingBottom: 10 }}>Whole {t} book</span>
        {book.map((r) => (
          <div key={r.l} style={{ ...tn, display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: 10, alignItems: 'center', padding: '11px 0', borderTop: HAIR }}>
            <span style={{ display: 'flex', flexDirection: 'column' }}><span style={{ fontSize: 15 }}>{r.l}</span><span style={{ fontSize: 12, color: MU }}>{r.s}</span></span>
            <span style={{ fontSize: 15, fontWeight: 600, color: r.c, whiteSpace: 'nowrap' }}>{r.v}</span>
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        <span style={{ fontSize: 17, fontWeight: 600, paddingBottom: 10 }}>Walls by expiry</span>
        {m.walls.map((c) => (
          <div key={c.ex} style={{ ...tn, display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: 10, alignItems: 'center', padding: '9px 0', borderTop: HAIR }}>
            <span style={{ display: 'flex', flexDirection: 'column' }}>
              <span style={{ fontSize: 15 }}>{c.label}</span>
              <span style={{ fontSize: 11, color: MU }}>{c.ex === fridayIso ? 'this week' : c.kind.toLowerCase()}</span>
            </span>
            <span style={{ fontSize: 13, fontWeight: 600, color: '#86A8F0', whiteSpace: 'nowrap' }}>{wall(c)}</span>
          </div>
        ))}
        {!m.walls.length && <span style={{ fontSize: 13, color: MU, padding: '9px 0', borderTop: HAIR }}>No walls saved for {t} yet</span>}
      </div>
    </div>
  );
}
