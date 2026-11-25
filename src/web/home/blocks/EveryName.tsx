// Every name (Current Web `b.isNames`; handoff 2026-11-18 §3.1): every name in the book in one boxed table, short
// first, at the top of Your book. A row opens Positions on that name.
//   Name             the company logo in a 32 px white circle (logo at 60%, /logos/TICKER.png), a red dot when the name
//                    is short at its priced move by Friday, orange when thin; the ticker, the company and its shares
//   Price · moment   the price and the move Home reads for it (the Your names map: before the bell, today, the week)
//   Sector           its sector and the sector's move, from the brief's sector maps (each map holds that sector's
//                    biggest names only, so a smaller name reads a quiet "-")
//   Calls sold       each sold call strike × contracts; under it the share of the premium captured and the soonest expiry
//   Delta by Friday  the read (Your position, By name) in its colour; under it the move priced by Friday
//   Next             the next earnings or ex-dividend, then the one after
// Everything comes from the Home payload through the rail's model (railNames, the book engine) and the brief.
// Columns: the design's minmax tracks; the box scrolls sideways when narrow.
import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { BookId, J } from '../../lib/data';
import { C, clean, count, pct, price } from '../../lib/format';
import { inSessionOrder, nextEvents, railNames, strike } from '../rail/model';
import { holderOf } from '../top/parts';
import { BOX, TABLE_PAD } from './Card';
import { byNextFriday } from './cards';
import { pmove, type Mo } from './util';
import { useWideTables } from './width';

const COLS = 'minmax(118px,150px) minmax(84px,110px) minmax(100px,1fr) minmax(88px,120px) minmax(140px,1.6fr) minmax(92px,140px)';
/** Under 1320 px of content (Current Web, Nov 24 "looks odd"): the Sector column folds away and the rest stop
    squeezing, the name's line on one line. */
const COLS_N = 'minmax(140px,1.2fr) minmax(84px,100px) minmax(96px,120px) minmax(150px,1.6fr) minmax(100px,1fr)';
/** The tracks' least widths and the gaps: under this the box scrolls sideways. */
const MIN_W = 118 + 84 + 100 + 88 + 140 + 92 + 5 * 12, MIN_W_N = 140 + 84 + 96 + 150 + 100 + 4 * 12;
const HAIR = '1px solid rgba(255,255,255,.08)';
const PERIOD: Record<Mo, string> = { pre: 'before the bell', open: 'today', post: 'today', weekend: 'the week' };
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const md = (iso: string) => { const [, m, d] = iso.split('-').map(Number); return m && d ? `${MON[m - 1]} ${d}` : ''; };
const lc1 = (s: string) => (s ? s[0].toLowerCase() + s.slice(1) : s);
const READ: Record<string, string> = { red: C.red, orange: C.orange, ink: C.ink };

interface NameRow {
  t: string; nm: string; dot: string | null;
  px: string; mv: string; mc: string;
  sec: string; sm: string; smc: string;
  cs: string; cs2: string; cs2c: string;
  rd: string; rdc: string; pm: string;
  nx: string; nx2: string;
}

/** Each held ticker's sector and that sector's move, from the brief's sectors card. */
function sectorOf(doc: J): Map<string, { t: string; mv: number }> {
  const out = new Map<string, { t: string; mv: number }>();
  for (const s of doc?.sections ?? []) for (const c of s?.cards ?? []) {
    if (c?.type !== 'sectors') continue;
    for (const m of c.maps ?? []) {
      const mv = m.moveSigned != null ? +m.moveSigned : (m.moveColor === 'red' ? -1 : 1) * parseFloat(m.move);
      for (const x of m.tiles ?? []) if (x?.ticker && !out.has(String(x.ticker))) out.set(String(x.ticker), { t: clean(m.title), mv: mv || 0 });
    }
  }
  return out;
}

export function everyNameRows(payload: J, doc: J, book: BookId, fri: (s: string) => string): NameRow[] {
  const names = inSessionOrder(book, railNames(payload));
  const inputs = new Map<string, J>(((payload?.brief_inputs?.names ?? []) as J[]).map((n) => [String(n.t), n]));
  const brief = new Map<string, J>(((payload?.brief?.names ?? []) as J[]).map((n) => [String(n.t), n]));
  const secs = sectorOf(doc);
  // Together: each row says whose it is, "Nike · 1,000 shares · Sunny" (Current Web `TG ? ' · Nicolay' : ' · Sunny'`).
  const who = holderOf(payload);
  return names.map((n) => {
    const legs: J[] = inputs.get(n.t)?.legs ?? [];
    const shares = legs.filter((l) => l.kind === 'shares').reduce((a, l) => a + (+l.q || 0), 0);
    const leaps = legs.filter((l) => l.kind === 'leaps').reduce((a, l) => a + (+l.q || 0), 0);
    const held = shares > 0 ? `${count(shares)} shares` : leaps > 0 ? `${count(leaps)} LEAPS` : '';
    const sc = legs.filter((l) => l.kind === 'sc' && +l.q < 0)
      .sort((a, b) => String(a.ex).localeCompare(String(b.ex)) || +a.K - +b.K);
    // One entry a strike (the contracts at that strike added across expiries), soonest expiry first.
    const byK = new Map<number, number>();
    for (const l of sc) byK.set(+l.K, (byK.get(+l.K) ?? 0) + Math.abs(+l.q));
    const sx = secs.get(n.t);
    const sd = +(brief.get(n.t)?.sd ?? 0);
    const ev = nextEvents(n.t, payload);
    const kp = n.kept ? Math.round(n.kept.pct) : null;
    return {
      t: n.t, nm: [n.company, held, who(n.t)].filter(Boolean).join(' · '),
      dot: n.st === 2 ? C.red : n.st === 1 ? C.orange : null,
      px: price(n.px), mv: pmove(n.mv), mc: n.mv < 0 ? C.red : C.green,
      sec: sx ? sx.t : '-', sm: sx ? pmove(sx.mv) : '', smc: sx && sx.mv < 0 ? C.red : C.green,
      cs: sc.length ? [...byK].map(([k, q]) => `${strike(k)} ×${count(q)}`).join(', ') : '-',
      cs2: sc.length ? [kp == null ? '' : kp >= 0 ? `${kp}% captured` : `costs ${-kp}% more`, md(String(sc[0].ex))].filter(Boolean).join(' · ') : '',
      cs2c: kp != null && kp < 0 ? C.red : C.ink2,
      rd: n.read ? fri(n.read) : '-', rdc: n.read ? READ[n.readColor] ?? C.ink : C.ink2,
      pm: sd > 0 ? `priced to move ±${pct(sd)} · ±${price(n.px * sd / 100)}` : '',
      nx: ev[0] ?? '-', nx2: ev[1] ? lc1(ev[1]) : '',
    };
  });
}

/** A company logo in a white circle (the app's and the Positions strip's style); the ticker when there is no logo. */
function Logo({ t, dot }: { t: string; dot: string | null }) {
  const [bad, setBad] = useState(false);
  return (
    <span aria-hidden="true" style={{ flex: 'none', position: 'relative', width: 32, height: 32, borderRadius: '50%', background: '#FFFFFF', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      {bad
        ? <span style={{ fontSize: 9, fontWeight: 700, color: '#1D1D1F' }}>{t.slice(0, 4)}</span>
        : <img src={`/logos/${encodeURIComponent(t)}.png`} alt="" onError={() => setBad(true)} style={{ width: '60%', height: '60%', objectFit: 'contain' }} />}
      {dot && <span style={{ position: 'absolute', right: -2, top: -2, width: 9, height: 9, borderRadius: '50%', background: dot }} />}
    </span>
  );
}

export default function EveryName({ payload, doc, book, mo }: { payload: J; doc: J; book: BookId; mo: Mo }) {
  const navigate = useNavigate();
  // The weekend's rows say "by next Friday" when Your position's header does.
  const head = clean(payload?.brief?.position?.subtitle);
  const fri = useMemo(() => byNextFriday(head), [head]);
  const rows = useMemo(() => everyNameRows(payload, doc, book, fri), [payload, doc, book, fri]);
  const wide = useWideTables(), cols = wide ? COLS : COLS_N;
  if (!rows.length) return null;
  const sub = (s: string, c: string = C.ink2, w = 400) => (s ? <span style={{ fontSize: 12, fontWeight: w, color: c }}>{s}</span> : null);
  return (
    <div aria-label="Every name" style={{ ...BOX, padding: TABLE_PAD, display: 'flex', flexDirection: 'column', overflowX: 'auto', minWidth: 0 }}>
      <div style={{ minWidth: wide ? MIN_W : MIN_W_N, display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12, paddingBottom: 10 }}>
          <span style={{ fontSize: 17, fontWeight: 600, whiteSpace: 'nowrap' }}>Every name</span>
          <span style={{ fontSize: 13, color: C.ink2, textAlign: 'right' }}>short first · a row opens Positions</span>
        </div>
        <div className="tnum kicker" style={{ display: 'grid', gridTemplateColumns: cols, gap: 12, padding: '6px 0 8px', whiteSpace: 'nowrap' }}>
          <span>Name</span><span>Price · {PERIOD[mo]}</span>{wide && <span>Sector</span>}<span>Calls sold</span><span>{fri('Delta by Friday')}</span><span>Next</span>
        </div>
        {rows.map((r) => (
          <button key={r.t} type="button" className="bare tnum swb-row" onClick={() => navigate('/positions/' + encodeURIComponent(r.t))}
            aria-label={`${r.t}, ${r.nm}, ${r.px} ${r.mv}, ${r.rd}. Opens Positions`}
            style={{ cursor: 'pointer', width: '100%', display: 'grid', gridTemplateColumns: cols, gap: 12, alignItems: 'start', padding: '13px 0', borderTop: HAIR }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
              <Logo t={r.t} dot={r.dot} />
              <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                <span style={{ fontSize: 15, fontWeight: 600 }}>{r.t}</span>
                <span title={r.nm} style={{ fontSize: 12, color: C.ink2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.nm}</span>
              </span>
            </span>
            <span style={{ display: 'flex', flexDirection: 'column' }}>
              <span style={{ fontSize: 15, fontWeight: 500 }}>{r.px}</span>
              {sub(r.mv, r.mc, 600)}
            </span>
            {wide && (
              <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                <span style={{ fontSize: 14, lineHeight: '19px', color: r.sm ? C.ink : C.ink2 }}>{r.sec}</span>
                {sub(r.sm, r.smc, 600)}
              </span>
            )}
            <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
              <span style={{ fontSize: 14, color: r.cs === '-' ? C.ink2 : C.ink }}>{r.cs}</span>
              {sub(r.cs2, r.cs2c)}
            </span>
            <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
              <span style={{ fontSize: 14, lineHeight: '19px', fontWeight: 600, color: r.rdc }}>{r.rd}</span>
              {sub(r.pm)}
            </span>
            <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
              <span style={{ fontSize: 13, lineHeight: '18px', color: r.nx === '-' ? C.ink2 : C.ink }}>{r.nx}</span>
              {sub(r.nx2)}
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}
