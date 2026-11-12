// The tables on Positions (README 2): Compare under the chart, then under both columns P&L by price and date, Every
// leg, and the two lists, Whole book and Walls by expiry. Each is drawn as the design draws it; every number is the
// book's, summed from the server's grid (and the engine for What if trades).
import { count, money, price } from '../lib/format';
import { fk, type ChainW, type DPt, type PLeg, type Pricer, type Seg } from './model';
import { HAIR, HAIR_S, K, MU, O, R, Seg as SegCtl, Switch, cl, kicker } from './ui';
import { LegSdLines } from './sd/LegLines';
import type { LegLines } from './sd/legs';
import { ROLES, roleOf, type Role } from './totals';

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
/** The filter (D4, Nik 11 Nov 2026): All · Long · Hedge · Income, the What if's groups (totals.ts roleOf). */
export type LegFilter = 'all' | Role;
export function EveryLeg({ rows, total, filter, setFilter, mask }:
  { rows: LegRow[]; total: { sf: number; d: number; th: number }; filter: LegFilter; setFilter: (f: LegFilter) => void; mask: (s: string) => string }) {
  const cols = '52px minmax(0,1fr) 140px 96px 64px 64px 80px 80px 76px 160px';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', paddingTop: 28 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingBottom: 10 }}>
        <span style={{ fontSize: 17, fontWeight: 600 }}>Every leg</span>
        <SegCtl<LegFilter> label="Legs" items={[['all', 'All'], ['long', 'Long'], ['hedge', 'Hedge'], ['income', 'Income']]} value={filter} onPick={setFilter} />
      </div>
      <div style={{ ...tn, display: 'grid', gridTemplateColumns: cols, gap: 10, padding: '10px 0 8px', borderTop: HAIR_S, ...kicker }}>
        <span>On</span><span>Leg</span><span>Contract</span><span>Count</span><span>At</span><span>Now</span><span>So far</span><span>Delta</span><span>Theta a day</span><span />
      </div>
      {rows.map((r) => {
        const op = r.on ? 1 : 0.45;
        return (
          <div key={(r.added ? 'a' : 'b') + r.l.k} style={{ ...tn, display: 'grid', gridTemplateColumns: cols, gap: 10, alignItems: 'center', padding: '11px 0', borderTop: HAIR }}>
            <Switch on={r.on} label={(r.on ? 'Switch off ' : 'Switch on ') + (r.added ? r.l.lb : r.l.ct)} onToggle={r.toggle} />
            <span style={{ display: 'flex', flexDirection: 'column', opacity: op }}>
              {/* The leg's group, not "OTM calls" or "Insurance puts" (Nik 12 Nov 2026); a trade keeps its name. */}
              <span style={{ fontSize: 15 }}>{r.added ? r.l.lb : ROLES.find((x) => x.k === roleOf(r.l))?.h ?? r.l.lb}</span>
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
  // Whole book in Nik's groups (totals.ts roleOf, 11 Nov 2026): Long the shares; Hedge every call bought (LEAPS
  // included), then every put bought; Income, what was sold, calls then puts. Each line is its legs'
  // delta today, as before; a line with no legs is left out, and a group with no lines.
  const n = (ls: PLeg[]) => ls.reduce((a, l) => a + Math.abs(l.q), 0);
  const and = (xs: string[]) => (xs.length < 2 ? xs[0] ?? '' : xs.slice(0, -1).join(', ') + ' and ' + xs[xs.length - 1]);
  const exOn = (ls: PLeg[]) => { const e = [...new Set(ls.map((l) => l.exL))]; return e.length ? ' · ' + and(e) : ''; };
  const of = (r: Role, ty: 'S' | 'C' | 'P') => legs.filter((l) => roleOf(l) === r && l.ty === ty);
  const sh = of('long', 'S'), hc = of('hedge', 'C'), hp = of('hedge', 'P'), ic = of('income', 'C'), ip = of('income', 'P');
  const lp = hc.filter((l) => l.kind === 'leaps'), oc = hc.filter((l) => l.kind !== 'leaps');
  const line = (k: string, l: string, ls: PLeg[], s: string) => { const d = dOf(ls); return { k, l, ls, s, v: side(d) + ' Δ', c: d < 0 ? R : K }; };
  const groups = [
    { h: 'Long', items: [line('sh', 'Shares', sh, count(n(sh)) + ' shares')] },
    { h: 'Hedge', items: [
      line('hc', 'Calls', hc, [lp.length ? count(n(lp)) + ' LEAPS' : '', oc.length ? count(n(oc)) + ' OTM calls' : ''].filter(Boolean).join(' · ')),
      line('hp', 'Puts', hp, count(n(hp)) + ' insurance puts' + exOn(hp)),
    ] },
    { h: 'Income', items: [line('ic', 'Calls', ic, count(n(ic)) + ' calls' + exOn(ic)), line('ip', 'Puts', ip, count(n(ip)) + ' puts' + exOn(ip))] },
  ].map((g) => ({ ...g, items: g.items.filter((x) => x.ls.length > 0) })).filter((g) => g.items.length > 0);
  const dn = dOf(legs);
  const net = { l: 'Net today', s: 'what moves with the price', v: side(dn) + ' Δ', c: dn < 0 ? R : K };
  const row = { ...tn, display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: 10, alignItems: 'center', padding: '11px 0' } as const;
  const wall = (c: ChainW) => {
    const w = [c.c ? 'Ceiling ' + fk(c.c.k) : '', c.f ? 'Floor ' + fk(c.f.k) : ''].filter(Boolean);
    if (w.length) return w.join(' · ');
    return c.a ? 'Accelerator ' + fk(c.a.k) : 'No walls saved';
  };
  return (
    <div style={{ ...tn, display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(360px,1fr))', gap: '28px 48px', paddingTop: 28 }}>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        <span style={{ fontSize: 17, fontWeight: 600, paddingBottom: 10 }}>Whole {t} book</span>
        {groups.map((g, gi) => (
          <div key={g.h} role="group" aria-label={g.h} style={{ display: 'flex', flexDirection: 'column' }}>
            <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 700, padding: `${gi ? 14 : 2}px 0 6px` }}>{g.h}</span>
            {g.items.map((r) => (
              <div key={r.k} style={{ ...row, borderTop: HAIR }}>
                <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}><span style={{ fontSize: 15 }}>{r.l}</span><span style={{ fontSize: 12, color: MU }}>{r.s}</span></span>
                <span style={{ fontSize: 15, fontWeight: 600, color: r.c, whiteSpace: 'nowrap' }}>{r.v}</span>
              </div>
            ))}
          </div>
        ))}
        <div style={{ ...row, marginTop: 6, borderTop: HAIR_S }}>
          <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}><span style={{ fontSize: 15, fontWeight: 600 }}>{net.l}</span><span style={{ fontSize: 12, color: MU }}>{net.s}</span></span>
          <span style={{ fontSize: 15, fontWeight: 600, color: net.c, whiteSpace: 'nowrap' }}>{net.v}</span>
        </div>
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
