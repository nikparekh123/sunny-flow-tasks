// Intelligence (handoff 2026-11-13-positions §3.9): a glass capsule that opens into the full window.
//   Header, the expiry chips (D1: it opens on this Friday's expiry), the SD calculator (D8: the engine's own rule,
//   sd-engine calc() on the server, with its signals under Why; the tiles are the engine's ladder), Today's alerts,
//   the read (D4: only the sale being picked), then the lanes on one price scale.
// Data: the name's sunny-sd reply (useSd), the book's legs for Net Δ and Try in What if (Pricer, the What if store).
// Escape closes it. No em dashes in any words here.
import { useEffect, useMemo, useRef } from 'react';
import { sdColour } from '../../../supabase/functions/_shared/positions-engine.ts';
import { count, money, price } from '../lib/format';
import { intelModel, ivAtStrike, ladder, rowAt, sdl, useIntelScroll, usePick, type IntelModel, type SdReply } from './intel';
import { Lanes } from './Lanes';
import type { ChainW, PLeg, Pricer, Trade } from './model';
import { Fold, FoldAway, G, GLASS, K, MT, MU, O, SOFT, Segmented, kicker, tnum, useReducedMotion } from './ui';

export interface IntelProps {
  book: string; t: string; d: SdReply | undefined; busy: boolean; failed: boolean; friday: string; chains: ChainW[];
  pr: Pricer | null; base: PLeg[]; off: Set<string>; trades: Trade[];
  setSd: (us: Omit<Trade, 'id' | 'on'>[] | null) => void;
  open: boolean; setOpen: (v: boolean) => void; mask: (s: string) => string;
}

export function Intelligence(props: IntelProps) {
  const { book, t, d, busy, failed, friday, chains, open, setOpen } = props;
  const { p, set } = usePick(book, t);
  const ok = !!d?.ok && d.t === t;
  const M = useMemo(() => (ok ? intelModel(d!, p, friday, chains) : null), [ok, d, p, friday, chains]);
  useEffect(() => {
    if (!open) return;
    const f = (ev: KeyboardEvent) => { if (ev.key === 'Escape') setOpen(false); };
    window.addEventListener('keydown', f);
    return () => window.removeEventListener('keydown', f);
  }, [open, setOpen]);
  // A Sold in SD row tap: once the window has opened (the capsule folds away above it), bring it into view.
  const seq = useIntelScroll(), done = useRef(seq), box = useRef<HTMLDivElement>(null), rm = useReducedMotion();
  useEffect(() => {
    if (seq === done.current || !open) return;
    done.current = seq;
    const tm = setTimeout(() => {
      const el = box.current;
      if (el) window.scrollBy({ top: el.getBoundingClientRect().top - 90, behavior: rm ? 'auto' : 'smooth' });
    }, rm ? 60 : 480);
    return () => clearTimeout(tm);
  }, [seq, open, rm]);
  const alS = M?.alerts.length ? (M.alerts.length === 1 ? M.alerts[0].text.replace(/^[↑↓] /, '') : `${M.alerts.length} levels hit today`) : null;
  return (
    <div ref={box} style={{ display: 'flex', flexDirection: 'column', scrollMarginTop: 90 }}>
      <FoldAway open={open}>
        <button type="button" className="bare" onClick={() => setOpen(true)} aria-expanded={false}
          style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, padding: '14px 20px', borderRadius: 20, ...GLASS }}>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 10, minWidth: 0, flexWrap: 'wrap' }}>
            <span style={{ fontSize: 17, fontWeight: 600 }}>Intelligence</span>
            <span style={{ fontSize: 13, color: MU }}>The SD calculator, the read and the lanes on one price scale{M ? `, for ${M.e.label}` : ''}</span>
          </span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, flex: 'none' }}>
            {alS && <span style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '4px 10px', borderRadius: 999, background: 'rgba(255,214,10,.12)', boxShadow: 'inset 0 0 0 1px rgba(255,214,10,.55)',
              color: '#FFD60A', fontSize: 13, lineHeight: '18px', fontWeight: 600, whiteSpace: 'nowrap' }}><span style={{ width: 6, height: 6, borderRadius: '50%', background: '#FFD60A' }} />{alS}</span>}
            <span style={{ fontSize: 14, fontWeight: 600 }}>Open</span>
          </span>
        </button>
      </FoldAway>
      <Fold open={open}>
        <div role="region" aria-label="Intelligence" style={{ padding: '22px 24px', borderRadius: 24, ...SOFT, display: 'flex', flexDirection: 'column', gap: 18 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16 }}>
            <span style={{ display: 'flex', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' }}>
              <span style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-.02em' }}>Intelligence</span>
              <span style={{ fontSize: 14, color: MU }}>{t} · one expiry, three layers</span>
            </span>
            <button type="button" className="bare" onClick={() => setOpen(false)} aria-label="Close Intelligence"
              style={{ width: 32, height: 32, borderRadius: '50%', background: 'rgba(118,118,128,.24)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: MT, flex: 'none' }}>✕</button>
          </div>
          {M && d ? <Body {...props} d={d} M={M} pick={p} setPick={set} /> : (
            <span style={{ fontSize: 14, color: MU, padding: '12px 0' }} aria-busy={busy}>
              {failed ? `Could not read ${t}’s option chain just now.` : `Reading ${t}’s option chain…`}
            </span>
          )}
        </div>
      </Fold>
    </div>
  );
}

function Body({ t, d, M, pick, setPick, pr, base, off, trades, setSd, mask }: IntelProps & { d: SdReply; M: IntelModel; pick: ReturnType<typeof usePick>['p']; setPick: ReturnType<typeof usePick>['set'] }) {
  const { e } = M, S = M.S;
  const exItems = d.exps.map((x) => [x.ex, x.label] as [string, string]);
  const put = M.side === 'p';
  const k = put ? M.kp : M.kc, rule = put ? M.ruleP : M.ruleC, sel = put ? pick.selP : pick.selC;
  const n = put ? M.nP : M.nC;
  const setN = (v: number) => setPick(put ? { nP: Math.max(0, Math.min(999, v)) } : { nC: Math.max(0, Math.min(999, v)) });
  // The trade line: both sides at their counts, the cash in, the net delta after (the book's, switches and What if
  // trades on, less the calculator's own earlier try), Try in What if.
  const legs = M.nw;
  const cash = legs.reduce((a, l) => a + l.n * 100 * l.p, 0);
  const net = useMemo(() => {
    if (!pr) return null;
    const keep = pr.trades.filter((l) => { const u = trades.find((x) => x.id === l.trade); return u?.on && u.src !== 'sd'; });
    const wi = [...base.filter((l) => !off.has(l.k)), ...keep];
    let dd = pr.delta(wi, pr.m.S0, pr.m.today);
    for (const l of legs) dd += pr.quote({ side: 's', ty: l.put ? 'p' : 'c', K: l.K, ex: e.ex, n: l.n, iv: ivAtStrike(e, l.K) }).delta;
    return dd;
  }, [pr, trades, base, off, legs, e]);
  const sdNow = trades.filter((u) => u.src === 'sd');
  const tried = legs.length > 0 && sdNow.length === legs.length && legs.every((l) => sdNow.some((u) => u.ty === (l.put ? 'p' : 'c') && Math.abs(u.K - l.K) < 1e-9 && u.n === l.n && u.ex === e.ex));
  const tryIt = () => setSd(tried ? null : legs.map((l) => ({ side: 's' as const, ty: l.put ? 'p' as const : 'c' as const, K: l.K, ex: e.ex, n: l.n, pr: l.p, iv: ivAtStrike(e, l.K), src: 'sd' as const })));
  const desc = legs.map((l) => `${l.n} × ${+l.K.toFixed(2)} ${l.put ? 'puts' : 'calls'}`).join(' and ');
  const cv = M.cov;
  const tiles = ladder(d, e, put);
  return <>
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16, flexWrap: 'wrap' }}>
      <Segmented label="Expiry" items={exItems} value={e.ex} onPick={(x) => setPick({ ex: x, selC: null, selP: null })} wrapStyle={{ width: 600, maxWidth: '100%' }} />
      <span style={{ fontSize: 13, color: MU }}>{e.long} · {e.cd <= 0 ? 'ends today' : e.cd === 1 ? '1 day' : `${e.cd} days`} · {M.kind}</span>
    </div>
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, padding: '16px 18px', borderRadius: 18, background: 'rgba(255,255,255,.04)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.08)', ...tnum }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12, flexWrap: 'wrap' }}>
        <span style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
          <span style={{ fontSize: 17, fontWeight: 600 }}>SD calculator</span>
          <span style={{ fontSize: 13, color: MU }}>{e.long} · ±{(M.m * 100).toFixed(1)}% priced</span>
        </span>
        <button type="button" className="bare" onClick={() => setPick({ why: !pick.why })} aria-expanded={pick.why} style={{ fontSize: 13, lineHeight: '18px', color: MT }}>
          Rule for {e.label}: calls {sdl(M.ruleC)}, puts {sdl(M.ruleP)} · <span style={{ fontWeight: 600, color: K }}>{pick.why ? 'Hide' : 'Why'}</span>
        </button>
      </div>
      {pick.why && (
        <div role="list" aria-label="Why the rule picks these strikes" style={{ display: 'flex', flexDirection: 'column', borderTop: '1px solid rgba(255,255,255,.08)' }}>
          {e.sig.map((g, i) => (
            <div key={g.key} role="listitem" style={{ display: 'grid', gridTemplateColumns: '24px 130px 170px minmax(0,1fr)', gap: 12, alignItems: 'baseline', padding: '8px 0', borderBottom: '1px solid rgba(255,255,255,.06)' }}>
              <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 700, color: MU }}>{i + 1}</span>
              <span style={{ fontSize: 14, lineHeight: '18px', fontWeight: 600 }}>{g.k}</span>
              <span style={{ fontSize: 14, lineHeight: '18px', color: g.vTone === 'red' ? '#FF6961' : g.vTone === 'green' ? G : g.vTone === 'or' ? O : MT }}>
                {g.v}{g.tag ? <span style={{ color: g.tagTone === 'or' ? O : MU }}> · {g.tag}</span> : null}
              </span>
              <span style={{ display: 'flex', flexDirection: 'column', gap: 2, fontSize: 14, lineHeight: '18px', color: MT }}>
                {g.s && <span>{g.s}</span>}
                {g.fx.map(([kk, tx], j) => <span key={j} style={{ fontWeight: kk === 'n' ? 500 : 600, color: kk === 'n' ? MT : kk === 'x' ? O : K }}>{tx}</span>)}
              </span>
            </div>
          ))}
          <div style={{ display: 'grid', gridTemplateColumns: '24px 130px minmax(0,1fr)', gap: 12, alignItems: 'baseline', padding: '8px 0' }}>
            <span style={{ fontSize: 12, fontWeight: 700, color: MU }}>{e.sig.length + 1}</span>
            <span style={{ fontSize: 14, fontWeight: 600 }}>The rule</span>
            <span style={{ fontSize: 14, fontWeight: 600, color: O }}>Call {sdl(M.ruleC)}, put {sdl(M.ruleP)}: {fmtK(e.sug.C.K)} and {fmtK(e.sug.P.K)}</span>
          </div>
        </div>
      )}
      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(160px,220px) minmax(0,1fr) 150px', gap: 16, alignItems: 'end' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>Sell</span>
          <Segmented label="Sell a call or a put" items={[['c', 'Call'], ['p', 'Put']]} value={M.side} onPick={(v) => setPick({ side: v })} width="100%" />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>How far out · the strike</span>
          <div className="swp-scroll" style={{ display: 'flex', gap: 6, overflowX: 'auto', margin: -2, padding: 2 }}>
            {tiles.map((kk) => {
              const r = rowAt(e, kk, put)!, on = sel != null && Math.abs(sel - kk) < 1e-9, isRule = Math.abs(kk - rule) < 1e-9, pk = r.K / S - 1;
              return (
                <button key={kk} type="button" className="bare" aria-pressed={on} onClick={() => setPick(put ? { selP: on ? null : kk } : { selC: on ? null : kk })}
                  aria-label={`${sdl(kk)}, strike ${fmtK(r.K)}, ${(Math.abs(pk) * 100).toFixed(1)}% ${pk >= 0 ? 'above' : 'below'} today${isRule ? ', the rule' : ''}`}
                  style={{ flex: '1 0 74px', display: 'flex', flexDirection: 'column', gap: 1, padding: '7px 10px', borderRadius: 12, background: on ? K : 'rgba(118,118,128,.24)', transition: 'background .2s',
                    boxShadow: !on && sel == null && isRule ? 'inset 0 0 0 1.5px rgba(245,245,247,.45)' : 'none' }}>
                  <span style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 12, lineHeight: '16px', fontWeight: 500, color: on ? '#3A3A3C' : MT, whiteSpace: 'nowrap' }}>
                    <span style={{ flex: 'none', width: 8, height: 8, borderRadius: '50%', background: sdColour(Math.max(0.25, Math.abs(kk))) }} />{sdl(kk)}{isRule ? ' · rule' : ''}
                  </span>
                  <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, color: on ? '#000000' : K, whiteSpace: 'nowrap' }}>{fmtK(r.K)}</span>
                  <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 500, color: on ? '#3A3A3C' : MT, whiteSpace: 'nowrap' }}>{pk >= 0 ? '↑' : '↓'}{(Math.abs(pk) * 100).toFixed(1)}%</span>
                </button>
              );
            })}
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>Contracts · {put ? 'puts' : 'calls'}</span>
          <div style={{ display: 'grid', gridTemplateColumns: '40px minmax(0,1fr) 40px', alignItems: 'center', height: 48, borderRadius: 14, background: 'rgba(118,118,128,.24)' }}>
            <button type="button" className="bare" onClick={() => setN(n - 1)} aria-label="One fewer" style={{ textAlign: 'center', fontSize: 20, lineHeight: '48px', fontWeight: 500 }}>−</button>
            <input type="text" inputMode="numeric" aria-label={`Contracts, ${put ? 'puts' : 'calls'}`} value={String(n)}
              onChange={(ev) => { const v = ev.target.value.replace(/\D/g, '').slice(0, 3); setN(+v || 0); }}
              style={{ width: '100%', minWidth: 0, border: 'none', background: 'transparent', color: K, textAlign: 'center', fontSize: 17, fontWeight: 600, outline: 'none' }} />
            <button type="button" className="bare" onClick={() => setN(n + 1)} aria-label="One more" style={{ textAlign: 'center', fontSize: 20, lineHeight: '48px', fontWeight: 500 }}>+</button>
          </div>
        </div>
      </div>
      {cv && (cv.sold > 0 || cv.capShares + cv.capOtm > 0) && (
        <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'baseline', gap: '4px 10px', fontSize: 14, lineHeight: '20px' }}>
          <span style={{ fontSize: 12, color: MU }}>Cover</span>
          <span style={{ fontWeight: 600, color: cv.uncovered > 0 ? O : G }}>{cv.uncovered > 0 ? `${cv.uncovered} uncovered` : 'Covered'}</span>
          <span style={{ color: MT }}>
            {cv.sold} calls sold{cv.open && cv.sale ? ` (${cv.open} open, ${cv.sale} new)` : ''}, {cv.byShares + cv.byOtm} covered · {cv.byShares} from shares + {cv.byOtm} OTM calls
          </span>
        </div>
      )}
      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) 110px 140px auto', gap: 20, alignItems: 'center', paddingTop: 12, borderTop: '1px solid rgba(255,255,255,.08)' }}>
        <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{legs.length ? `Sell ${desc} · ${e.label}` : 'Nothing to sell yet: set a count'}</span>
          <span style={{ fontSize: 13, lineHeight: '18px', color: MU }}>
            Editing the {put ? 'put' : 'call'} side{legs.length ? ' · ' + legs.map((l) => `${price(l.p)} a ${l.put ? 'put' : 'call'}`).join(', ') : ''}
          </span>
        </span>
        <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
          <span style={{ fontSize: 12, color: MU }}>Cash today</span>
          <span style={{ fontSize: 17, fontWeight: 600, color: G }}>{mask(money(cash))}</span>
        </span>
        <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
          <span style={{ fontSize: 12, color: MU }}>Net Δ after</span>
          <span style={{ fontSize: 17, fontWeight: 600, color: net != null && net < 0 ? O : K, whiteSpace: 'nowrap' }}>{net == null ? '-' : `${net < 0 ? 'Short' : 'Long'} ${count(net)}`}</span>
        </span>
        <button type="button" className="bare" onClick={tryIt} disabled={!legs.length && !tried}
          style={{ padding: '10px 22px', borderRadius: 999, fontSize: 14, lineHeight: '18px', fontWeight: 600, whiteSpace: 'nowrap', transition: 'background .2s',
            background: tried ? 'rgba(101,196,102,.18)' : 'rgba(118,118,128,.24)', color: tried ? G : K, opacity: legs.length || tried ? 1 : 0.4 }}>{tried ? 'In What if · Undo' : 'Try in What if'}</button>
      </div>
    </div>
    {M.alerts.length > 0 && (
      <div role="status" aria-label="Alerts" style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8 }}>
        <span style={kicker}>Today</span>
        {M.alerts.map((a) => {
          const closed = a.s !== 'touch';
          return (
            <span key={a.k} style={{ display: 'flex', alignItems: 'center', gap: 6, height: 28, padding: '0 12px', borderRadius: 999, fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap',
              background: closed ? K : 'rgba(255,214,10,.12)', boxShadow: closed ? 'none' : 'inset 0 0 0 1px rgba(255,214,10,.55)', color: closed ? '#000000' : '#FFD60A' }}>
              {!closed && <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#FFD60A' }} />}{a.text}
            </span>
          );
        })}
      </div>
    )}
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, minHeight: 27 * 2 + 24, maxWidth: 980 }}>
      <span style={kicker}>The read · {e.long}{M.picked ? '' : ' · the rule’s strikes'}</span>
      <p key={M.read.lead + M.read.rest} className="swp-fade" style={{ margin: 0, fontSize: 19, lineHeight: '27px', letterSpacing: '-.01em', textWrap: 'pretty' }}>
        <span style={{ fontWeight: 600, color: K }}>{M.read.lead}</span> <span style={{ fontWeight: 400, color: 'rgba(245,245,247,.72)' }}>{M.read.rest}</span>
      </p>
    </div>
    <Lanes d={d} M={M} t={t} mask={mask} />
  </>;
}
const fmtK = (K: number) => String(+K.toFixed(2));
