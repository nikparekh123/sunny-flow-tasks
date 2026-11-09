// Overnight (Web Dark v2, `b.isOvn`): four columns, Asia · Europe · Rates and the dollar · Commodities and crypto,
// each row the name and its value, under them the region and the move. Also draws The world this week.
// The doc's rows carry no group, so a row is placed by its name; with any name not known the rows run in four
// even columns with no group labels rather than guess.
import type { J } from '../../lib/data';
import { C, clean } from '../../lib/format';
import { move } from './util';

const GROUPS: { k: string; l: string; status: boolean; re: RegExp }[] = [
  { k: 'asia', l: 'Asia', status: true, re: /^(nikkei|topix|hang seng|shanghai|shenzhen|csi|kospi|asx|sensex|nifty|taiex|straits)/i },
  { k: 'eu', l: 'Europe', status: true, re: /^(dax|ftse|cac|stoxx|euro stoxx|ibex|aex|smi|ftse mib|mib)/i },
  { k: 'rates', l: 'Rates and the dollar', status: false, re: /(yield|treasury|dollar|euro$|yen|pound|bund|gilt)/i },
  { k: 'cmd', l: 'Commodities and crypto', status: false, re: /^(oil|brent|wti|gold|silver|copper|natural gas|gas|bitcoin|ether|ethereum|crypto)/i },
];

interface ORow { name: string; sub: string; value: string; m: { t: string; c: string }; status: string }

export default function Overnight({ card }: { card: J }) {
  const rows: ORow[] = (card.rows ?? []).map((r: J) => ({
    name: clean(r.name), sub: clean(r.sub), value: clean(r.value), m: move(r.move, r.moveColor, r.moveSigned), status: clean(r.status),
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
            {g.rows.map((r) => (
              <div key={r.name} style={{ display: 'flex', flexDirection: 'column', gap: 1, padding: '9px 0', borderTop: '1px solid rgba(255,255,255,.08)' }}>
                <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                  <span style={{ fontSize: 15 }}>{r.name}</span>
                  <span style={{ fontSize: 15, fontWeight: 600, whiteSpace: 'nowrap' }}>{r.value}</span>
                </span>
                <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                  <span style={{ fontSize: 12, color: C.ink2 }}>{r.sub}</span>
                  <span style={{ fontSize: 12, fontWeight: 600, color: r.m.c, whiteSpace: 'nowrap' }}>{r.m.t}</span>
                </span>
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}
