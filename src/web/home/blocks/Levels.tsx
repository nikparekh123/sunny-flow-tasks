// The Levels card (handoff 2026-11-18; Nik picked 161c on 16 Nov; SunnyActivity.dc.html view="levels" web): in
// 2 · Your book at every moment, after Your names. On the web it is flat in its box, two columns and no fold (one
// column under 640 px):
//   left    "3 names crossed a line today." and, thin, the names under all three averages; then one row a name that
//           crossed a line in the card's window (logo, name, what and when; the price and its move). A row opens the
//           Activity panel on that line.
//   right   every name held against its 20, 50 and 200-day, then against this week's walls, as logo chips; a dot marks
//           a name that changed in the window.
// The card from the server says only which window ({type: 'levels', when: 'today' | 'yday' | 'week'}: the session and
// after, before the bell, the weekend); the figures come from payload.activity (levels and the level and move lines).
import { useMemo, type CSSProperties } from 'react';
import type { J } from '../../lib/data';
import { C, pct, price } from '../../lib/format';
import { useWeb } from '../../lib/state';
import { Logo } from '../../activity/Activity';
import { daysOf, nyTime, readActivity, type ActEvent, type ActLevel } from '../../activity/model';
import { strike } from '../rail/model';
import { BOX } from './Card';

type When = 'today' | 'yday' | 'week';
const SUB = C.ink2, THIN = 'rgba(245,245,247,.72)', LN = '1px solid rgba(255,255,255,.08)';
const SPAN: Record<When, string> = { today: 'today', yday: 'yesterday', week: 'this week' };
const HEAD: Record<When, string> = { today: 'Today', yday: 'Yesterday', week: 'This week' };
/** The averages in plain words: '1' over, '0' under, for the 20, 50 and 200-day. */
const MA: [string, string][] = [
  ['111', 'Over all three averages'], ['011', 'Under the 20-day'], ['001', 'Under the 20 and 50-day'],
  ['100', 'Over the 20-day, under the 50 and 200'], ['110', 'Under the 200-day'], ['101', 'Under the 50-day'],
  ['010', 'Over the 50-day only'], ['000', 'Under all three'],
];
const WALLS: [ActLevel['wall'], string][] = [['c', 'Near a ceiling'], ['f', 'Near a floor'], ['b', 'Between the walls']];

/** A pattern with a missing average ('-'): said from the ones there are. */
function maWords(p: string): string {
  const L = ['20', '50', '200'], over = L.filter((_, i) => p[i] === '1'), under = L.filter((_, i) => p[i] === '0');
  const of = (xs: string[]) => (xs.length === 3 ? 'all three' : xs.length === 2 ? `the ${xs[0]} and ${xs[1]}-day` : `the ${xs[0]}-day`);
  if (!over.length && !under.length) return 'No averages yet';
  if (!under.length) return `Over ${of(over)}`;
  if (!over.length) return `Under ${of(under)}`;
  return `Over ${of(over)}, under ${of(under)}`;
}
/** "Alibaba, FIS and Nike". */
const andList = (xs: string[]) => (xs.length < 2 ? xs.join('') : `${xs.slice(0, -1).join(', ')} and ${xs[xs.length - 1]}`);
const cap1 = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);

interface LvRow { k: string; t: string; nm: string; w: string; tm: string; px: string; mv: string; mc: string; aria: string }
interface Chip { t: string; v: string; dot: boolean; aria: string }
interface Block { k: string; h: string; rows: { k: string; l: string; names: Chip[] }[] }

export default function Levels({ card, payload }: { card: J; payload: J }) {
  const { openActivity } = useWeb();
  const act = useMemo(() => readActivity(payload), [payload]);
  const when: When = card?.when === 'yday' || card?.when === 'week' ? card.when : 'today';

  const m = useMemo(() => {
    if (!act) return null;
    const d = daysOf(act.today), lv = new Map(act.levels.map((l) => [l.t, l]));
    const inWin = (e: ActEvent) => (when === 'today' ? e.day === act.today : when === 'yday' ? e.day === d.yday : e.day >= d.mon && e.day <= act.today);
    // One row a name, its newest line (the events come newest first).
    const seen = new Set<string>(), hit: ActEvent[] = [];
    for (const e of act.events) {
      if ((e.kind !== 'lvl' && e.kind !== 'move') || !e.t || seen.has(e.t) || !inWin(e)) continue;
      seen.add(e.t);
      hit.push(e);
    }
    const rows: LvRow[] = hit.map((e) => {
      const t = e.t!, l = lv.get(t), nm = l?.name ?? t;
      const w = cap1(e.title.toLowerCase().startsWith(nm.toLowerCase() + ' ') ? e.title.slice(nm.length + 1) : e.title.replace(/^\S+\s+/, ''));
      const tm = nyTime(e.at, when === 'week');
      const px = l && l.px > 0 ? price(l.px) : '', up = (l?.mv ?? 0) >= 0;
      const mv = l?.mv != null ? `${up ? '▲' : '▼'} ${pct(l.mv)}` : '';
      return { k: e.key, t, nm, w, tm, px, mv, mc: up ? C.green : C.red,
        aria: `${nm}, ${w.toLowerCase()} at ${tm}${px ? ', ' + px : ''}${mv ? `, ${up ? 'up' : 'down'} ${pct(l!.mv)}` : ''}. Opens Activity` };
    });
    const under = act.levels.filter((l) => l.ma === '000');
    const n = rows.length, span = SPAN[when];
    const thick = n ? `${n} ${n === 1 ? 'name' : 'names'} crossed a line ${span}.` : `No name crossed a line ${span}.`;
    const thin = !under.length ? ''
      : under.length > 1 && under.length === act.levels.length ? ' Every name is under all three averages.'
      : ` ${andList(under.map((l) => l.name))} ${under.length === 1 ? 'is' : 'are'} under all three averages.`;

    const chip = (l: ActLevel, v = ''): Chip => ({ t: l.t, v, dot: seen.has(l.t), aria: `${l.name}${v ? ' ' + v : ''}${seen.has(l.t) ? `, changed ${span}` : ''}` });
    const pats = [...MA.map(([p]) => p), ...[...new Set(act.levels.map((l) => l.ma))].filter((p) => !MA.some(([q]) => q === p))];
    const maRows = pats.map((p) => ({ k: p, l: MA.find(([q]) => q === p)?.[1] ?? maWords(p), names: act.levels.filter((l) => l.ma === p).map((l) => chip(l)) }))
      .filter((r) => r.names.length);
    const wallRows = WALLS.map(([w, l]) => ({ k: w, l, names: act.levels.filter((x) => x.wall === w).map((x) => chip(x, x.wall !== 'b' && x.wallK ? strike(x.wallK) : '')) }))
      .filter((r) => r.names.length);
    const blocks: Block[] = [{ k: 'a', h: 'Against the 20, 50 and 200-day', rows: maRows }, { k: 'w', h: 'Against this week’s walls', rows: wallRows }]
      .filter((b) => b.rows.length);
    return { rows, thick, thin, blocks, dots: seen.size > 0, span };
  }, [act, when]);

  if (!m) return null;
  return (
    <section aria-label="Levels" className="lvc tnum" style={{ ...BOX, padding: '20px 24px 18px', minWidth: 0 }}>
      <style>{LV_CSS}</style>
      <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <span style={{ fontSize: 17, lineHeight: '20px', fontWeight: 600 }}>Levels</span>
        <p style={{ margin: '6px 0 10px', fontSize: 17, lineHeight: '24px', textWrap: 'pretty' } as CSSProperties}>
          <span style={{ fontWeight: 600 }}>{m.thick}</span><span style={{ color: THIN }}>{m.thin}</span>
        </p>
        {m.rows.length > 0 && <span style={{ padding: '2px 0 6px', fontSize: 12, lineHeight: '16px', fontWeight: 600, color: SUB }}>{HEAD[when]}</span>}
        {m.rows.map((r) => (
          <button key={r.k} type="button" className="bare swb-row" onClick={() => openActivity(r.k)} aria-label={r.aria}
            style={{ display: 'grid', gridTemplateColumns: '28px minmax(0,1fr) auto 12px', gap: 10, alignItems: 'center', minHeight: 56, padding: '8px 0', borderTop: LN }}>
            <Logo t={r.t} size={28} />
            <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
              <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{r.nm}</span>
              <span style={{ fontSize: 13, lineHeight: '18px', color: SUB, textWrap: 'pretty' } as CSSProperties}>{r.w} · {r.tm}</span>
            </span>
            <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 1 }}>
              {r.px && <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{r.px}</span>}
              {r.mv && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: r.mc, whiteSpace: 'nowrap' }}>{r.mv}</span>}
            </span>
            <svg aria-hidden="true" width="12" height="12" viewBox="0 0 24 24" style={{ color: SUB, fill: 'none', stroke: 'currentColor', strokeWidth: 3, strokeLinecap: 'round', strokeLinejoin: 'round' }}>
              <path d="M9 6l6 6-6 6" />
            </svg>
          </button>
        ))}
      </div>
      <div className="lvc-r" style={{ display: 'flex', flexDirection: 'column', gap: 16, minWidth: 0 }}>
        {m.blocks.map((b) => (
          <div key={b.k} role="group" aria-label={b.h} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: SUB }}>{b.h}</span>
            {b.rows.map((g) => (
              <div key={g.k} style={{ display: 'flex', flexDirection: 'column', gap: 6, paddingTop: 8, borderTop: LN }}>
                <span style={{ fontSize: 14, lineHeight: '18px', fontWeight: 500 }}>{g.l}</span>
                <div role="list" aria-label={g.l} style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                  {g.names.map((n) => (
                    <span key={n.t} role="listitem" aria-label={n.aria}
                      style={{ display: 'flex', alignItems: 'center', gap: 6, height: 28, padding: '0 10px 0 4px', borderRadius: 999, background: 'rgba(118,118,128,.24)',
                        fontSize: 13, lineHeight: '16px', fontWeight: 600 }}>
                      <Logo t={n.t} size={20} />
                      <span aria-hidden="true">{n.t}</span>
                      {n.v && <span aria-hidden="true" style={{ fontWeight: 500, color: SUB }}>{n.v}</span>}
                      {n.dot && <span aria-hidden="true" style={{ width: 6, height: 6, borderRadius: '50%', background: '#0A84FF' }} />}
                    </span>
                  ))}
                </div>
              </div>
            ))}
          </div>
        ))}
        <span style={{ fontSize: 12, lineHeight: '17px', color: SUB, textWrap: 'pretty' } as CSSProperties}>
          {m.dots ? `A dot: changed ${m.span}. ` : ''}Walls are this week’s chain; near is within 1%.
        </span>
      </div>
    </section>
  );
}

const LV_CSS = `.sw .lvc{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:0 44px;align-items:start}
.sw .lvc-r{padding-top:6px}
@media (max-width:640px){.sw .lvc{grid-template-columns:minmax(0,1fr);row-gap:18px}.sw .lvc-r{padding-top:0}}`;
