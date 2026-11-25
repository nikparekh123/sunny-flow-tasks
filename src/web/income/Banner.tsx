// The realized income banner on top of the Income tab (handoff-2026-11-24-income "The banner"; SunnyIncome
// banner="bars"): what was kept on calls and puts sold, Weekly | Monthly. The chart is the hero: 12 weeks (or every
// month), each bar calls (#3E6AE1) and puts (#C8946A) stacked, dashed grid lines with a value scale on the right, tap
// a bar to read it (a soft column behind it and its value on top). Everything else is small: the period and its total
// (22 px), the yield in grey, the Calls and Puts amounts beside the switch, on Together each account's part, then By
// ticker, 34 px rows ranked by total with the share average after every premium kept ("avg $").
// A week or month that lost money draws below the baseline in red tones (Overview's Realized P&L); its figures are
// neutral words with a − (handoff 2026-11-25-focus §2: the bars keep their colour, the words never wear one).
// Under 600 px of content it takes the design's narrow sizes (8 weeks, every other label, 140 tall, the top 5 names).
import { useMemo, useState, type CSSProperties } from 'react';
import { money, sgn } from '../lib/format';
import { useWeb } from '../lib/state';
import { useContentWidth } from '../home/blocks/width';
import { barsOf, CC, CC_LOSS, f2, ln, MU, PC, PC_LOSS, scaleOf, W, yieldOf, type Banner as B } from './model';
import { Disc } from './ui';

const ROOM = 20;
const WIDE = { pd: '18px 22px', g: 16, H: 200, bw: 40, gap: 10, AG: 40, xf: 11, top: 8, tg: 'repeat(auto-fill,minmax(220px,1fr))' };
const NARROW = { pd: '16px', g: 14, H: 140, bw: 20, gap: 4, AG: 32, xf: 10, top: 5, tg: 'minmax(0,1fr)' };
const KEY = 'sw-inc-bn';
const saved = (): { vw?: 'w' | 'm'; pick?: Record<string, string> } => { try { return JSON.parse(sessionStorage.getItem(KEY) || '{}') || {}; } catch { return {}; } };
const keep = (v: { vw: 'w' | 'm'; pick: Record<string, string> }) => { try { sessionStorage.setItem(KEY, JSON.stringify(v)); } catch { /* private window */ } };
/** A figure that lost: grey with a − (under 15 px; focus §2.1, §2.2), else the text's own colour and no sign. */
const red = (v: number) => (v < -0.5 ? MU : undefined);
const lost = (v: number, s: string) => (v < -0.5 ? sgn(-1, s) : s);

export function Banner({ b, today, accounts }: { b: B; today: string; accounts: string[] | null }) {
  const { mask } = useWeb();
  const cw = useContentWidth(), nw = cw > 0 && cw < 600, L = nw ? NARROW : WIDE, H = L.H, PH = H - ROOM, AG = L.AG;
  // The picked bar (and so Weekly or Monthly) lasts the session (README §4).
  const [vw, setVwS] = useState<'w' | 'm'>(() => (saved().vw === 'm' ? 'm' : 'w'));
  const [pick, setPickS] = useState<Record<string, string>>(() => saved().pick ?? {});
  const setVw = (v: 'w' | 'm') => { setVwS(v); keep({ vw: v, pick }); };
  const setPick = (f: (p: Record<string, string>) => Record<string, string>) => setPickS((p) => { const n = f(p); keep({ vw, pick: n }); return n; });
  const [all, setAll] = useState(false);
  const { bars, def } = useMemo(() => barsOf(b, vw, today, nw), [b, vw, today, nw]);
  const sc = useMemo(() => scaleOf(bars), [bars]);
  const pi = bars.findIndex((x) => x.k === pick[vw]), si = pi >= 0 ? pi : def;
  const sel = bars[si];
  if (!sel) return null;

  const span = sc.top + sc.bot || 1;
  const y = (v: number) => ROOM + ((sc.top - v) / span) * PH;
  const y0 = y(0);
  const yl = yieldOf(sel.t, b.capital, sel.part, vw);

  // By ticker: what each name realized in the period picked, with its share average. A period at a profit starts with
  // the best name, a period at a loss with the worst (Nik, 24 Nov 2026).
  const rows0 = Object.keys(sel.by).map((t) => { const [c, p] = sel.by[t] ?? [0, 0]; return { t, c, p, tot: c + p, sh: b.shares[t] }; })
    .filter((x) => Math.abs(x.tot) >= 0.5 || Math.abs(x.c) >= 0.5 || Math.abs(x.p) >= 0.5);
  const lossFirst = rows0.reduce((s, x) => s + x.tot, 0) < 0;
  const rows = rows0.sort((a, c) => (lossFirst ? a.tot - c.tot : c.tot - a.tot) || a.t.localeCompare(c.t));
  const shown = all ? rows : rows.slice(0, L.top);
  const parts = accounts && accounts.length > 1 ? accounts.map((nm) => { const v = sel.bk[nm] ?? [0, 0]; return { nm, v: v[0] + v[1] }; }) : null;

  const seg = (k: 'w' | 'm', l: string) => {
    const on = vw === k;
    return (
      <button key={k} type="button" role="radio" aria-checked={on} className="bare" onClick={() => setVw(k)}
        style={{ minWidth: 68, height: 28, padding: '0 10px', borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12,
          fontWeight: 500, color: on ? W : MU, background: on ? 'rgba(255,255,255,.2)' : 'transparent',
          boxShadow: on ? 'inset 0 0 0 .5px rgba(255,255,255,.22),0 2px 8px rgba(0,0,0,.35)' : 'none', transition: 'background .2s,color .2s' }}>{l}</button>
    );
  };
  const sw = (c: string, l: string, v: number) => (
    <span style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
      <span aria-hidden="true" style={{ width: 8, height: 8, borderRadius: 2, background: c }} />{l} <span style={{ color: red(v) }}>{lost(v, mask(money(v)))}</span>
    </span>
  );

  return (
    <section aria-label="Realized income" className="tnum"
      style={{ display: 'flex', flexDirection: 'column', gap: L.g, padding: L.pd, borderRadius: 20, background: 'rgba(255,255,255,.04)', boxShadow: `inset 0 0 0 1px ${ln(0.08)}`, minWidth: 0 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '8px 16px', flexWrap: 'wrap' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <span style={{ display: 'flex', flexWrap: 'wrap', gap: '0 6px', fontSize: 13, lineHeight: '18px', color: MU }}>
            <span style={{ fontWeight: 400, color: W }}>Realized income</span><span>{sel.cap}</span>
          </span>
          <span style={{ display: 'flex', alignItems: 'baseline', flexWrap: 'wrap', gap: '2px 12px' }}>
            <span style={{ fontSize: 22, lineHeight: '28px', fontWeight: 700, letterSpacing: '-.02em', whiteSpace: 'nowrap' }}>{lost(sel.t, mask(money(sel.t)))}</span>
            {yl && (
              <span title={`Yield: premium kept ÷ what the shares cost${sel.part ? '' : `. The yearly pace repeats this ${vw === 'w' ? 'week' : 'month'} all year`}`}
                style={{ fontSize: 13, lineHeight: '18px', color: MU, whiteSpace: 'nowrap' }}>{yl.v} yield · {yl.a}</span>
            )}
            {parts && (
              <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>
                {parts.map((p, i) => <span key={p.nm}>{i ? ' · ' : ''}{p.nm} <span style={{ color: red(p.v) }}>{lost(p.v, mask(money(p.v)))}</span></span>)}
              </span>
            )}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px 16px', flexWrap: 'wrap' }}>
          <span style={{ display: 'flex', gap: 12, fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>
            {sw(sel.c < -0.5 ? CC_LOSS : CC, 'Calls', sel.c)}{sw(sel.p < -0.5 ? PC_LOSS : PC, 'Puts', sel.p)}
          </span>
          <div role="radiogroup" aria-label="Weekly or monthly" style={{ display: 'flex', padding: 2, borderRadius: 999, background: 'rgba(128,128,128,.24)' }}>
            {seg('w', 'Weekly')}{seg('m', 'Monthly')}
          </div>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{ position: 'relative', paddingRight: AG }}>
          {sc.lines.map((v) => (
            <div key={v} aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: y(v), borderTop: `1px dashed ${ln(0.08)}` }}>
              <span style={{ position: 'absolute', right: 0, top: -7, fontSize: 11, lineHeight: '14px', color: MU }}>{v < 0 ? sgn(-1, mask(money(v))) : mask(money(v))}</span>
            </div>
          ))}
          <div aria-hidden="true" style={{ position: 'absolute', left: 0, right: AG, top: y0, borderTop: `1px solid ${ln(0.14)}` }} />
          <div role="group" aria-label={`Realized by ${vw === 'w' ? 'week' : 'month'}, pick one to read it`} style={{ position: 'relative', display: 'flex', gap: L.gap, height: H }}>
            {bars.map((x, i) => {
              const on = i === si, up = Math.max(0, x.c) + Math.max(0, x.p), dn = Math.min(0, x.c) + Math.min(0, x.p);
              const hc = (v: number) => (Math.abs(v) / span) * PH;
              const both = (a: number, c: number) => (a !== 0 && c !== 0 ? 1 : 0);
              const st: CSSProperties = { position: 'absolute', left: '50%', transform: 'translateX(-50%)', width: '100%', maxWidth: L.bw, display: 'flex', overflow: 'hidden' };
              const zero = up < 0.5 && dn > -0.5;
              return (
                <button key={x.k} type="button" className="bare sw-bn-b" aria-pressed={on} onClick={() => setPick((p) => ({ ...p, [vw]: x.k }))}
                  aria-label={mask(`${x.pl}, ${x.t < -0.5 ? 'lost ' : ''}${money(x.t)} realized, calls ${x.c < -0.5 ? 'lost ' : ''}${money(x.c)}, puts ${x.p < -0.5 ? 'lost ' : ''}${money(x.p)}`)}
                  style={{ position: 'relative', flex: '1 1 0', minWidth: 0, height: '100%', borderRadius: 8, background: on ? 'rgba(255,255,255,.08)' : 'transparent', transition: 'background .2s' }}>
                  {on && !zero && (
                    <span style={{ position: 'absolute', left: 0, right: 0, top: Math.max(0, y(up) - 20), textAlign: 'center', fontSize: 12, lineHeight: '14px', fontWeight: 400, whiteSpace: 'nowrap', color: red(x.t) ?? W }}>{lost(x.t, mask(money(x.t)))}</span>
                  )}
                  {zero && <span style={{ ...st, top: y0 - 2, height: 2, borderRadius: 1, background: '#2A2A2A' }} />}
                  {up >= 0.5 && (
                    <span style={{ ...st, top: y(up), height: y0 - y(up), flexDirection: 'column', gap: both(Math.max(0, x.c), Math.max(0, x.p)), borderRadius: '4px 4px 0 0' }}>
                      {x.p > 0 && <span style={{ flex: 'none', height: hc(x.p), background: PC }} />}
                      {x.c > 0 && <span style={{ flex: 'none', height: hc(x.c), background: CC }} />}
                    </span>
                  )}
                  {dn <= -0.5 && (
                    <span style={{ ...st, top: y0 + 1, height: y(dn) - y0, flexDirection: 'column', gap: both(Math.min(0, x.c), Math.min(0, x.p)), borderRadius: '0 0 4px 4px' }}>
                      {x.c < 0 && <span style={{ flex: 'none', height: hc(x.c), background: CC_LOSS }} />}
                      {x.p < 0 && <span style={{ flex: 'none', height: hc(x.p), background: PC_LOSS }} />}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>
        <div aria-hidden="true" style={{ display: 'flex', gap: L.gap, paddingRight: AG }}>
          {bars.map((x, i) => (
            <span key={x.k} style={{ flex: '1 1 0', minWidth: 0, textAlign: 'center', fontSize: L.xf, lineHeight: '14px', fontWeight: 500, color: i === si ? W : MU, whiteSpace: 'nowrap' }}>{nw && i !== si && i % 2 ? '' : x.l}</span>
          ))}
        </div>
      </div>

      {rows.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <div role="list" aria-label="Realized by ticker" style={{ display: 'grid', gridTemplateColumns: L.tg, gap: '0 28px' }}>
            {shown.map((x) => {
              const av = x.sh && x.sh.sh > 0 && x.sh.avg != null ? x.sh.avg : null;
              const pd = x.sh && x.sh.paid != null ? x.sh.paid : null;
              return (
                <div key={x.t} role="listitem" title={av != null ? `Share average after every premium kept${pd != null ? ` · paid $${f2(pd)}` : ''}` : undefined}
                  aria-label={mask(`${x.t}, ${x.tot < -0.5 ? 'lost ' : ''}${money(x.tot)} realized, calls ${money(x.c)}, puts ${money(x.p)}${av != null ? `, share average $${f2(av)}` : ''}`)}
                  style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0, height: 34, boxSizing: 'content-box', borderBottom: `1px solid ${ln(0.06)}`, fontSize: 13, lineHeight: '18px', whiteSpace: 'nowrap',
                    opacity: Math.abs(x.tot) < 0.5 ? 0.5 : 1 }}>
                  <Disc t={x.t} size={18} fs={5} pct={62} />
                  <span style={{ fontWeight: 400 }}>{x.t}</span>
                  <span style={{ marginLeft: 'auto', fontWeight: 400, color: red(x.tot) }}>{lost(x.tot, mask(money(x.tot)))}</span>
                  <span style={{ flex: 'none', minWidth: 76, textAlign: 'right', fontSize: 12, color: MU }}>{av != null ? `avg $${f2(av)}` : ''}</span>
                </div>
              );
            })}
          </div>
          {rows.length > L.top && (
            <button type="button" className="bare sw-bn-m" onClick={() => setAll(!all)} aria-expanded={all}
              style={{ alignSelf: 'flex-start', minHeight: 32, display: 'flex', alignItems: 'center', fontSize: 12, lineHeight: '16px', fontWeight: 400, color: MU }}>
              {all ? 'Fewer' : `All ${rows.length} names`}
            </button>
          )}
        </div>
      )}
      <style>{'.sw .sw-bn-b:hover{opacity:.85}.sw .sw-bn-m:hover{opacity:.75}'}</style>
    </section>
  );
}
