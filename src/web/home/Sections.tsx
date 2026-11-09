// Home's numbered sections (README 1, item 8, and "Blocks used inside sections"; Web Dark v2 `d.hs`).
// Each section: padding-top 64, gap 22 inside; the kicker ("1 · WORLD AND ECONOMY") 8 over the headline (h2 28/36,
// the first sentence 600, the rest 400 at .72); then its blocks. Cards sit in a two-column grid; Overnight, the
// economy readings and the sectors table with its heat maps take the full width.
// The index cards (indexCards, futuresCards, theWeekIndexes) are not drawn here: the index strip at the top of Home
// carries those numbers. A section with nothing else is skipped (its headline moves into the strip), and the
// sections drawn are numbered 1, 2, 3 in order.
import { useMemo, useState, type ReactNode } from 'react';
import type { BookId, J } from '../lib/data';
import { useWeb } from '../lib/state';
import { clean, named } from '../lib/format';
import './blocks/blocks.css';
import { Grid, More } from './blocks/Card';
import { gridCards, type Ctx } from './blocks/cards';
import Economy, { OutToday, readings } from './blocks/Economy';
import Overnight from './blocks/Overnight';
import { SectorMaps, SectorTable, sectorsOf } from './blocks/Sectors';
import { momentOf, scrollToSel, spans, tidy, type Mo, type Span } from './blocks/util';

const INDEX = new Set(['indexCards', 'futuresCards', 'theWeekIndexes']);
const PERIOD: Record<Mo, string> = { pre: 'before the bell', open: 'today', post: 'today', weekend: 'the week' };

/* ── The headline: thick then thin ─────────────────────────────────────────── */
// The server's split when it sends one (a run with b: false); else the first sentence thick and the rest thin, cut
// where the phone cuts it (HeadlineWeight.split): a . ! or ? then a space and more words, not after an abbreviation,
// initials or a single capital.
const ABBR = new Set(['mr', 'mrs', 'ms', 'dr', 'st', 'jr', 'sr', 'inc', 'corp', 'co', 'ltd', 'vs', 'approx', 'no', 'jan', 'feb', 'mar', 'apr',
  'jun', 'jul', 'aug', 'sep', 'sept', 'oct', 'nov', 'dec', 'mon', 'tue', 'tues', 'wed', 'thu', 'thur', 'thurs', 'fri', 'sat', 'sun']);
function firstSentenceEnd(c: string): number | null {
  for (let i = 0; i < c.length - 1; i++) {
    if (!'.!?'.includes(c[i])) continue;
    let j = i + 1;
    while (j < c.length && '”’")\''.includes(c[j])) j++;
    if (!(j < c.length && c[j] === ' ' && /\S/.test(c.slice(j + 1)))) continue;
    if (c[i] === '.') {
      let k = i;
      while (k > 0 && !/\s/.test(c[k - 1])) k--;
      const letters = c.slice(k, i).replace(/^[(“"]+/, '');
      if (ABBR.has(letters.toLowerCase())) continue;
      if (/^([A-Za-z]\.)+[A-Za-z]$/.test(letters)) continue;
      if (letters.length === 1 && /[A-Z]/.test(letters)) continue;
      if (i > 0 && c[i - 1] === '.') continue;
    }
    return j + 1;
  }
  return null;
}
function split(runs: Span[]): { t: string; thick: boolean; c?: string }[] {
  if (runs.some((r) => r.b === false) && runs.some((r) => r.b)) return runs.map((r) => ({ t: r.t, thick: !!r.b, c: r.c }));
  const all = runs.map((r) => r.t).join('');
  const cut = firstSentenceEnd(all) ?? all.length;
  const out: { t: string; thick: boolean; c?: string }[] = [];
  let at = 0;
  for (const r of runs) {
    const end = at + r.t.length;
    if (end <= cut) out.push({ t: r.t, thick: true, c: r.c });
    else if (at >= cut) out.push({ t: r.t, thick: false, c: r.c });
    else { out.push({ t: r.t.slice(0, cut - at), thick: true, c: r.c }); out.push({ t: r.t.slice(cut - at), thick: false, c: r.c }); }
    at = end;
  }
  return out;
}

function Headline({ runs, mask }: { runs: Span[]; mask: (s: string) => string }) {
  const parts = split(runs.map((r) => ({ ...r, t: tidy(r.t) })));
  return (
    <h2 className="h2">
      {parts.map((p, i) => (p.thick
        ? <span key={i} style={p.c ? { color: named(p.c) } : undefined}>{mask(p.t)}</span>
        : <span key={i} className="thin" style={p.c ? { color: named(p.c, 'rgba(245,245,247,.72)') } : undefined}>{mask(p.t)}</span>))}
    </h2>
  );
}

/* ── The sections ─────────────────────────────────────────────────────────── */
export default function Sections({ doc, payload, book }: { doc: J; payload: J; book: BookId }) {
  const { mask, privacy } = useWeb();
  const mo = momentOf(doc?.moment);
  const [folds, setFolds] = useState<Record<string, boolean>>({});
  const isOpen = (k: string) => !!folds[`${book}:${mo}:${k}`];
  const toggle = (k: string, v?: boolean) => setFolds((f) => ({ ...f, [`${book}:${mo}:${k}`]: v ?? !f[`${book}:${mo}:${k}`] }));

  const names: J[] = payload?.brief?.names ?? [];
  const held = useMemo(() => new Set<string>(names.map((n) => String(n.t))), [names]);
  const company = useMemo(() => {
    const m: Record<string, string> = {};
    for (const n of names) if (n?.t) m[n.t] = n.name ?? n.t;
    for (const r of payload?.brief?.position?.rows ?? []) if (r?.id && !m[r.id]) m[r.id] = r.name;
    return m;
  }, [names, payload]);
  // A heat-map tile opens the ticker page for a book or watchlist name only.
  const linked = useMemo(() => {
    const s = new Set<string>(held);
    for (const w of payload?.watchlist ?? []) if (w?.ticker) s.add(String(w.ticker));
    for (const sec of doc?.sections ?? []) for (const c of sec.cards ?? []) if (c.type === 'yourNames')
      for (const p of c.pages ?? []) for (const t of p.tiles ?? []) if (t?.ticker) s.add(String(t.ticker));
    return s;
  }, [held, payload, doc]);

  const cx: Ctx = { mo, mask, position: payload?.brief?.position, company };
  const secs = (doc?.sections ?? [])
    .map((s: J) => ({ s, cards: (s.cards ?? []).filter((c: J) => c && !INDEX.has(c.type)) }))
    .filter((x: { cards: J[] }) => x.cards.length);
  if (!secs.length) return null;

  return (
    <>
      {secs.map(({ s, cards }: { s: J; cards: J[] }, si: number) => {
        const runs = spans(privacy ? (s.privacy?.headline ?? s.headline) : s.headline);
        const blocks: ReactNode[] = [];
        let grid: ReactNode[] = [];
        const flush = () => { if (grid.length) { blocks.push(<Grid key={'g' + blocks.length}>{grid}</Grid>); grid = []; } };
        const full = (n: ReactNode) => { flush(); blocks.push(<div key={'b' + blocks.length} style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>{n}</div>); };
        cards.forEach((c: J, ci: number) => {
          const key = `${si}-${ci}`;
          switch (c.type) {
            case 'overnight': case 'worldThisWeek':
              full(<Overnight card={c} />);
              break;
            case 'economy': {
              const list = readings(doc, c);
              if (!list.length) break;
              // Pre-market leads with the readings; later they fold (they change weekly or monthly).
              if (mo === 'pre') { full(<Economy list={list} />); break; }
              const k = 'econ' + key;
              if (isOpen(k)) full(<Economy list={list} />);
              full(<More open={isOpen(k)} onToggle={() => toggle(k)}
                label={isOpen(k) ? `Fold the ${list.length} readings` : `Show the ${list.length} readings · they change weekly or monthly`} />);
              break;
            }
            case 'outToday':
              full(<OutToday card={c} />);
              break;
            case 'sectors': {
              const sx = sectorsOf(c, held);
              if (!sx.length) break;
              const k = 'maps' + key;
              // Pre-market keeps sectors to the table; market hours opens the maps; post-market and the weekend fold
              // them one link away. A row opens its sector's map.
              const onRow = mo === 'pre' ? undefined : (id: string) => {
                if (mo !== 'open' && !isOpen(k)) toggle(k, true);
                window.setTimeout(() => scrollToSel(`[data-sec="map-${id}"]`), 80);
              };
              full(<SectorTable secs={sx} sub={`cap-weighted, ${PERIOD[mo]}${mo === 'pre' ? '' : ' · a row opens its map'}`} onRow={onRow} />);
              if (mo === 'open' || (mo !== 'pre' && isOpen(k))) full(<SectorMaps secs={sx} held={held} linked={linked} />);
              if (mo === 'post' || mo === 'weekend') {
                full(<More open={isOpen(k)} onToggle={() => toggle(k)} label={isOpen(k) ? 'Fold the names' : 'Show every sector’s biggest names'} />);
              }
              break;
            }
            default:
              grid.push(...gridCards(c, cx, key));
          }
        });
        flush();
        return (
          <section key={si} data-sec={'s' + si} data-kicker={clean(s.kicker)} aria-label={clean(s.kicker)} style={{ display: 'flex', flexDirection: 'column', gap: 22, paddingTop: 64 }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <span className="kicker">{si + 1} · {String(s.kicker ?? '').replace(/^\d+ · /, '')}</span>
              <Headline runs={runs} mask={mask} />
            </div>
            {blocks}
          </section>
        );
      })}
    </>
  );
}

