// What if (handoff 2026-11-13-positions §3.6; D10: it replaces 144c, the switches live in Every leg).
//   Try a trade: Sell | Buy, Call | Put, a strike 85% to 120% of the price on the chain's step, the expiry, the count,
//   then "Sell 10 × 36.5 calls · Nov 6", "$0.48 each · Δ short 320 · $481 in", and Add.
//   Your changes: the trades added (from here or the SD calculator), and the legs switched off in Every leg.
//   Net Δ: the whole name with the changes. Cash today: premium in less premium out. Back to the book clears all.
// Every price is the book engine's (Pricer.quote, on the IV a trade is priced on). Nothing is ever sent anywhere.
import { shortDate } from '../lib/clock';
import { count, money, price } from '../lib/format';
import type { Draft } from './whatif';
import { tradeName, type PLeg, type Pricer, type Trade } from './model';
import { G, GLASS, K, MU, O, R, Segmented, kicker, tnum } from './ui';

const field = { height: 34, border: 'none', borderRadius: 10, padding: '0 6px', background: 'rgba(118,118,128,.24)', color: K, fontSize: 13, width: '100%' } as const;

export function WhatIf({ pr, base, off, trades, draft, strikes, expiries, expL, nCh, cashC, mask, setDraft, add, remove, reset }: {
  pr: Pricer; base: PLeg[]; off: Set<string>; trades: Trade[]; draft: Required<Draft>; strikes: number[]; expiries: string[]; expL: (iso: string) => string;
  nCh: number; cashC: number; mask: (s: string) => string;
  setDraft: (d: Draft) => void; add: (u: Omit<Trade, 'id' | 'on'>) => void; remove: (id: number) => void; reset: () => void;
}) {
  const m = pr.m, S0 = m.S0;
  const q = pr.quote({ side: draft.side, ty: draft.ty, K: draft.K, ex: draft.ex, n: draft.n });
  const wi = [...base.filter((l) => !off.has(l.k)), ...pr.trades.filter((l) => trades.find((u) => u.id === l.trade)?.on)];
  const d0 = pr.delta(base, S0, m.today), d1 = pr.delta(wi, S0, m.today), chg = nCh > 0;
  const dTx = (d: number) => (d < 0 ? 'Short ' : 'Long ') + count(d);
  const nOff = base.filter((l) => off.has(l.k)).length;
  return (
    <div style={{ flex: '1 1 340px', minWidth: 284, borderRadius: 24, padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 12, ...GLASS, ...tnum }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-.02em' }}>What if</span>
        <span style={{ fontSize: 13, color: MU }}>{chg ? `${nCh} ${nCh === 1 ? 'change' : 'changes'}` : 'No changes'}</span>
      </div>
      <span style={kicker}>Try a trade</span>
      <div style={{ display: 'flex', gap: 8 }}>
        <Segmented label="Sell or buy" items={[['s', 'Sell'], ['b', 'Buy']]} value={draft.side} onPick={(v) => setDraft({ side: v })} size={13} wrapStyle={{ flex: 1 }} />
        <Segmented label="Call or put" items={[['c', 'Call'], ['p', 'Put']]} value={draft.ty} onPick={(v) => setDraft({ ty: v })} size={13} wrapStyle={{ flex: 1 }} />
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) minmax(0,1.5fr) 54px', gap: 8 }}>
        <label style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
          <span style={{ fontSize: 12, lineHeight: '14px', color: MU }}>Strike</span>
          <select value={String(draft.K)} onChange={(e) => setDraft({ K: +e.target.value })} style={{ ...field, cursor: 'pointer' }}>
            {strikes.map((k) => <option key={k} value={String(k)}>{String(+k.toFixed(2))}</option>)}
          </select>
        </label>
        <label style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
          <span style={{ fontSize: 12, lineHeight: '14px', color: MU }}>Expiry</span>
          <select value={draft.ex} onChange={(e) => setDraft({ ex: e.target.value })} style={{ ...field, cursor: 'pointer' }}>
            {expiries.map((x) => <option key={x} value={x}>{shortDate(x)}</option>)}
          </select>
        </label>
        <label style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
          <span style={{ fontSize: 12, lineHeight: '14px', color: MU }}>Count</span>
          <input type="text" inputMode="numeric" value={String(draft.n)} aria-label="Contracts"
            onChange={(e) => { const t = e.target.value.replace(/\D/g, '').slice(0, 3); setDraft({ n: Math.max(1, +t || 1) }); }} style={{ ...field, cursor: 'text' }} />
        </label>
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10 }}>
        <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
          <span style={{ fontSize: 14, lineHeight: '18px', fontWeight: 600 }}>{tradeName(draft, expL(draft.ex))}</span>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>
            {price(q.per)} each · Δ {dTx(q.delta).toLowerCase()} · <span style={{ fontWeight: 600, color: q.cash >= 0 ? G : R }}>{mask(money(q.cash))} {q.cash >= 0 ? 'in' : 'out'}</span>
          </span>
        </span>
        <button type="button" className="bare swp-add" onClick={() => add({ side: draft.side, ty: draft.ty, K: draft.K, ex: draft.ex, n: draft.n })}
          style={{ flex: 'none', padding: '8px 20px', borderRadius: 999, background: K, color: '#000000', fontSize: 14, fontWeight: 600 }}>Add</button>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, borderTop: '1px solid rgba(255,255,255,.14)', paddingTop: 10 }}>
        <span style={{ ...kicker, paddingBottom: 4 }}>Your changes</span>
        {pr.trades.map((l) => {
          const u = trades.find((x) => x.id === l.trade);
          if (!u) return null;
          const cash = -l.q * 100 * (l.at ?? 0);
          return (
            <div key={l.k} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto 26px', gap: 8, alignItems: 'center', padding: '6px 0', opacity: u.on ? 1 : 0.45 }}>
              <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                <span style={{ fontSize: 14, lineHeight: '18px', fontWeight: 600 }}>{l.lb}</span>
                <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{u.src === 'sd' ? 'from the SD calculator' : 'tried here'}{u.on ? '' : ' · switched off'}</span>
              </span>
              <span style={{ fontSize: 13, fontWeight: 600, color: cash >= 0 ? G : R, whiteSpace: 'nowrap' }}>{mask(money(cash))} {cash >= 0 ? 'in' : 'out'}</span>
              <button type="button" className="xbtn" onClick={() => remove(u.id)} aria-label={`Take off ${l.lb}`} style={{ width: 26, height: 26, fontSize: 11 }}>✕</button>
            </div>
          );
        })}
        {nOff > 0 && <span style={{ padding: '4px 0', fontSize: 13, lineHeight: '18px', color: '#AEAEB2' }}>{nOff} {nOff === 1 ? 'leg' : 'legs'} switched off in Every leg</span>}
        {!trades.length && !nOff && <span style={{ fontSize: 13, lineHeight: '18px', color: MU }}>Nothing yet. Add a trade here, try one from Intelligence, or switch a leg off in Every leg.</span>}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 8 }}>
        <span style={{ fontSize: 13, color: MU }}>Net Δ</span>
        <span style={{ display: 'flex', gap: 6, fontSize: 14, fontWeight: 600, whiteSpace: 'nowrap' }}>
          <span style={{ color: chg ? MU : d0 < 0 ? O : K }}>{dTx(d0)}</span>
          {chg && <><span style={{ color: MU }}>→</span><span style={{ color: d1 < 0 ? O : K }}>{dTx(d1)}</span></>}
        </span>
      </div>
      <div style={{ marginTop: 'auto', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, borderTop: '1px solid rgba(255,255,255,.14)', paddingTop: 12 }}>
        <span style={{ display: 'flex', flexDirection: 'column' }}>
          <span style={{ fontSize: 12, color: MU }}>Cash today</span>
          <span style={{ fontSize: 18, fontWeight: 600, color: cashC >= 0 ? G : R }}>{mask(money(cashC))}</span>
        </span>
        <button type="button" className="bare" onClick={reset} disabled={!chg}
          style={{ padding: '7px 16px', borderRadius: 999, background: 'rgba(118,118,128,.24)', fontSize: 14, fontWeight: 500, opacity: chg ? 1 : 0.4, cursor: chg ? 'pointer' : 'default' }}>Back to the book</button>
      </div>
    </div>
  );
}
