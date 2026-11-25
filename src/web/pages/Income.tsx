// The Income tab (handoff 2026-11-24 §1.4 and handoff-2026-11-24-income; SunnyIncome part="page" banner="bars"
// rung="line" card="split", as Income Web.dc.html draws it): every call and put sold for income, top to bottom:
//   the title and one grey line · the realized income banner (Banner.tsx) · the logo strip (a tap scrolls that name's
//   card to 96 px under the top and rings the logo; a dot only when the name needs you: red in the money, green to
//   roll) · the totals row (Left to earn, Kept so far, Collected, To roll, In the money) · a card a name, two a row
//   from 520 px each: the header (logo, ticker, company · cadence, on Together the account; price and today's move),
//   the small calendar, the delta line for a name that sells on several Fridays, then every rung as a row, nothing
//   folded (Nik: "I need to see all the positions").
// Every figure is the Home payload's `income` (sunny-home income.ts) for the account on screen; Together carries both.
import { useEffect, useMemo, useState, type CSSProperties } from 'react';
import { useHome, type J } from '../lib/data';
import { money } from '../lib/format';
import { useWeb } from '../lib/state';
import { Banner } from '../income/Banner';
import { cadWord, f2, flipOf, GRN, lineOf, ln, MU, readIncome, RED, rungsOf, W, type Income as Inc, type IncName } from '../income/model';
import { Calendar, Disc, FlipBody, RungRow } from '../income/ui';

const CARD: CSSProperties = { boxSizing: 'border-box', borderRadius: 20, background: 'rgba(255,255,255,.04)', boxShadow: `inset 0 0 0 1px ${ln(0.08)}`, minWidth: 0 };
const OFF = 96;

const reduced = () => typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

export default function Income() {
  const { book } = useWeb();
  const home = useHome(book);
  const payload: J = home.data?.payload;
  const inc = useMemo(() => readIncome(payload), [payload]);
  const [pk, setPk] = useState<string | null>(null);
  // A new account starts with no logo picked.
  useEffect(() => { setPk(null); }, [book]);
  const accounts = useMemo(() => {
    if (book !== 'T') return null;
    const sp: J[] = Array.isArray(payload?.split) ? payload.split : [];
    return sp.length > 1 ? sp.map((s) => String(s.name ?? s.id)) : ['Sunny', 'Nicolay'];
  }, [book, payload]);

  const go = (t: string) => {
    setPk(t);
    const el = document.querySelector(`[data-inc-card="${CSS.escape(t)}"]`);
    if (!el) return;
    window.scrollTo({ top: Math.max(0, window.scrollY + el.getBoundingClientRect().top - OFF), behavior: reduced() ? 'auto' : 'smooth' });
  };

  return (
    <div aria-busy={!payload} style={{ display: 'flex', flexDirection: 'column', gap: 18, maxWidth: 1240 }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <h1 style={{ margin: 0, fontSize: 28, lineHeight: '34px', fontWeight: 700, letterSpacing: '-.02em' }}>Income</h1>
        <span style={{ fontSize: 14, lineHeight: '20px', color: MU, textWrap: 'pretty', maxWidth: 820 } as CSSProperties}>
          Every call and put you sell for income. Green is ready to roll, red is in the money and yours to decide.
        </span>
      </div>
      {inc?.banner && <Banner b={inc.banner} today={inc.today} accounts={accounts} />}
      {inc && inc.names.length > 0 && <Strip inc={inc} pk={pk} go={go} />}
      {inc && inc.rungs.length > 0 && <Totals inc={inc} />}
      {inc && inc.names.length > 0 && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(min(100%,520px),1fr))', gap: 16, alignItems: 'start' }}>
          {inc.names.map((n) => <NameCard key={n.t} inc={inc} n={n} tg={book === 'T'} />)}
        </div>
      )}
    </div>
  );
}

/** The logo strip: 52 px white circles, the ticker under each, 8 apart, scrolling sideways. */
function Strip({ inc, pk, go }: { inc: Inc; pk: string | null; go: (t: string) => void }) {
  return (
    <div role="navigation" aria-label="Go to a name" className="noscroll" style={{ display: 'flex', gap: 8, overflowX: 'auto', margin: '0 -4px', padding: '2px 4px 4px' }}>
      {inc.names.map((n) => {
        const rs = inc.rungs.filter((r) => r.t === n.t), im = rs.some((r) => r.st === 'itm'), rl = rs.some((r) => r.st === 'roll'), on = pk === n.t;
        return (
          <button key={n.t} type="button" className="bare" onClick={() => go(n.t)} aria-pressed={on}
            aria-label={`Go to ${n.co || n.t}${im ? ', in the money' : rl ? ', ready to roll' : ''}`}
            style={{ flex: 'none', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, width: 64 }}>
            <Disc t={n.t} size={52} fs={11} ring={on ? `inset 0 0 0 2.5px ${W}, 0 0 0 2px #0A0C0B` : `inset 0 0 0 1px ${ln(0.1)}`} style={{ transition: 'box-shadow .2s ease' }}>
              {(im || rl) && <span style={{ position: 'absolute', right: 0, top: 0, width: 12, height: 12, borderRadius: '50%', background: im ? RED : GRN, boxShadow: '0 0 0 2px #0A0C0B' }} />}
            </Disc>
            <span style={{ fontSize: 13, lineHeight: '16px', fontWeight: on ? 700 : 500, color: on ? W : MU }}>{n.t}</span>
          </button>
        );
      })}
    </div>
  );
}

/** The totals row between hairlines: labels 12/16 uppercase, values 17/22 bold. */
function Totals({ inc }: { inc: Inc }) {
  const { mask } = useWeb();
  const t = inc.totals;
  const cells: [string, string, string][] = [
    ['Left to earn on these rungs', mask(money(t.left)), W],
    ['Kept so far', mask(money(t.kept)), t.kept < -0.5 ? RED : W],
    ['Collected', mask(money(t.collected)), W],
    ['To roll', String(t.roll), t.roll > 0 ? GRN : MU],
    ['In the money', String(t.itm), t.itm > 0 ? RED : MU],
  ];
  return (
    <div role="list" aria-label="All income" className="tnum"
      style={{ display: 'flex', flexWrap: 'wrap', gap: '10px 36px', padding: '12px 0', borderTop: `1px solid ${ln(0.08)}`, borderBottom: `1px solid ${ln(0.08)}` }}>
      {cells.map(([l, v, c]) => (
        <span key={l} role="listitem" style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, letterSpacing: '.05em', textTransform: 'uppercase', color: MU }}>{l}</span>
          <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 700, color: c, whiteSpace: 'nowrap' }}>{v}</span>
        </span>
      ))}
    </div>
  );
}

/** One name's card: the header, the calendar, the delta line, then every rung. */
function NameCard({ inc, n, tg }: { inc: Inc; n: IncName; tg: boolean }) {
  const f = flipOf(n), rs = rungsOf(inc, n.t);
  const sub = [n.co || n.t, tg && n.books.length ? n.books.join(' and ') : '', cadWord(n)].filter(Boolean).join(' · ');
  const chg = n.chg;
  return (
    <section data-inc-card={n.t} aria-label={`${n.co || n.t} income`} className="tnum"
      style={{ ...CARD, scrollMarginTop: OFF, display: 'flex', flexDirection: 'column', gap: 12, padding: '16px 18px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <Disc t={n.t} size={40} fs={10} />
        <span style={{ display: 'flex', flexDirection: 'column', gap: 1, flex: 1, minWidth: 0 }}>
          <span style={{ fontSize: 16, lineHeight: '20px', fontWeight: 700 }}>{n.t}</span>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{sub}</span>
        </span>
        <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 1 }}>
          <span style={{ fontSize: 16, lineHeight: '20px', fontWeight: 700 }}>{f2(n.px)}</span>
          {chg != null && (
            <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: chg < 0 ? RED : GRN, whiteSpace: 'nowrap' }}>
              {chg < 0 ? '↓' : '↑'} {Math.abs(chg).toFixed(1)}% today
            </span>
          )}
        </span>
      </div>
      {n.cal?.length > 0 && <Calendar t={n.t} cal={n.cal} />}
      {f && (
        <div style={{ padding: '8px 0', borderTop: `1px solid ${ln(0.08)}`, borderBottom: `1px solid ${ln(0.08)}` }}>
          <FlipBody f={f} size={26} />
        </div>
      )}
      {rs.length > 0 && (
        <div role="list" aria-label={`${n.t} rungs`} style={{ display: 'flex', flexDirection: 'column' }}>
          {rs.map((r) => <RungRow key={r.k} x={lineOf(r, false)} narrow={false} />)}
        </div>
      )}
    </section>
  );
}
