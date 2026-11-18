// Overview §2 · Your positions, by what you hold, both accounts added (SunnyOverview 165; Nik's rule of 11 Nov:
// What you sold = Calls sold, Puts sold; What you own = Shares, Hedges with every call bought, LEAPS too, and every
// put bought). Today | Unrealized picks the figure: Today is each book's Home today split by leg, Unrealized each leg
// against what it cost or what it was sold for. A row opens its legs in the rail's row style: logo, name, what,
// each account's part, and a pill (green made, red lost, grey neither). The design's small line per leg is left
// out: there is no intraday series per leg to draw it from.
import { useRef, useState } from 'react';
import { C, count, money, pct } from '../lib/format';
import { useWeb } from '../lib/state';
import { CHIP, H2, LINE, Logo, cl } from './ui';
import { dayLabel, type Item, type PosRow, type Together } from './together';

type View = 'td' | 'un';
const plural = (n: number, one: string, many: string) => `${count(n)} ${Math.round(n) === 1 ? one : many}`;
/** The pill (dark): green made, red lost, grey neither. */
const pill = (v: number) => (v > 0.5 ? ['#65C466', '#000000'] : v < -0.5 ? ['#FF6961', '#000000'] : ['rgba(118,118,128,.32)', '#F5F5F7']);

function sub(r: PosRow, isT: boolean): string {
  const nm = r.only ? `${r.only} only` : plural(r.names, 'name', 'names');
  if (r.sold) {
    if (!isT) return `of ${money(r.base)} collected`;
    const head = `${plural(r.n, r.k === 'cs' ? 'call' : 'put', r.k === 'cs' ? 'calls' : 'puts')} · ${nm}`;
    if (!(r.base > 0)) return head;
    const f = r.all / r.base;
    return `${head} · ${pct(Math.abs(f) * 100)} ${f < 0 ? 'lost' : 'captured'} so far`;   // kept since each leg was sold
  }
  if (!isT) return `on ${money(r.base)} paid`;
  if (r.k === 'sh') return `${plural(r.n, 'share', 'shares')} · ${nm}`;
  if (r.k === 'hg') {
    return [r.hedgeCalls ? plural(r.hedgeCalls, 'hedge call', 'hedge calls') : '', r.hedgePuts ? plural(r.hedgePuts, 'hedge put', 'hedge puts') : '']
      .filter(Boolean).join(' · ');
  }
  return `${plural(r.n, 'contract', 'contracts')} · ${nm}`;
}

/** What a leg is: "150 puts · Nov 25 · 25 contracts", "Hedge 70 calls · Jan ’28 · 17 contracts", "800 shares". */
function what(i: Item): string {
  if (i.k === 'sh') return plural(i.n, 'share', 'shares');
  return `${i.k === 'hc' || i.k === 'ip' ? 'Hedge ' : ''}${i.label} · ${plural(i.n, 'contract', 'contracts')}`;
}

export function YourPositions({ t }: { t: Together }) {
  const { mask } = useWeb();
  const [vw, setVw] = useState<View>('td');
  const [open, setOpen] = useState<string | null>(null);
  const isT = vw === 'td';
  const fig = (x: { today: number; all: number }) => (isT ? +x.today : +x.all);

  // An open row keeps its order while the numbers tick (biggest first when it opens or the view changes).
  const order = useRef<{ sig: string; keys: string[] }>({ sig: '', keys: [] });
  const ordered = (r: PosRow): Item[] => {
    const sig = r.k + '|' + vw, by = new Map(r.items.map((i) => [i.key, i]));
    const ranked = [...r.items].sort((a, b) => Math.abs(fig(b)) - Math.abs(fig(a))).map((i) => i.key);
    const keys = order.current.sig === sig ? order.current.keys.filter((k) => by.has(k)) : [];
    for (const k of ranked) if (!keys.includes(k)) keys.push(k);
    order.current = { sig, keys };
    return keys.map((k) => by.get(k)!);
  };

  // A book whose figures were built on an earlier day says so.
  const stale = t.names.map((nm, i) => (t.built[i] && t.built[i] !== t.today ? `${nm} as of ${dayLabel(t.built[i])}.` : '')).filter(Boolean).join(' ');
  const note = (isT
    ? 'Each leg against yesterday’s close, both accounts added. A tap shows the names and each account’s part.'
    : 'What you own against what you paid; what you sold against what you collected. Both accounts added.') + (stale ? ' ' + stale : '');

  return (
    <section aria-label="Your positions" style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, paddingBottom: 4 }}>
        <H2>Your positions</H2>
        <div role="radiogroup" aria-label="Today or unrealized"
          style={{ position: 'relative', flex: 'none', display: 'grid', gridTemplateColumns: 'repeat(2,minmax(0,1fr))', width: 196, padding: 2, borderRadius: 999, background: CHIP }}>
          <span aria-hidden="true" className="seg-thumb"
            style={{ position: 'absolute', top: 2, bottom: 2, left: 2, width: 'calc((100% - 4px) / 2)', borderRadius: 999,
              transform: isT ? 'translateX(0%)' : 'translateX(100%)', transition: 'transform .45s cubic-bezier(.34,1.36,.64,1)' }} />
          {([['td', 'Today'], ['un', 'Unrealized']] as [View, string][]).map(([k, l]) => (
            <button key={k} type="button" role="radio" aria-checked={vw === k} className="bare" onClick={() => setVw(k)}
              style={{ position: 'relative', textAlign: 'center', padding: '7px 0', fontSize: 14, lineHeight: '18px',
                fontWeight: vw === k ? 600 : 500, color: vw === k ? C.ink : C.ink2 }}>{l}</button>
          ))}
        </div>
      </div>

      {t.positions.map((g) => (
        <div key={g.k} style={{ display: 'flex', flexDirection: 'column', paddingTop: 10 }}>
          <span style={{ paddingBottom: 6, fontSize: 13, lineHeight: '18px', fontWeight: 600, color: C.ink2 }}>{g.l}</span>
          {g.rows.map((r) => {
            const o = open === r.k, val = fig(r), s = sub(r, isT);
            return (
              <div key={r.k} style={{ display: 'flex', flexDirection: 'column', borderTop: LINE }}>
                <button type="button" className="bare ov-tap" aria-expanded={o} onClick={() => setOpen(o ? null : r.k)}
                  aria-label={mask(`${r.l}, ${isT ? 'today' : 'unrealized'} ${val < -0.5 ? 'down ' : val > 0.5 ? 'up ' : ''}${money(val)}. ${s}. ${o ? 'Hide' : 'Show'} the names`)}
                  style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto 12px', gap: 10, alignItems: 'center', minHeight: 60, padding: '8px 0' }}>
                  <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                    <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 600 }}>{r.l}</span>
                    <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 500, color: C.ink2, textWrap: 'pretty' } as React.CSSProperties}>{mask(s)}</span>
                  </span>
                  <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 700, color: cl(val), whiteSpace: 'nowrap' }}>{mask(money(val))}</span>
                  <svg width="12" height="12" viewBox="0 0 24 24" aria-hidden="true"
                    style={{ flex: 'none', color: C.ink2, transform: o ? 'rotate(90deg)' : 'none', transition: 'transform .25s ease' }}>
                    <path d="M9 5l7 7-7 7" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 2.6, strokeLinecap: 'round', strokeLinejoin: 'round' }} />
                  </svg>
                </button>
                {o && (
                  <div role="list" aria-label={`${r.l} by name`} style={{ display: 'flex', flexDirection: 'column', padding: '0 22px 10px 0' }}>
                    {ordered(r).map((i) => {
                      const tot = fig(i), [pb, pf] = pill(tot);
                      const parts = t.names.map((nm, bi) => ({ nm, p: i.parts?.[bi] ?? null })).filter((x) => x.p);
                      return (
                        <div key={i.key} role="listitem" style={{ display: 'grid', gridTemplateColumns: '28px minmax(0,1fr) auto', gap: 10, alignItems: 'center', padding: '8px 0' }}>
                          <Logo t={i.t} />
                          <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
                            <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{i.name}</span>
                            <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 500, color: C.ink2, textWrap: 'pretty' } as React.CSSProperties}>{what(i)}</span>
                            <span style={{ display: 'flex', flexWrap: 'wrap', gap: '0 8px', fontSize: 12, lineHeight: '16px', fontWeight: 500, color: C.ink2 }}>
                              {parts.map(({ nm, p }) => {
                                const pv = fig(p!);
                                return <span key={nm} style={{ whiteSpace: 'nowrap' }}>{nm} <span style={{ fontWeight: 600, color: cl(pv) }}>{mask(money(pv))}</span></span>;
                              })}
                            </span>
                          </span>
                          <span style={{ minWidth: 68, height: 30, padding: '0 9px', borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center',
                            background: pb, color: pf, fontSize: 14, lineHeight: '18px', fontWeight: 600, whiteSpace: 'nowrap' }}>{mask(money(tot))}</span>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      ))}
      <span style={{ paddingTop: 8, borderTop: LINE, fontSize: 12, lineHeight: '16px', fontWeight: 500, color: C.ink2, textWrap: 'pretty' } as React.CSSProperties}>{note}</span>
    </section>
  );
}
