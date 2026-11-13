// Sold, in SD (handoff 2026-11-13-positions §3.3; Web Dark v2 `d.sd153`): every sold option leg on the account on
// screen, on one SD axis, one row per leg. The rows come from Home's legs (brief_inputs: strike, count, sold at, the
// mark, each leg's own IV), already loaded, so the card opens at once. The hollow dot (SD when sold) is the fill's,
// from each name's sunny-sd reply (`sold[i].z0`), read only once the card is opened; a leg without one has no hollow
// dot (never back-solved). No buy-back or roll hints (Nik removed them).
import type { J } from '../lib/data';
import { ny } from '../lib/clock';
import { tradingDays, type SoldIn, type SoldRow, type Tone } from '../../../supabase/functions/_shared/positions-engine.ts';
import { expLabel, fk } from './model';
import type { SdReply } from './intel';
import { Chevron, Fold, GLASS, MT, MU, QU, R, O, K, SOFT, tnum } from './ui';

const TONE: Record<Tone, string> = { red: R, orange: O, quiet: MT };
/** The days the market is shut, from Home's calendar. */
export const closedDays = (calendar: J): Set<string> =>
  new Set(((Array.isArray(calendar) ? calendar : []) as J[]).filter((d) => d?.kind === 'closed' && d?.date).map((d) => String(d.date)));

/** Every sold leg of the book, from Home's payload; z0 from the names' sunny-sd replies when they are in. */
export function soldLegs(payload: J, sd: Map<string, SdReply | undefined>): SoldIn[] {
  const inp = payload?.brief_inputs;
  if (!inp?.names) return [];
  const n0 = ny(), closed = closedDays(payload?.calendar), gone = Math.max(0, (Date.now() - Date.parse(inp.built_at)) / 864e5);
  const out: SoldIn[] = [];
  for (const n of inp.names as J[]) {
    const S = Number(n.S0);
    if (!(S > 0)) continue;
    const reply = sd.get(String(n.t));
    for (const l of (n.legs ?? []) as J[]) {
      if (l.ty === 'S' || !(Number(l.q) < 0) || !l.ex) continue;
      const put = l.ty === 'P', K = Number(l.K), ex = String(l.ex), cd = Math.max(0, Number(l.days) - gone);
      const iv = Number(l.iv) > 0.03 ? Number(l.iv) : Number(n.iv) || 0;
      const z0 = reply?.sold?.find((s) => s.put === put && Math.abs(s.K - K) < 1e-6 && s.ex === ex)?.z0 ?? null;
      out.push({ t: String(n.t), S, put, K, n: -Number(l.q), ex, exLabel: expLabel(ex, Math.round(cd)), entry: l.at != null ? Number(l.at) : null,
        mark: l.now != null ? Number(l.now) : null, iv, td: tradingDays(n0.date, ex, closed, n0.mins), cd, z0 });
    }
  }
  return out;
}

/** The closed box at the strip's right end: "Sold, in SD", how many sit within 0.5 SD, a chevron. */
export function SoldCapsule({ rows, open, toggle }: { rows: SoldRow[]; open: boolean; toggle: () => void }) {
  if (!rows.length) return null;
  const hot = rows.filter((r) => r.itm || r.a < 0.5).length;
  const cap = hot ? `${hot} within 0.5 SD` : `${rows.length} sold, all past 0.5 SD`;
  return (
    <button type="button" className="bare" onClick={toggle} aria-expanded={open} aria-label={`Sold, in SD, ${cap}${open ? ', close' : ', open'}`}
      style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 12, minHeight: 52, padding: '8px 14px 8px 18px', borderRadius: 18, ...GLASS,
        ...(open ? { background: 'rgba(255,255,255,.14)' } : {}), transition: 'background .2s' }}>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
        <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>Sold, in SD</span>
        <span style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, lineHeight: '16px', fontWeight: 600, color: hot ? R : MU, whiteSpace: 'nowrap' }}>
          {hot > 0 && <span style={{ flex: 'none', width: 6, height: 6, borderRadius: '50%', background: R }} />}{cap}
        </span>
      </span>
      <Chevron open={open} />
    </button>
  );
}

const COLS = '140px minmax(0,1fr) 124px 124px 100px';
const AX: [number, string][] = [[-2, '2 SD'], [-1, '1 SD'], [0, 'Today'], [1, '1 SD'], [2, '2 SD']];
const xp = (z: number) => `${((0.5 + z / 2.2 / 2) * 100).toFixed(2)}%`;
const pc = (x: number) => `${(x * 100).toFixed(2)}%`;

/** The open card: one row per sold leg, in the money first, then SD now, nearest first. A tap opens that name with
    Intelligence on that expiry. */
export function SoldCard({ rows, within, inTheMoney, open, close, onPick }:
  { rows: SoldRow[]; within: number; inTheMoney: number; open: boolean; close: () => void; onPick: (t: string, ex: string) => void }) {
  if (!rows.length) return null;
  const sum = `${rows.length} sold · ${within ? `${within} within 0.5 SD` : 'none within 0.5 SD'} · ${inTheMoney ? `${inTheMoney} in the money` : 'none in the money'}`;
  return (
    <Fold open={open}>
      <div role="region" aria-label="Sold, in SD" style={{ padding: '22px 24px', borderRadius: 24, ...SOFT, display: 'flex', flexDirection: 'column', gap: 14, ...tnum }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 16, flexWrap: 'wrap' }}>
          <span style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span style={{ fontSize: 20, lineHeight: '26px', fontWeight: 700 }}>Sold, in SD</span>
            <span style={{ fontSize: 13, lineHeight: '18px', color: MU }}>Every sold leg from today’s price. The dot is the strike now, the hollow dot when sold, the tick its breakeven.</span>
          </span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{sum}</span>
            <button type="button" className="bare" onClick={close} aria-expanded={open} style={{ fontSize: 14, fontWeight: 600, color: K, padding: '6px 2px' }}>Close</button>
          </span>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: COLS, gap: 16, alignItems: 'end', fontSize: 12, lineHeight: '16px', color: MU }}>
          <span>Leg</span>
          <span style={{ position: 'relative', display: 'block', height: 34 }}>
            <span style={{ position: 'absolute', top: 0, left: 0, fontWeight: 600, color: MT }}>← puts</span>
            <span style={{ position: 'absolute', top: 0, right: 0, fontWeight: 600, color: MT }}>calls →</span>
            {AX.map(([z, l]) => <span key={z} style={{ position: 'absolute', top: 18, left: xp(z), transform: 'translateX(-50%)', whiteSpace: 'nowrap' }}>{l}</span>)}
          </span>
          <span>Strike · sold → now</span><span>Sold at → now</span><span>Breakeven</span>
        </div>
        <div style={{ position: 'relative', display: 'flex', flexDirection: 'column', borderTop: '1px solid rgba(255,255,255,.08)' }}>
          <span aria-hidden="true" style={{ position: 'absolute', top: 0, bottom: 0, left: 156, right: 396, pointerEvents: 'none' }}>
            {[2, 1.5, 1, 0.5].map((k) => <span key={k} style={{ position: 'absolute', top: 0, bottom: 0, left: xp(-k), width: `${((k / 2.2) * 100).toFixed(2)}%`, background: 'rgba(128,128,220,.06)' }} />)}
            <span style={{ position: 'absolute', top: 0, bottom: 0, left: '50%', borderLeft: '1.5px solid rgba(245,245,247,.7)' }} />
          </span>
          {rows.map((r) => <SoldRowView key={r.key} r={r} onPick={onPick} />)}
        </div>
        <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>
          Red under 0.5 SD, orange 0.5 to 1 SD, quiet past 1 SD, filled red in the money · the hollow dot is where the strike sat when sold · breakeven shows under 0.5 SD or in the money · a tap opens the name
        </span>
      </div>
    </Fold>
  );
}

function SoldRowView({ r, onPick }: { r: SoldRow; onPick: (t: string, ex: string) => void }) {
  const c = TONE[r.tone], lc = r.tone === 'quiet' ? 'rgba(174,174,178,.55)' : c;
  const what = `${fk(r.K)} ${r.put ? 'puts' : 'calls'} · ${r.exLabel} · ${r.n}`;
  const sdNow = `${r.a.toFixed(2)} SD${r.itm ? ' in' : ''}`;
  const kept = r.kept == null ? null : r.kept >= 0 ? `${Math.round(r.kept * 100)}% kept` : `${Math.round(-r.kept * 100)}% lost`;
  const aria = `${r.t} ${fk(r.K)} ${r.put ? 'puts' : 'calls'} ${r.exLabel}, ${r.a0 != null ? `sold ${r.a0.toFixed(2)} SD out, ` : ''}now ${r.a.toFixed(2)} SD ${r.itm ? 'in the money' : 'out'}${r.showBE && r.be != null ? `, breakeven ${r.be.toFixed(2)}` : ''}, opens Intelligence`;
  return (
    <button type="button" className="bare swp-row" onClick={() => onPick(r.t, r.ex)} aria-label={aria}
      style={{ position: 'relative', display: 'grid', gridTemplateColumns: COLS, gap: 16, alignItems: 'center', minHeight: 56, borderBottom: '1px solid rgba(255,255,255,.06)' }}>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
        <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{r.t}</span>
        <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{what}</span>
      </span>
      <span aria-hidden="true" style={{ position: 'relative', display: 'block', height: 28 }}>
        {r.x0 != null && <>
          <span style={{ position: 'absolute', top: 13, height: 0, left: pc(Math.min(r.x0, r.x)), width: pc(Math.abs(r.x - r.x0)), borderTop: '1.5px dotted rgba(245,245,247,.35)' }} />
          <span style={{ position: 'absolute', top: 9, width: 10, height: 10, marginLeft: -5, left: pc(r.x0), borderRadius: '50%', border: '1.5px solid rgba(245,245,247,.4)' }} />
        </>}
        {r.xb != null && <>
          <span style={{ position: 'absolute', top: 13, height: 2, left: pc(Math.min(r.x, r.xb)), width: pc(Math.abs(r.x - r.xb)), background: lc, opacity: 0.5 }} />
          <span style={{ position: 'absolute', top: 6, height: 16, width: 2, marginLeft: -1, left: pc(r.xb), borderRadius: 1, background: lc }} />
        </>}
        <span style={{ position: 'absolute', top: 8, width: 12, height: 12, marginLeft: -6, left: pc(r.x), borderRadius: '50%', border: `2px solid ${c}`, background: r.itm ? R : '#0B0D0C' }} />
      </span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
        <span style={{ fontSize: 14, lineHeight: '20px', fontWeight: 600, whiteSpace: 'nowrap' }}>
          {r.a0 != null && <><span style={{ color: QU, fontWeight: 500 }}>{r.a0.toFixed(2)}</span> <span style={{ color: r.closer ? R : '#65C466' }}>→</span> </>}
          <span style={{ color: c }}>{sdNow}</span>
        </span>
        <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>Δ {r.delta.toFixed(2).replace(/^0/, '')}</span>
      </span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
        <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, whiteSpace: 'nowrap' }}>
          {r.entry != null ? `$${r.entry.toFixed(2)}` : '-'} <span style={{ color: QU, fontWeight: 400 }}>→</span> {r.mark != null ? `$${r.mark.toFixed(2)}` : '-'}
        </span>
        <span style={{ fontSize: 12, lineHeight: '16px', whiteSpace: 'nowrap' }}>
          {kept && <span style={{ color: (r.kept ?? 0) >= 0 ? '#65C466' : R }}>{kept}</span>}<span style={{ color: MU }}>{kept ? ' · ' : ''}× {r.n}</span>
        </span>
      </span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
        {r.showBE && r.be != null ? <>
          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, color: R }}>BE {r.be.toFixed(2)}</span>
          <span style={{ fontSize: 12, lineHeight: '16px', color: R }}>{r.past ? 'past it' : `${Math.abs(r.zb ?? 0).toFixed(2)} SD away`}</span>
        </> : <span style={{ fontSize: 15, lineHeight: '20px', color: QU }}>-</span>}
      </span>
    </button>
  );
}
