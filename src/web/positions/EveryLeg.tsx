// Every leg (handoff 2026-11-13-positions §3.7; D7, D10): always shown, a switch on each row, the Whole TICKER book
// row. Columns: On, Contract, Leg, Count, At, Now, So far, Delta, Theta a day (Contract before Leg: Nik, 17 Nov 2026).
//   Leg is the group (Nik's rule, totals.ts: Long = shares, Hedge = every leg bought, Income = every leg sold) and the
//   contract is strike first ("36 call · Oct 30"), never "OTM calls", "Insurance puts" or "LEAPS".
//   So far = (mark − entry) × q × mul; Delta = q × 100 × Δ (shares q); Theta a day = q × 100 × θ (the server's grid).
//   A leg that is off drops out of Payoff, the Greeks and the Whole row; its row fades to .4. Legs sold start on, shares
//   and legs bought start off (Nik, 13 Nov 2026; the page works it out, whatif.ts).
// Count is signed (Nik, 17 Nov 2026): +40 bought, −40 sold, +3,000 shares. A count, not money, so the "no minus sign"
//   money rule does not apply.
// The Whole row's At cell (Nik, 17 Nov 2026, option B): "$25.9K in" (at × count × 100 over the legs sold) over "$5.0K out"
//   (the legs bought). Same legs as So far: switched on, not the What if trades. Shares left out: their cost would swamp it.
// Soonest expiry first inside each group, calls before puts on the same day, then the strike.
import { count, money, price } from '../lib/format';
import type { PLeg, Pricer, Trade } from './model';
import { ROLES, roleOf, type Role } from './totals';
import { K, MU, O, Segmented, Switch, cl, tnum } from './ui';

const COLS = '52px minmax(104px,1.2fr) minmax(64px,.7fr) 84px 64px 64px 84px 104px 100px';
const ROLE_H: Record<Role, string> = { long: 'Long', hedge: 'Hedge', income: 'Income' };
export type LegFilter = 'all' | Role;
const ord = (a: PLeg, b: PLeg) => {
  const ri = (l: PLeg) => ROLES.findIndex((r) => r.k === roleOf(l));
  return ri(a) - ri(b) || a.ex.localeCompare(b.ex) || (a.ty === 'P' ? 1 : 0) - (b.ty === 'P' ? 1 : 0) || a.K - b.K;
};

export function EveryLeg({ t, pr, base, off, note, trades, toggleLeg, toggleTrade, filter, setFilter, mask }: {
  t: string; pr: Pricer; base: PLeg[]; off: Set<string>; note?: string; trades: Trade[]; toggleLeg: (k: string) => void; toggleTrade: (id: number) => void;
  filter: LegFilter; setFilter: (f: LegFilter) => void; mask: (s: string) => string;
}) {
  const m = pr.m, S0 = m.S0, D = m.today;
  const soFar = (l: PLeg) => (l.ty === 'S' ? l.q * (S0 - l.K) : l.at != null ? (l.now - l.at) * l.q * 100 : 0);
  const fOk = (l: PLeg) => filter === 'all' || roleOf(l) === filter;
  const tOn = (l: PLeg) => !!trades.find((u) => u.id === l.trade)?.on;
  const rows = [
    ...base.slice().sort(ord).filter(fOk).map((l) => ({ l, on: !off.has(l.k), tg: () => toggleLeg(l.k), added: false })),
    ...pr.trades.slice().sort(ord).filter(fOk).map((l) => ({ l, on: tOn(l), tg: () => toggleTrade(l.trade!), added: true })),
  ];
  const wi = [...base.filter((l) => !off.has(l.k)), ...pr.trades.filter(tOn)];
  const chg = off.size > 0 || pr.trades.some(tOn);
  const onB = base.filter((l) => !off.has(l.k)), cash = (l: PLeg) => (l.ty === 'S' || l.at == null ? 0 : l.at * Math.abs(l.q) * 100);
  const inT = onB.filter((l) => l.q < 0).reduce((a, l) => a + cash(l), 0), outT = onB.filter((l) => l.q > 0).reduce((a, l) => a + cash(l), 0);
  const sfT = onB.reduce((a, l) => a + soFar(l), 0), dT = pr.delta(wi, S0, D), thT = wi.reduce((a, l) => a + pr.thL(l, S0, D), 0);
  const dTx = (d: number) => (d < 0 ? 'Short ' : 'Long ') + count(d);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', ...tnum }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, paddingBottom: 12, flexWrap: 'wrap' }}>
        <span style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-.01em' }}>Every leg</span>
        <Segmented label="Legs" items={[['all', 'All'], ['long', 'Long'], ['hedge', 'Hedge'], ['income', 'Income']]} value={filter} onPick={setFilter} size={13} width={300} />
      </div>
      <div className="swp-scroll" style={{ overflowX: 'auto' }}>
        <div style={{ minWidth: 800 }}>
          <div style={{ display: 'grid', gridTemplateColumns: COLS, gap: 10, padding: '8px 0', borderTop: '1px solid rgba(255,255,255,.14)', fontSize: 12, lineHeight: '16px', fontWeight: 600,
            letterSpacing: '.05em', textTransform: 'uppercase', color: MU }}>
            <span>On</span><span>Contract</span><span>Leg</span><span>Count</span><span>At</span><span>Now</span><span>So far</span><span>Delta</span><span>Theta a day</span>
          </div>
          {rows.map(({ l, on, tg, added }) => {
            const opt = l.ty !== 'S', dl = pr.dL(l, S0, D), th = opt ? pr.thL(l, S0, D) : 0, sf = soFar(l), op = on ? 1 : 0.4;
            const ct = opt ? l.ct : `${t} shares`, grp = ROLE_H[roleOf(l)];
            const qt = (l.q < 0 ? '−' : '+') + count(l.q), qa = opt ? `${count(l.q)} ${l.q < 0 ? 'sold' : 'bought'}` : `${count(l.q)} shares`;
            return (
              <div key={l.k} role="row" aria-label={`${grp}, ${ct}, ${qa}, so far ${mask(money(sf))}${sf < 0 ? ' down' : ''}, delta ${dTx(dl)}, ${on ? 'on' : 'off'}`}
                style={{ display: 'grid', gridTemplateColumns: COLS, gap: 10, alignItems: 'center', padding: '11px 0', borderTop: '1px solid rgba(255,255,255,.08)' }}>
                <Switch on={on} label={`${on ? 'Switch off' : 'Switch on'} ${ct}`} onToggle={tg} />
                <span style={{ fontSize: 14, opacity: op }}>{ct}</span>
                <span style={{ display: 'flex', flexDirection: 'column', opacity: op, minWidth: 0 }}>
                  <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{grp}</span>
                  {added && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: O }}>added, a what if</span>}
                </span>
                <span style={{ fontSize: 14, opacity: op }}>{qt}</span>
                <span style={{ fontSize: 14, color: MU, opacity: op }}>{l.at != null ? price(l.at) : '-'}</span>
                <span style={{ fontSize: 14, opacity: op }}>{price(l.now)}</span>
                <span style={{ fontSize: 14, fontWeight: 600, color: added ? MU : cl(sf), opacity: op }}>{added ? 'new' : mask(money(sf))}</span>
                <span style={{ fontSize: 14, opacity: op }}>{dTx(dl)}</span>
                <span style={{ fontSize: 14, color: opt ? cl(th) : MU, opacity: op }}>{mask(money(th))}</span>
              </div>
            );
          })}
          <div style={{ display: 'grid', gridTemplateColumns: COLS, gap: 10, alignItems: 'center', padding: '12px 0 0', borderTop: '1px solid rgba(255,255,255,.2)' }}
            aria-label={`Whole ${t} book, ${mask(money(inT))} in, ${mask(money(outT))} out, so far ${mask(money(sfT))}, delta ${dTx(dT)}, theta ${mask(money(thT))} a day`} role="row">
            <span />
            <span style={{ gridColumn: 'span 3', display: 'flex', flexDirection: 'column' }}>
              <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 700 }}>Whole {t} book</span>
              <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{note ?? (chg ? 'with your changes' : 'every leg on')}</span>
            </span>
            <span style={{ gridColumn: 'span 2', display: 'flex', flexDirection: 'column', whiteSpace: 'nowrap' }}>
              <span style={{ fontSize: 14, lineHeight: '20px', fontWeight: 700 }}>{mask(money(inT))} in</span>
              <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{mask(money(outT))} out</span>
            </span>
            <span style={{ fontSize: 14, fontWeight: 700, color: cl(sfT) }}>{mask(money(sfT))}</span>
            <span style={{ fontSize: 14, fontWeight: 700, color: dT < 0 ? O : K }}>{dTx(dT)}</span>
            <span style={{ fontSize: 14, fontWeight: 700, color: cl(thT) }}>{mask(money(thT))}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
