// Overview · Both accounts (README "3 · Overview"): the coach's view of both books, in rates rather than dollars
// so a book a third the size compares fairly. Opened from the account menu's "Both accounts".
//
// The report itself is the phone's: sunny-home builds it in book S's build from both books (payload.overview:
// sentence, six checks with a chip per book, Coming in; overview.ts, Brief/Overview.swift). The three numbers are
// each book's account value and today's change (payload.account); Allocation reads each book's own legs.
// The server builds the checks for this week only, so the period control offers This week alone.
import { useState } from 'react';
import { AccountMenu, BOOK_NAME } from '../components/AccountMenu';
import { CountUp } from '../components/CountUp';
import { useHome, type BookId, type J } from '../lib/data';
import { C, arrow, dollars, money, pct } from '../lib/format';
import { useWeb } from '../lib/state';
import { Allocation } from '../overview/Allocation';
import { allocationRows, chipFor, splitSentence, type AlRow } from '../overview/model';
import { Seg } from '../overview/Seg';

const HAIR = '1px solid rgba(255,255,255,.08)', HAIR_S = '1px solid rgba(255,255,255,.14)';
const GRID = 'minmax(0,1.3fr) minmax(0,1fr) minmax(0,1fr) 110px';
/** The design's six rows, in its order, with what each measures. */
const CHECKS: [string, string][] = [
  ['Pace', 'kept on what you bought'],
  ['Calls at work', 'calls sold ÷ shares ÷ 100'],
  ['Delta', 'short or thin by Friday'],
  ['To do', 'orders for the open'],
  ['Downside', 'shares the puts cover'],
  ['Concentration', 'the biggest name, by capital bought'],
];

/** "▼ $13.7K today" in red, "▲ ... " in green; a day with no change reads "$0 today" in grey. */
function dayLine(a: number | null) {
  if (a == null) return { t: '', c: C.ink2 };
  const r = Math.round(a);
  if (r === 0) return { t: '$0 today', c: C.ink2 };
  return { t: `${arrow(r)} ${money(r)} today`, c: r < 0 ? C.red : C.green };
}

export default function Overview() {
  const { books, mask, pickAccount } = useWeb();
  const hasS = books.includes('S'), hasN = books.includes('N');
  const hs = useHome(hasS ? 'S' : null), hn = useHome(hasN ? 'N' : null);
  const pay: Record<BookId, J> = { S: hs.data?.payload, N: hn.data?.payload };
  const ids = (['S', 'N'] as BookId[]).filter((b) => books.includes(b));
  const ov: J = pay.S?.overview && !pay.S.overview.error ? pay.S.overview : null;
  const [per, setPer] = useState<'wk'>('wk');

  const rows: Record<BookId, AlRow[] | null> = { S: pay.S ? allocationRows(pay.S) : null, N: pay.N ? allocationRows(pay.N) : null };
  const val = (b: BookId) => (pay[b]?.account?.value != null ? Number(pay[b].account.value) : null);
  const day = (b: BookId) => (pay[b]?.account?.today?.amount != null ? Number(pay[b].account.today.amount) : null);
  const loaded = ids.every((b) => val(b) != null);
  const tog = loaded ? ids.reduce((a, b) => a + (val(b) ?? 0), 0) : null;
  const togDay = loaded && ids.every((b) => day(b) != null) ? ids.reduce((a, b) => a + (day(b) ?? 0), 0) : null;

  const sent = ov ? splitSentence(ov.sentence) : null;
  const byName = new Map<string, J>(((ov?.checks ?? []) as J[]).map((c) => [String(c.name), c]));
  const cell = (name: string, b: BookId): string => {
    const c = byName.get(name), bn = BOOK_NAME[b];
    if (name === 'Concentration') {
      const r = rows[b];
      if (!r || !r.length) return 'None';
      const tot = r.reduce((a, x) => a + x.cap, 0);
      return `${r[0].name} ${pct((r[0].cap / tot) * 100)}`;
    }
    const v = chipFor(c, bn);
    if (name === 'Pace') return v ? `${v} a week` : 'None';
    if (name === 'Calls at work') return v ? `${v} of shares` : 'None';
    if (name === 'To do') {
      const n = v != null ? Number(v) : Number(((ov?.raw?.orders ?? []) as J[]).find((o) => o.id === b)?.n ?? 0);
      return n > 0 ? `${n} ${n === 1 ? 'order' : 'orders'}` : 'None';
    }
    return v ?? 'None';
  };
  const ci = ov?.comingIn;
  const foot = 'Rates, not dollars, so a book a third the size compares fairly.'
    + (ci?.amount && ci?.line ? ` ${ci.title ?? 'Coming in'} ${ci.amount} · ${ci.line}.` : '');

  const t0 = dayLine(togDay);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 28 }}>
      <div style={{ alignSelf: 'flex-start' }}><AccountMenu /></div>

      {sent && sent.thick && (
        <p style={{ margin: '-10px 0 0', maxWidth: 980, fontSize: 26, lineHeight: '35px', letterSpacing: '-.015em', textWrap: 'pretty' } as React.CSSProperties}>
          <span style={{ fontWeight: 600 }}>{mask(sent.thick)}</span>
          {sent.thin && <>{' '}<span style={{ fontWeight: 400, color: 'rgba(245,245,247,.68)' }}>{mask(sent.thin)}</span></>}
        </p>
      )}

      <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', padding: '18px 0', borderTop: HAIR_S, borderBottom: HAIR }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <span style={{ fontSize: 13, color: C.ink2 }}>Together</span>
          <span style={{ fontSize: 34, lineHeight: '40px', fontWeight: 700, letterSpacing: '-.025em' }}>
            {tog != null ? <CountUp v={mask(dollars(tog))} /> : ' '}
          </span>
          <span style={{ fontSize: 14, fontWeight: 600, color: t0.c }}>{mask(t0.t) || ' '}</span>
        </div>
        {ids.map((b) => {
          const v = val(b), d = dayLine(day(b));
          return (
            <button key={b} type="button" className="bare sw-ovb" onClick={() => pickAccount(b)}
              style={{ display: 'flex', flexDirection: 'column', gap: 2, paddingLeft: 28, borderLeft: HAIR }}>
              <span style={{ fontSize: 13, color: C.ink2 }}>{BOOK_NAME[b]} ›</span>
              <span style={{ fontSize: 34, lineHeight: '40px', fontWeight: 700, letterSpacing: '-.025em' }}>
                {v != null ? <CountUp v={mask(dollars(v))} /> : ' '}
              </span>
              <span style={{ fontSize: 14, fontWeight: 600, color: d.c }}>{mask(d.t) || ' '}</span>
            </button>
          );
        })}
      </div>

      {ov && (
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, paddingBottom: 12 }}>
            <span style={{ fontSize: 20, fontWeight: 600 }}>Six checks</span>
            <Seg<'wk'> label="Period" items={[['wk', 'This week']]} value={per} onChange={setPer} />
          </div>
          <div className="tnum" style={{ display: 'grid', gridTemplateColumns: GRID, gap: 16, padding: '10px 0 8px', borderTop: HAIR_S,
            fontSize: 12, fontWeight: 600, letterSpacing: '.05em', textTransform: 'uppercase', color: C.ink2 }}>
            <span>Check</span>{ids.map((b) => <span key={b}>{BOOK_NAME[b]}</span>)}<span />
          </div>
          {CHECKS.filter(([n]) => byName.has(n)).map(([n, s]) => {
            const c = byName.get(n)!, watch = String(c.status ?? '').toLowerCase().startsWith('watch'), zc = watch ? C.orange : C.green;
            return (
              <div key={n} className="tnum" style={{ display: 'grid', gridTemplateColumns: GRID, gap: 16, alignItems: 'center', padding: '14px 0', borderTop: HAIR }}>
                <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                  <span style={{ fontSize: 16, fontWeight: 600 }}>{n}</span>
                  <span style={{ fontSize: 12, color: C.ink2 }}>{s}</span>
                </span>
                {ids.map((b) => <span key={b} style={{ fontSize: 15 }}>{mask(cell(n, b))}</span>)}
                <span style={{ justifySelf: 'start', borderRadius: 999, padding: '3px 10px', fontSize: 12, fontWeight: 600, color: zc,
                  boxShadow: `inset 0 0 0 1px ${zc}` }}>{watch ? 'Watch' : 'On track'}</span>
              </div>
            );
          })}
          <span style={{ paddingTop: 12, fontSize: 12, lineHeight: '18px', color: C.ink2 }}>{mask(foot)}</span>
        </div>
      )}

      <Allocation sides={ids.map((b) => ({ id: b, rows: rows[b] }))} />
      <style>{`.sw .sw-ovb:hover{opacity:.85}`}</style>
    </div>
  );
}
