// Overview §4 · Realized P&L, both accounts (handoff 2026-11-18 §4.1, SunnyOverview pnl="col"): this month and the
// year with each account's part; By month as vertical bars stacked by account (Sunny solid green, Nicolay the lighter
// green; bar 62% of its column, at most 48 px, radius 6 6 3 3, chart 132 tall, scale the largest month × 1.02),
// the total above each bar and the month under it, a dashed least-squares trend through the totals (the server's
// fit), a tap reads one month. A month that lost money draws down from the baseline in red tones, never a minus
// sign. Dividends sit on their own line, never added in.
import { useState } from 'react';
import { C, arrow, money } from '../lib/format';
import { useWeb } from '../lib/state';
import { H2, LINE, cl } from './ui';
import { dayLabel, dom, monthDay, type Month, type Together } from './together';

const H = 132;
/** Each account's bar colour: the first solid, the next lighter; green made, red lost. */
const tint = (i: number, v: number) => (v >= 0 ? (i ? 'rgba(101,196,102,.42)' : '#65C466') : (i ? 'rgba(255,105,97,.42)' : '#FF6961'));

export function RealizedPL({ t }: { t: Together }) {
  const { mask } = useWeb();
  const R = t.realized, names = t.names;
  const months: Month[] = Array.isArray(R?.byMonth) ? R.byMonth : [];
  const [pm, setPm] = useState<string | null>(null);
  if (!R) return null;

  const add = (a: (number | null)[]) => a.reduce<number>((s, x) => s + (x == null ? 0 : +x), 0);
  const parts = (per: (number | null)[]) => names.map((nm, i) => ({ nm, v: per?.[i] ?? null })).filter((x) => x.v != null) as { nm: string; v: number }[];
  const rows = ([['m', 'This month', R.month?.per ?? []], ['y', 'Year to date', R.year?.per ?? []]] as [string, string, (number | null)[]][]);

  // ── By month: the scale takes the stacks up and down, and the trend, so nothing leaves the chart ──
  const stacks = months.map((m) => {
    let up = 0, dn = 0;
    (m.per ?? []).forEach((v) => { if (v != null) { if (v > 0) up += v; else dn += v; } });
    return { up, dn };
  });
  const fit = R.trend?.fit ?? [];
  let hi = Math.max(0, ...stacks.map((s) => s.up)), lo = Math.min(0, ...stacks.map((s) => s.dn));
  if (fit.length === months.length && fit.length) { hi = Math.max(hi, ...fit); if (lo < 0) lo = Math.min(lo, ...fit); }
  let hiS = hi * 1.02;
  const loS = lo * 1.02;
  if (hiS === 0 && loS === 0) hiS = 1;
  const span = hiS - loS;
  const Y = (v: number) => ((hiS - Math.max(loS, Math.min(hiS, v))) / span) * H;
  const y0 = Y(0), px = (v: number) => (Math.abs(v) / span) * H;
  const nM = months.length;

  const running = months.find((m) => m.part);
  const def = (running ?? months[nM - 1])?.m;
  const sel = months.find((m) => m.m === pm) ?? months.find((m) => m.m === def) ?? null;
  const toDay = monthDay(t.today);
  const lab = (m: Month) => m.l + (m.part ? ` to ${toDay}` : '');

  // "Trend ▼ $14K a month since September, both accounts. Nicolay from Oct 29; November runs to Wed Nov 18."
  const tr = R.trend;
  const first = months[0] ? `${months[0].m}-01` : '';
  const later = (R.starts ?? []).filter((s) => first && s.start > first).map((s) => `${s.name} from ${s.md}`).join(', ');
  const tail = [later, running ? `${running.l} runs to ${dayLabel(t.today)}` : ''].filter(Boolean).join('; ');
  const trWords = tr ? ` since ${tr.since}, both accounts.${tail ? ' ' + tail + '.' : ''}` : '';

  const divs = names.map((nm, i) => ({ nm, v: +(R.dividends?.year?.[i] ?? 0) })).filter((x) => Math.abs(x.v) >= 0.5);
  const divTot = divs.reduce((s, x) => s + x.v, 0);

  const ariaOf = (m: Month) => {
    const p = names.map((nm, i) => (m.per?.[i] == null ? `${nm} not yet started` : `${nm} ${m.per[i]! < -0.5 ? 'lost ' : ''}${money(m.per[i])}`)).join(', ');
    return mask(`${lab(m)}: ${m.total < -0.5 ? 'lost ' : ''}${money(m.total)}, ${p}`);
  };

  return (
    <section aria-label="Realized P&L" style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, paddingBottom: 8 }}>
        <H2>Realized P&amp;L</H2>
        <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 500, color: C.ink2 }}>What closed or expired, both accounts</span>
      </div>

      {rows.map(([k, l, per]) => {
        const tot = add(per);
        return (
          <div key={k} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: '2px 12px', alignItems: 'center', minHeight: 60, padding: '8px 0', borderTop: LINE }}>
            <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 500 }}>{l}</span>
            <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 700, color: cl(tot), textAlign: 'right' }}>{mask(money(tot))}</span>
            <span style={{ gridColumn: '1 / -1', display: 'flex', justifyContent: 'flex-end', flexWrap: 'wrap', gap: '0 12px', fontSize: 12, lineHeight: '16px', fontWeight: 500, color: C.ink2 }}>
              {parts(per).map((p) => <span key={p.nm}>{p.nm} <span style={{ fontWeight: 600, color: cl(p.v) }}>{mask(money(p.v))}</span></span>)}
            </span>
          </div>
        );
      })}

      {nM > 0 && sel && (
        <div role="group" aria-label={mask(`Realized P&L by month, both accounts.${tr ? ` Trend ${tr.slope < 0 ? 'down' : 'up'} ${money(tr.slope)} a month.` : ''} Tap a month for each account.`)}
          style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '14px 0 6px', borderTop: LINE }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '8px 12px', flexWrap: 'wrap' }}>
            <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>By month</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 12, lineHeight: '16px', fontWeight: 500, color: C.ink2 }}>
              {names.map((nm, i) => (
                <span key={nm} style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                  <span style={{ width: 8, height: 8, borderRadius: 2, background: tint(i, 1) }} />{nm}
                </span>
              ))}
              {tr && (
                <span style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                  <svg width="14" height="4" viewBox="0 0 14 4" aria-hidden="true"><line x1="0" y1="2" x2="14" y2="2" style={{ stroke: C.ink, strokeOpacity: 0.6, strokeWidth: 1.5, strokeDasharray: '3 2' }} /></svg>Trend
                </span>
              )}
            </span>
          </div>

          <div aria-hidden="true" style={{ display: 'grid', gridTemplateColumns: `repeat(${nM},minmax(0,1fr))`, marginBottom: -4 }}>
            {months.map((m) => {
              const on = m.m === sel.m;
              return <span key={m.m} style={{ textAlign: 'center', fontSize: 12, lineHeight: '16px', fontWeight: on ? 700 : 500, color: on ? cl(m.total) : C.ink2, whiteSpace: 'nowrap' }}>{mask(money(m.total))}</span>;
            })}
          </div>

          <div style={{ position: 'relative', height: H }}>
            <svg viewBox={`0 0 ${nM * 100} ${H}`} preserveAspectRatio="none" aria-hidden="true"
              style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible', pointerEvents: 'none' }}>
              <line x1="0" x2={nM * 100} y1={y0.toFixed(1)} y2={y0.toFixed(1)} style={{ stroke: 'rgba(255,255,255,.14)', strokeWidth: 1, vectorEffect: 'non-scaling-stroke' }} />
            </svg>
            <div style={{ position: 'absolute', inset: 0, display: 'grid', gridTemplateColumns: `repeat(${nM},minmax(0,1fr))` }}>
              {months.map((m, mi) => {
                const on = m.m === sel.m, st = stacks[mi], per = m.per ?? [];
                const bar = { position: 'absolute' as const, left: '50%', transform: 'translateX(-50%)', width: '62%', maxWidth: 48, display: 'flex',
                  overflow: 'hidden', opacity: on ? 1 : 0.55, transition: 'opacity .25s ease' };
                return (
                  <button key={m.m} type="button" className="bare" aria-pressed={on} aria-label={ariaOf(m)} onClick={() => setPm(m.m)}
                    style={{ position: 'relative', height: '100%', display: 'block' }}>
                    {st.up > 0 && (
                      <span style={{ ...bar, top: Y(st.up), height: y0 - Y(st.up), flexDirection: 'column-reverse', borderRadius: '6px 6px 3px 3px' }}>
                        {per.map((v, i) => (v != null && v > 0 ? <span key={i} style={{ flex: 'none', height: px(v), background: tint(i, v) }} /> : null))}
                      </span>
                    )}
                    {st.dn < 0 && (
                      <span style={{ ...bar, top: y0, height: Y(st.dn) - y0, flexDirection: 'column', borderRadius: '3px 3px 6px 6px' }}>
                        {per.map((v, i) => (v != null && v < 0 ? <span key={i} style={{ flex: 'none', height: px(v), background: tint(i, v) }} /> : null))}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
            {tr && fit.length === nM && nM > 1 && (
              <svg viewBox={`0 0 ${nM * 100} ${H}`} preserveAspectRatio="none" aria-hidden="true"
                style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible', pointerEvents: 'none' }}>
                <path d={'M' + fit.map((f, i) => `${((i + 0.5) * 100).toFixed(1)} ${Y(f).toFixed(1)}`).join(' L')}
                  style={{ fill: 'none', stroke: C.ink, strokeOpacity: 0.6, strokeWidth: 1.5, strokeDasharray: '4 4', strokeLinecap: 'round', vectorEffect: 'non-scaling-stroke' }} />
              </svg>
            )}
          </div>

          <div aria-hidden="true" style={{ display: 'grid', gridTemplateColumns: `repeat(${nM},minmax(0,1fr))`, marginTop: -4 }}>
            {months.map((m) => {
              const on = m.m === sel.m;
              return (
                <span key={m.m} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', fontSize: 12, lineHeight: '16px', fontWeight: on ? 700 : 500, color: on ? C.ink : C.ink2 }}>
                  {m.s}
                  {m.part && <span style={{ fontSize: 11, lineHeight: '14px', fontWeight: 500, color: C.ink2 }}>to {dom(t.today)}</span>}
                </span>
              );
            })}
          </div>

          <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'baseline', gap: '4px 12px', paddingTop: 10, borderTop: LINE }}>
            <span style={{ fontSize: 14, lineHeight: '20px', fontWeight: 600, whiteSpace: 'nowrap' }}>
              {lab(sel)} <span style={{ color: cl(sel.total) }}>{mask(money(sel.total))}</span>
            </span>
            <span style={{ display: 'flex', flexWrap: 'wrap', gap: '0 12px', fontSize: 13, lineHeight: '18px', fontWeight: 500, color: C.ink2, whiteSpace: 'nowrap' }}>
              {names.map((nm, i) => {
                const v = sel.per?.[i];
                return (
                  <span key={nm}>{nm} {v == null
                    ? <span style={{ fontWeight: 600, color: C.ink2 }}>not yet</span>
                    : <span style={{ fontWeight: 600, color: cl(v) }}>{mask(money(v))}</span>}</span>
                );
              })}
            </span>
          </div>
          {tr && (
            <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 500, color: C.ink2, textWrap: 'pretty' } as React.CSSProperties}>
              <span style={{ fontWeight: 600, color: cl(tr.slope) }}>{mask(`Trend ${arrow(tr.slope)} ${money(tr.slope)} a month`)}</span>{trWords}
            </span>
          )}
        </div>
      )}

      {divs.length > 0 && (
        <span style={{ paddingTop: 8, borderTop: LINE, fontSize: 13, lineHeight: '18px', fontWeight: 500, color: C.ink2, textWrap: 'pretty' } as React.CSSProperties}>
          {mask(`Dividends, kept apart: ${money(divTot)} this year · ${divs.map((d) => `${d.nm} ${money(d.v)}`).join(' · ')}`)}
        </span>
      )}
    </section>
  );
}
