// Income's shared pieces (SunnyIncome.dc.html): the logo disc, the rung row (README §1.2, `rung` need | line), the
// delta line and a name's small calendar. Dark only, as the rest of the web.
import { useEffect, useState, type CSSProperties, type ReactNode } from 'react';
import { GRN, ln, MU, ONW, QT, RED, TRK, W, type Cell, type Flip, type Line } from './model';

/** A white disc with the company's logo at 60% (public/logos/TICKER.png); the ticker in the circle when there is no
    logo file. `ring` is an inset shadow, so a dot pinned to the disc never moves. */
export function Disc({ t, size, fs, ring, pct = 60, style, children }: { t: string; size: number; fs: number; ring?: string; pct?: number; style?: CSSProperties; children?: ReactNode }) {
  const [bad, setBad] = useState(false);
  useEffect(() => setBad(false), [t]);
  return (
    <span aria-hidden="true" style={{ position: 'relative', flex: 'none', width: size, height: size, boxSizing: 'border-box', borderRadius: '50%', background: '#FFFFFF',
      boxShadow: ring, display: 'flex', alignItems: 'center', justifyContent: 'center', ...style }}>
      {bad
        ? <span style={{ fontSize: fs, lineHeight: 1, fontWeight: 800, color: '#000000' }}>{t}</span>
        : <img src={`/logos/${encodeURIComponent(t)}.png`} alt="" draggable={false} onError={() => setBad(true)}
            style={{ width: `${pct}%`, height: `${pct}%`, objectFit: 'contain', pointerEvents: 'none' }} />}
      {children}
    </span>
  );
}

/** One rung, one row: the big kept % (64 px column, 52 narrow), then the title with its date and the action on one
    line (the action wraps under it when narrow), and the grey line when there is something to do. */
export function RungRow({ x, narrow }: { x: Line; narrow: boolean }) {
  return (
    <div role="listitem" aria-label={x.aria} className="tnum"
      style={{ display: 'grid', gridTemplateColumns: `${narrow ? 52 : 64}px minmax(0,1fr)`, gap: `0 ${narrow ? 12 : 24}px`, alignItems: 'center', padding: '10px 0', borderTop: `1px solid ${ln(0.06)}` }}>
      <span style={{ fontSize: narrow ? 22 : 26, lineHeight: 1.05, fontWeight: 800, letterSpacing: '-.03em', color: x.bigC, whiteSpace: 'nowrap' }}>{x.big}</span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
        <span style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'baseline', justifyContent: 'space-between', gap: '2px 12px' }}>
          <span style={{ fontSize: narrow ? 14 : 16, lineHeight: narrow ? '19px' : '22px', fontWeight: 600, color: x.titleC }}>
            {x.title}<span style={{ fontWeight: 400, color: MU }}> · {x.date}</span>
          </span>
          {x.act && <span style={{ fontSize: narrow ? 13 : 14, lineHeight: narrow ? '18px' : '21px', fontWeight: 600, color: x.actC, textWrap: 'pretty' } as CSSProperties}>{x.act}</span>}
        </span>
        {x.grey && <span style={{ fontSize: 12, lineHeight: '16px', color: MU, textWrap: 'pretty' } as CSSProperties}>{x.grey}</span>}
      </span>
    </div>
  );
}

/** The delta line's body: the big ↑% (grey, red inside 3%), then the plain words and one grey line of why. */
export function FlipBody({ f, size }: { f: Flip; size: number }) {
  return (
    <span style={{ display: 'grid', gridTemplateColumns: 'auto minmax(0,1fr)', gap: '2px 14px', alignItems: 'center' }}>
      <span className="tnum" style={{ fontSize: size, lineHeight: 1.1, fontWeight: 700, letterSpacing: '-.02em', color: f.bigC, whiteSpace: 'nowrap' }}>{f.big}</span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
        <span className="tnum" style={{ fontSize: 14, lineHeight: '19px', fontWeight: 500, textWrap: 'pretty' } as CSSProperties}>{f.a}</span>
        {f.b ? <span style={{ fontSize: 12, lineHeight: '16px', color: MU, textWrap: 'pretty' } as CSSProperties}>{f.b}</span> : null}
      </span>
    </span>
  );
}

const CHIP: Record<string, [string, string]> = { itm: [RED, ONW], roll: [GRN, ONW], run: [TRK, W], next: ['transparent', MU] };
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const md = (d: string) => { const [, m, dd] = d.split('-').map(Number); return `${MO[m - 1]} ${dd}`; };

/** A name's calendar (Nik: keep it as it is): Mon to Fri from this week, today white, each expiry day a chip a side
    ("72 calls", "30 puts": grey running, green ready to roll, red in the money), the day the next roll goes to
    dashed with "next", past days (and market holidays) faded. */
export function Calendar({ t, cal }: { t: string; cal: Cell[] }) {
  const said = cal.flatMap((c) => {
    const real = c.chips.filter((h) => h.k !== 'n');
    if (real.length) return [`${md(c.d)}: ${real.map((h) => h.t + (h.tone === 'itm' ? ' in the money' : h.tone === 'roll' ? ' ready to roll' : '')).join(' and ')}`];
    if (c.chips.some((h) => h.k === 'n')) return [`${md(c.d)}: the next one`];
    return [];
  });
  const today = cal.find((c) => c.today);
  const aria = `${t} calendar: ${said.length ? said.join('; ') : 'nothing sold'}.${today ? ` Today is ${md(today.d)}.` : ''}`;
  return (
    <div role="img" aria-label={aria} style={{ display: 'flex', flexDirection: 'column', gap: 4, maxWidth: 380, padding: '2px 0' }}>
      <div aria-hidden="true" style={{ display: 'grid', gridTemplateColumns: 'repeat(5,minmax(0,1fr))', gap: 4 }}>
        {['M', 'T', 'W', 'T', 'F'].map((l, i) => <span key={i} style={{ paddingLeft: 5, fontSize: 11, lineHeight: '14px', fontWeight: 600, color: MU }}>{l}</span>)}
      </div>
      <div aria-hidden="true" style={{ display: 'grid', gridTemplateColumns: 'repeat(5,minmax(0,1fr))', gap: 4 }}>
        {cal.map((c) => {
          const nx = c.chips.length > 0 && c.chips.every((h) => h.k === 'n');
          const has = c.chips.length > 0 && !nx;
          return (
            <div key={c.d} title={c.closed ? 'Market closed' : undefined}
              style={{ boxSizing: 'border-box', minHeight: 54, padding: 4, borderRadius: 8, background: has ? ln(0.06) : ln(0.025),
                border: nx ? `1px dashed ${ln(0.35)}` : '1px solid transparent', opacity: c.past || c.closed ? 0.45 : 1,
                display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 3, minWidth: 0 }}>
              <span className="tnum" style={{ minWidth: 18, height: 18, padding: '0 5px', boxSizing: 'border-box', borderRadius: 9, background: c.today ? W : 'transparent',
                fontSize: 11, lineHeight: '18px', fontWeight: c.today ? 700 : 500, color: c.today ? ONW : c.past ? MU : QT, textAlign: 'center', whiteSpace: 'nowrap' }}>{c.lbl}</span>
              {c.chips.map((h) => {
                const [b, f] = CHIP[h.tone] ?? CHIP.run;
                return (
                  <span key={h.k} className="tnum" style={{ maxWidth: '100%', boxSizing: 'border-box', height: 17, padding: '0 5px', borderRadius: 5, background: b,
                    fontSize: 11, lineHeight: '17px', fontWeight: 700, color: f, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{h.t}</span>
                );
              })}
            </div>
          );
        })}
      </div>
    </div>
  );
}
