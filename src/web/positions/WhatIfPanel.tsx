// What if (README 2, right column): switch a leg off, or try a trade; the chart, the numbers and the tables follow.
// Nothing is sent to the broker. G1 glass, radius 24, padding 20 22, gap 14.
import { useEffect, useState } from 'react';
import { count, money, price } from '../lib/format';
import { expLabel, fk, tradeName, type PLeg, type Pricer, type Trade } from './model';
import type { Draft } from './whatif';
import { HAIR, HAIR_S, K, MU, O, Seg, Switch, cl, kicker } from './ui';
import { LegSdLines, TradeSdLine } from './sd/LegLines';
import type { LegLines } from './sd/legs';
import { ROLES, isPut, roleOf } from './totals';

interface Props {
  t: string;
  pr: Pricer;
  legs: PLeg[];
  off: Set<string>;
  trades: Trade[];
  nCh: number;
  cashC: number;
  draft: Required<Draft>;
  strikes: number[];
  expiries: string[];
  mask: (s: string) => string;
  toggleLeg: (k: string) => void;
  toggleTrade: (id: number) => void;
  remove: (id: number) => void;
  setDraft: (d: Draft) => void;
  add: (u: Omit<Trade, 'id' | 'on'>) => void;
  reset: () => void;
  /** SD on your positions (139a): each option leg's three lines, and Try a trade's one line. */
  sdOf?: (l: PLeg) => LegLines | null;
  tryLine?: LegLines | null;
}

const select = { boxSizing: 'border-box', width: '100%', height: 36, border: 'none', borderRadius: 10, padding: '0 8px', background: 'rgba(118,118,128,.24)',
  color: '#F5F5F7', fontSize: 14 } as const;
const cashWords = (c: number) => (c >= 0 ? money(c) + ' in' : 'costs ' + money(c));
/** "long 2,083" / "short 1,840": whole shares, the side in words, never a minus sign. */
const dTx = (v: number) => (Math.round(v) < 0 ? 'short ' : 'long ') + count(v);
/** A net that is short reads orange. */
const dCol = (v: number) => (Math.round(v) < 0 ? O : K);
/** A leg's title, strike first (Nik 12 Nov 2026: not "OTM calls" or "Insurance puts" on every strike; the group says
    why it is held): "110 call · Jan 15", or "Shares". */
const titleOf = (l: PLeg) => (l.ty === 'S' ? 'Shares' : `${fk(l.K)} ${l.ty === 'C' ? 'call' : 'put'} · ${l.exL}`);
/** Days left (Nik 12 Nov 2026): "64 days", "1 day", "today". */
const daysTx = (d: number) => (d <= 0 ? 'today' : d === 1 ? '1 day' : count(d) + ' days');
/** The count under it: "×9", or "3,000 shares". */
const subOf = (l: PLeg) => (l.ty === 'S' ? count(l.q) + ' shares' : '×' + count(l.q));
/** Theta a day, the Every leg table's number: red when it costs, green when it earns, never a minus sign. */
const thTx = (v: number, mask: (s: string) => string) => 'Θ ' + mask(money(v)) + ' a day';

export function WhatIfPanel(p: Props) {
  const { t, pr, legs, off, trades, nCh, cashC, draft, strikes, expiries, mask } = p;
  const m = pr.m, chg = nCh > 0;
  const q = pr.quote(draft);
  const exL = (iso: string) => expLabel(iso, m.wholeDays(iso));
  const stp = m.S0 < 50 ? 0.5 : m.S0 < 200 ? 1 : 5;
  // The count as typed; a whole number from 1 to 999 goes in at once, anything else is put right on leaving the box.
  const [nTxt, setNTxt] = useState(String(draft.n));
  useEffect(() => { setNTxt(String(draft.n)); }, [draft.n, t]);
  const tradeRows = pr.trades.map((l) => ({ l, u: trades.find((u) => u.id === l.trade)! })).filter((x) => x.u);

  // Your legs (144c) in Nik's three groups (totals.ts roleOf): Long the shares, Hedge every call then every put bought,
  // Income everything sold, calls then puts. Delta is the page's (each leg's today, at today's price); the net counts
  // every leg switched on and every trade switched on, the SD calculator's included.
  const dOf = (l: PLeg) => pr.dL(l, m.S0, m.today);
  const thOf = (l: PLeg) => (l.ty === 'S' ? 0 : pr.thL(l, m.S0, m.today));
  const tradesOn = pr.trades.filter((l) => trades.find((u) => u.id === l.trade)?.on);
  const dN0 = pr.delta(legs, m.S0, m.today), dN1 = pr.delta([...legs.filter((l) => !off.has(l.k)), ...tradesOn], m.S0, m.today);
  const moved = Math.round(dN1) !== Math.round(dN0);
  const groups = ROLES.map((r) => {
    // Soonest to expire first (Nik 12 Nov 2026), calls before puts on the same day, then by strike.
    const ls = legs.filter((l) => roleOf(l) === r.k)
      .sort((a, b) => (a.ex < b.ex ? -1 : a.ex > b.ex ? 1 : +isPut(a) - +isPut(b) || a.K - b.K));
    const allOff = ls.every((l) => off.has(l.k));
    // Switch all off while any is on; Switch all on once every one is off.
    const toggle = () => ls.forEach((l) => { if (off.has(l.k) === !allOff) return; p.toggleLeg(l.k); });
    const on = ls.filter((l) => !off.has(l.k));
    return { k: r.k, h: r.h, ls, allOff, d: on.reduce((a, l) => a + dOf(l), 0), th: on.reduce((a, l) => a + thOf(l), 0),
      opt: ls.some((l) => l.ty !== 'S'), toggle };
  }).filter((g) => g.ls.length > 0);
  return (
    <div className="g1" style={{ flex: '1 1 340px', minWidth: 0, borderRadius: 24, padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-.02em' }}>What if</span>
        <span style={{ fontSize: 13, color: MU }}>{chg ? nCh + (nCh === 1 ? ' change' : ' changes') : 'no changes yet'}</span>
      </div>
      <span style={{ fontSize: 13, lineHeight: '19px', color: MU, textWrap: 'pretty' } as React.CSSProperties}>
        Switch a leg off to see the book without it, or try a trade. The chart, the numbers and the table follow. Nothing is sent to the broker.
      </span>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        <div className="tnum" style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12, paddingBottom: 6 }}>
          <span style={kicker}>Your {t} legs</span>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 6, fontSize: 13, lineHeight: '18px', fontWeight: 600, whiteSpace: 'nowrap' }}>
            <span style={{ color: moved ? MU : dCol(dN0) }}>Net Δ {dTx(dN0)}</span>
            {moved && <><span style={{ color: MU }}>→</span><span style={{ color: dCol(dN1) }}>{dTx(dN1)}</span></>}
          </span>
        </div>
        {groups.map((g, gi) => (
          <div key={g.k} role="group" aria-label={g.h} style={{ display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: gi ? '14px 0 4px' : '8px 0 4px',
              borderTop: '1px solid rgba(255,255,255,.16)' }}>
              <span className="tnum" style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{g.h}</span>
                <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: MU }}>
                  {g.allOff ? 'Off' : <>Δ {dTx(g.d)}{g.opt && <> · <span style={{ color: cl(g.th) }}>{thTx(g.th, mask)}</span></>}</>}
                </span>
              </span>
              <button type="button" className="bare swp-all" onClick={g.toggle}
                style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: MU, padding: '6px 0' }}>{g.allOff ? 'Switch all on' : 'Switch all off'}</button>
            </div>
            {g.ls.map((l) => {
              // A leg switched off dims to 42% and says what closing it would do: a bought leg brings cash in, buying
              // back a sold one costs. Shares get no SD lines.
              const o = off.has(l.k), cc = l.value, s = p.sdOf?.(l) ?? null, op = o ? 0.42 : 1, sub = subOf(l), ttl = titleOf(l), th = thOf(l), days = daysTx(m.wholeDays(l.ex));
              return (
                <div key={l.k} className="tnum" style={{ display: 'grid', gridTemplateColumns: '48px minmax(0,1fr) auto', gap: 10, alignItems: 'center', padding: '10px 0', borderTop: HAIR }}>
                  <Switch on={!o} label={(o ? 'Switch on ' : 'Switch off ') + ttl + ', ' + sub} onToggle={() => p.toggleLeg(l.k)} />
                  <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                    <span style={{ display: 'flex', flexDirection: 'column', opacity: op, transition: 'opacity .2s' }}>
                      <span style={{ fontSize: 15, lineHeight: '20px' }}>{ttl}</span>
                      {/* Count, days left and theta (Nik 12 Nov 2026); a leg's delta is in the Every leg table, and the
                          net above shows what switching it does. */}
                      <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{sub}{l.ty !== 'S' && ' · ' + days}</span>
                      {l.ty !== 'S' && <span style={{ fontSize: 12, lineHeight: '16px', color: cl(th), whiteSpace: 'nowrap' }}>{thTx(th, mask)}</span>}
                    </span>
                    {o && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: cl(cc), whiteSpace: 'nowrap' }}>{mask('close · ' + cashWords(cc))}</span>}
                  </span>
                  {s ? <LegSdLines v={s} style={{ opacity: op, transition: 'opacity .2s' }} /> : <span />}
                </div>
              );
            })}
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, borderTop: HAIR_S, paddingTop: 14 }}>
        <span style={kicker}>Try a trade</span>
        <div style={{ display: 'flex', gap: 8 }}>
          <Seg label="Buy or sell" items={[['b', 'Buy'], ['s', 'Sell']]} value={draft.side} onPick={(v) => p.setDraft({ side: v })} />
          <Seg label="Call or put" items={[['c', 'Call'], ['p', 'Put']]} value={draft.ty} onPick={(v) => p.setDraft({ ty: v })} />
        </div>
        <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) minmax(0,1.3fr) 74px', gap: 8 }}>
          <label style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
            <span style={{ fontSize: 11, color: MU }}>Strike</span>
            <select value={fk(draft.K)} onChange={(e) => p.setDraft({ K: +e.target.value })} style={{ ...select, cursor: 'pointer' }}>
              {strikes.map((x) => <option key={x} value={fk(x)}>{fk(x) + (Math.abs(x - m.S0) < stp / 2 ? ' · at the money' : '')}</option>)}
            </select>
          </label>
          <label style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
            <span style={{ fontSize: 11, color: MU }}>Expiry</span>
            <select value={draft.ex} onChange={(e) => p.setDraft({ ex: e.target.value })} style={{ ...select, cursor: 'pointer' }}>
              {expiries.map((x) => { const d = m.wholeDays(x); return <option key={x} value={x}>{exL(x) + (d < 365 ? ' · ' + d + ' days' : '')}</option>; })}
            </select>
          </label>
          <label style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
            <span style={{ fontSize: 11, color: MU }}>Count</span>
            <input type="number" min={1} max={999} value={nTxt} style={select}
              onChange={(e) => { setNTxt(e.target.value); const v = Math.round(+e.target.value); if (v >= 1 && v <= 999) p.setDraft({ n: v }); }}
              onBlur={() => { const v = Math.max(1, Math.min(999, Math.round(+nTxt || 1))); setNTxt(String(v)); p.setDraft({ n: v }); }} />
          </label>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10 }}>
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
            <span style={{ fontSize: 14, fontWeight: 600 }}>{tradeName(draft, exL(draft.ex))}</span>
            <span style={{ fontSize: 12, color: MU }}>
              {price(q.per)} a share · delta {q.delta < 0 ? 'short ' : 'long '}{count(q.delta)} · <span style={{ fontWeight: 600, color: cl(q.cash) }}>{mask(cashWords(q.cash))}</span>
            </span>
          </span>
          <button type="button" className="bare swp-add" onClick={() => p.add({ side: draft.side, ty: draft.ty, K: draft.K, ex: draft.ex, n: draft.n })}
            style={{ flex: 'none', padding: '8px 20px', borderRadius: 999, background: K, color: '#000000', fontSize: 14, fontWeight: 600 }}>Add</button>
        </div>
        {/* Under the summary line, the trade's strike against today (README "Try a trade"): the full width, so it
            stays one line beside nothing; it follows the strike, expiry, side and Buy or Sell. */}
        {p.tryLine && <TradeSdLine v={p.tryLine} style={{ marginTop: -8 }} />}
        {tradeRows.length > 0 && (
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {tradeRows.map(({ l, u }) => {
              const cash = -l.value;
              return (
                <div key={l.k} className="tnum" style={{ display: 'grid', gridTemplateColumns: '48px minmax(0,1fr) auto 28px', gap: 8, alignItems: 'center', padding: '9px 0', borderTop: HAIR }}>
                  <Switch on={u.on} label={(u.on ? 'Switch off ' : 'Switch on ') + l.lb} onToggle={() => p.toggleTrade(u.id)} />
                  <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                    <span style={{ fontSize: 14 }}>{l.lb}</span>
                    <span style={{ fontSize: 12, color: MU }}>{price(l.now)} each today</span>
                  </span>
                  <span style={{ fontSize: 12, fontWeight: 600, color: cl(cash), textAlign: 'right', whiteSpace: 'nowrap' }}>{mask(cashWords(cash))}</span>
                  <button type="button" className="bare" aria-label={'Remove ' + l.lb} onClick={() => p.remove(u.id)}
                    style={{ width: 26, height: 26, borderRadius: '50%', background: '#2C2C2E', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 11, color: '#AEAEB2' }}>✕</button>
                </div>
              );
            })}
          </div>
        )}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, borderTop: HAIR_S, paddingTop: 12 }}>
        <span style={{ display: 'flex', flexDirection: 'column' }}>
          <span style={{ fontSize: 12, color: MU }}>Cash today</span>
          <span style={{ fontSize: 18, fontWeight: 600, color: chg ? cl(cashC) : MU }}>{chg ? mask(money(cashC) + (cashC >= 0 ? ' in' : ' out')) : 'Nothing yet'}</span>
        </span>
        <button type="button" className="bare" onClick={p.reset} disabled={!chg}
          style={{ padding: '7px 16px', borderRadius: 999, background: 'rgba(118,118,128,.24)', fontSize: 14, fontWeight: 500, opacity: chg ? 1 : 0.4 }}>Back to the book</button>
      </div>
      <style>{`.sw .swp-all:hover{color:#F5F5F7!important}`}</style>
    </div>
  );
}
