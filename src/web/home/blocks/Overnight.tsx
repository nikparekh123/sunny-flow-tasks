// Overnight (Web Dark v2, `b.isOvn`): four columns, Asia · Europe · Rates and the dollar · Commodities and crypto,
// each row the name and its value, under them the region and the move, and between them the month's line (Nik,
// 9 Nov 2026: trend lines, one month; the server sends `trend`: the closes, ending on today's price, its colour and
// words). Also draws The world this week.
// The doc's rows carry no group, so a row is placed by its name; with any name not known the rows run in four
// even columns with no group labels rather than guess.
import { Fragment } from 'react';
import type { J } from '../../lib/data';
import { C, clean, named } from '../../lib/format';
import { move } from './util';

const GROUPS: { k: string; l: string; status: boolean; re: RegExp }[] = [
  { k: 'asia', l: 'Asia', status: true, re: /^(nikkei|topix|hang seng|shanghai|shenzhen|csi|kospi|asx|sensex|nifty|taiex|straits)/i },
  { k: 'eu', l: 'Europe', status: true, re: /^(dax|ftse|cac|stoxx|euro stoxx|ibex|aex|smi|ftse mib|mib)/i },
  { k: 'rates', l: 'Rates and the dollar', status: false, re: /(yield|treasury|dollar|euro$|yen|pound|bund|gilt)/i },
  { k: 'cmd', l: 'Commodities and crypto', status: false, re: /^(oil|brent|wti|gold|silver|copper|natural gas|gas|bitcoin|ether|ethereum|crypto)/i },
];

interface Trend { pts: number[]; color: string; text: string }
interface ORow { name: string; sub: string; value: string; m: { t: string; c: string }; status: string; trend: Trend | null }

/** The month's line, drawn as the app's design draws Overnight (SunnyBriefs): 72 x 30 with 3 of padding above and
    below, the dashed line at where the month started, the line 1.5 in the month's colour, and a 2.5 dot at the end
    while the market still trades; the words on hover. It shrinks as a whole when the column is narrower. */
function MonthLine({ t, live }: { t: Trend; live: boolean }) {
  const W = 72, H = 30, P = 3, n = t.pts.length;
  const lo = Math.min(...t.pts), hi = Math.max(...t.pts), span = hi - lo || 1;
  const x = (i: number) => +((i / (n - 1)) * W).toFixed(1), y = (v: number) => +(P + ((hi - v) / span) * (H - 2 * P)).toFixed(1);
  const c = named(t.color, C.ink2), by = y(t.pts[0]);
  return (
    <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={t.text} style={{ width: '100%', maxWidth: W, height: 'auto', display: 'block', overflow: 'visible' }}>
      <title>{t.text}</title>
      <line x1={0} y1={by} x2={W} y2={by} style={{ stroke: C.ink2, strokeWidth: 1, strokeDasharray: '2 2.5', opacity: 0.6 }} />
      <path d={'M' + t.pts.map((v, i) => `${x(i)} ${y(v)}`).join('L')} style={{ fill: 'none', stroke: c, strokeWidth: 1.5, strokeLinejoin: 'round', strokeLinecap: 'round' }} />
      {live ? <circle cx={x(n - 1)} cy={y(t.pts[n - 1])} r={2.5} style={{ fill: c }} /> : null}
    </svg>
  );
}
const trendOf = (x: J): Trend | null => {
  const pts = Array.isArray(x?.pts) ? (x.pts as unknown[]).map(Number).filter((v) => Number.isFinite(v)) : [];
  return pts.length >= 2 ? { pts, color: String(x.color ?? ''), text: clean(x.text) } : null;
};

export default function Overnight({ card }: { card: J }) {
  const rows: ORow[] = (card.rows ?? []).map((r: J) => ({
    name: clean(r.name), sub: clean(r.sub), value: clean(r.value), m: move(r.move, r.moveColor, r.moveSigned), status: clean(r.status), trend: trendOf(r.trend),
  }));
  const week = card.type === 'worldThisWeek';
  const placed = rows.map((r) => GROUPS.findIndex((g) => g.re.test(r.name)));
  const grouped = rows.length > 0 && placed.every((i) => i >= 0);
  const cols: { k: string; l: string; rows: ORow[] }[] = grouped
    ? GROUPS.map((g, gi) => {
        const rs = rows.filter((_, i) => placed[i] === gi);
        const sts = [...new Set(rs.map((r) => r.status).filter(Boolean))];
        // "Asia · closed" as the design writes it; the week's review has no session to name.
        const l = g.status && !week && sts.length === 1 ? `${g.l} · ${sts[0]}` : g.l;
        return { k: g.k, l, rows: rs };
      }).filter((g) => g.rows.length)
    : [0, 1, 2, 3].map((c) => {
        const per = Math.ceil(rows.length / 4);
        return { k: 'c' + c, l: '', rows: rows.slice(c * per, c * per + per) };
      }).filter((g) => g.rows.length);
  const sub = clean(card.footer ?? card.subtitle);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', padding: '16px 0 0', borderTop: '1px solid rgba(255,255,255,.14)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12, paddingBottom: 10 }}>
        <span style={{ fontSize: 17, fontWeight: 600 }}>{clean(card.title) || 'Overnight'}</span>
        {sub ? <span style={{ fontSize: 13, color: C.ink2 }}>{sub}</span> : null}
      </div>
      <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(4,minmax(0,1fr))', gap: 32 }}>
        {cols.map((g) => (
          <div key={g.k} style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
            {g.l ? <span className="kicker" style={{ paddingBottom: 6 }}>{g.l}</span> : null}
            {/* One grid a column: name and region, the 72 x 30 line, value and move (the app's design, 12 apart). The
                names and values take what they need, so a column's lines stand one above the other. */}
            <div style={{ display: 'grid', gridTemplateColumns: 'max-content minmax(0,72px) max-content', justifyContent: 'space-between', columnGap: 12, alignItems: 'stretch' }}>
              {g.rows.map((r) => {
                const cell = { padding: '9px 0', display: 'flex', flexDirection: 'column' as const, gap: 1, justifyContent: 'center', minWidth: 0 };
                return (
                  <Fragment key={r.name}>
                    <span aria-hidden="true" style={{ gridColumn: '1 / -1', height: 1, background: 'rgba(255,255,255,.08)' }} />
                    <span style={cell}>
                      <span style={{ fontSize: 15, whiteSpace: 'nowrap' }}>{r.name}</span>
                      <span style={{ fontSize: 12, color: C.ink2, whiteSpace: 'nowrap' }}>{r.sub}</span>
                    </span>
                    <span style={cell}>{r.trend ? <MonthLine t={r.trend} live={r.status === 'still trading'} /> : null}</span>
                    <span style={{ ...cell, alignItems: 'flex-end' }}>
                      <span style={{ fontSize: 15, fontWeight: 600, whiteSpace: 'nowrap' }}>{r.value}</span>
                      <span style={{ fontSize: 12, fontWeight: 600, color: r.m.c, whiteSpace: 'nowrap' }}>{r.m.t}</span>
                    </span>
                  </Fragment>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
