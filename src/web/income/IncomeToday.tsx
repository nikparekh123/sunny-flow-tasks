// Income today (handoff 2026-11-24 §1.3; SunnyIncome part="today" rung="need"): only what needs you. The header
// ("Income today", "2 need you" in ink, "All quiet" grey) over the marks' time, Every rung › to the Income tab; the
// delta line for each name that sells on several Fridays; then In the money and Ready to roll, a row a rung, a red or
// green dot before each one's % (handoff 2026-11-25-focus §2.3, no colour on the words); the rest run on their own
// behind one grey line.
// Home's right rail draws it narrow (from 960 px of content); under that it sits in the main column, wide.
import { useMemo, type CSSProperties } from 'react';
import { useNavigate } from 'react-router-dom';
import type { J } from '../lib/data';
import { marksWords } from '../lib/clock';
import { Dot, label } from '../lib/focus';
import { wordOf } from '../lib/format';
import { flipOf, ln, MU, readIncome, todayGroups, lineOf, type IncName } from './model';
import { FlipBody, RungRow } from './ui';

const CARD: CSSProperties = { boxSizing: 'border-box', display: 'flex', flexDirection: 'column', background: 'rgba(255,255,255,.04)', boxShadow: `inset 0 0 0 1px ${ln(0.08)}`, minWidth: 0 };

export function IncomeToday({ payload, narrow }: { payload: J; narrow: boolean }) {
  const nav = useNavigate();
  const inc = useMemo(() => readIncome(payload), [payload]);
  const g = useMemo(() => (inc ? todayGroups(inc) : null), [inc]);
  const flips = useMemo(() => (inc ? inc.names.map((n: IncName) => ({ t: n.t, f: flipOf(n) })).filter((x) => x.f) : []), [inc]);
  if (!inc || !g) return null;
  // Under the header only the marks' time (README §1.3; no how-to line on the face, Nik 24 Nov 2026).
  const sub = marksWords(payload);
  // One width for every row's big %, from the widest one in the card, so the titles line up (a signed −901% is
  // five characters; Nik 25 Nov: the rows did not line up).
  const fs = narrow ? 22 : 26, base = narrow ? 52 : 64;
  const col = Math.max(base, Math.ceil(Math.max(0, ...g.groups.flatMap((gr) => gr.rows.map((r) => lineOf(r, true).big.length))) * fs * 0.7));
  return (
    <section aria-label="Sundial" className="tnum"
      style={{ ...CARD, gap: narrow ? 10 : 14, padding: narrow ? '16px 16px 4px' : '20px 22px 10px', borderRadius: narrow ? 22 : 20 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '12px 20px', flexWrap: 'wrap' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 3, flex: `1 1 ${narrow ? 160 : 360}px`, minWidth: 0 }}>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' }}>
            <span style={{ fontSize: narrow ? 17 : 20, lineHeight: narrow ? '22px' : '26px', fontWeight: narrow ? 500 : 700, letterSpacing: '-.01em' }}>Sundial</span>
            <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 500, color: wordOf(g.needC, 15) }}>{g.needT}</span>
          </span>
          {sub && <span style={{ fontSize: 13, lineHeight: '18px', color: MU, textWrap: 'pretty' } as CSSProperties}>{sub}</span>}
        </div>
        <button type="button" className="bare sw-inc-open" onClick={() => { nav('/sundial'); }}
          style={{ flex: 'none', height: 34, padding: '0 14px', borderRadius: 999, boxShadow: `inset 0 0 0 1px ${ln(0.16)}`, fontSize: 13, lineHeight: '34px', fontWeight: 400, whiteSpace: 'nowrap' }}>
          Every rung ›
        </button>
      </div>
      {flips.length > 0 && (
        <div role="list" aria-label="Where the delta turns short"
          style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(min(100%,300px),1fr))', gap: '8px 24px', padding: '12px 0 14px', borderTop: `1px solid ${ln(0.08)}` }}>
          {flips.map((x) => <div key={x.t} role="listitem" style={{ minWidth: 0 }}><FlipBody f={x.f!} size={narrow ? 17 : 20} /></div>)}
        </div>
      )}
      {g.groups.map((gr) => (
        <div key={gr.k} role="list" aria-label={gr.t} style={{ display: 'flex', flexDirection: 'column' }}>
          {/* The dot on the group's title, not on every row (as the app; Nik 25 Nov: the row dots looked off). */}
          <span style={{ display: 'flex', alignItems: 'center', padding: '10px 0 2px', borderTop: `1px solid ${ln(0.12)}`, ...label, lineHeight: '16px' }}>
            {(gr.k === 'itm' || gr.k === 'roll') && <Dot k={gr.k === 'itm' ? 'r' : 'g'} />}{gr.t}
          </span>
          {gr.rows.map((r) => <RungRow key={r.k} x={lineOf(r, true)} narrow={narrow} col={col} />)}
        </div>
      ))}
      {!g.need && <span style={{ padding: '12px 0', borderTop: `1px solid ${ln(0.12)}`, fontSize: 15, lineHeight: '20px', fontWeight: 500 }}>Nothing needs you today.</span>}
      {g.foot && <span style={{ padding: '10px 0', borderTop: `1px solid ${ln(0.08)}`, fontSize: 13, lineHeight: '18px', color: MU, textWrap: 'pretty' } as CSSProperties}>{g.foot}</span>}
      <style>{'.sw .sw-inc-open:hover{opacity:.8}'}</style>
    </section>
  );
}
