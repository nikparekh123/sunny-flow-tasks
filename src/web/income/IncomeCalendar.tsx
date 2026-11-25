// The Income calendar (handoff 2026-11-24 late §1.3; SunnyIncomeCal head=false view="w" quiet="fold", as Current
// Web mounts it under the realized banner). Top to bottom, 18 px apart:
//   the ticker strip, like the account strip (All, then Nicolay's names, a hairline, then Sunny's; a logo in each pill;
//   a dot red when a rung is in the money, green when one is ready to roll) ·
//   the status line (the name or All on the left; on the right one big count of what needs you, red when anything is
//   in the money, else green, "in the money · to roll" grey under it; "All quiet" with the nearest roll) ·
//   the range (‹ › on Week, which walks the four weeks; Week | Month) ·
//   the grid, Mon to Fri: Week one tall week, Month four. Today a white circle, past and closed days faded.
// No dollar figures, so privacy does not touch it. The ticker (per account), the week and the view last the session.
// The focus look (handoff 2026-11-25-focus §2): the words neutral (the strip's dots and the tiles' rings keep the red
// and green), a lost % takes a −, the day heads plain grey words.
import { Fragment, useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import type { BookId, J } from '../lib/data';
import { ny } from '../lib/clock';
import { BOOK_NAME } from '../components/AccountMenu';
import { label as LABEL } from '../lib/focus';
import { signBy, wordOf } from '../lib/format';
import { Disc } from './ui';
import { GRN, ln, MU, ONW, QT, RED, W, type Income, type IncName } from './model';
import { calOf, closedDays, contentOf, ctxSub, dayAria, dayLabel, daysOf, DN, rangeOf, statusOf, type Content, type Day, type View } from './calendar';

const TRK = 'rgba(128,128,128,.24)', THUMB = 'rgba(255,255,255,.2)', TH_SH = 'inset 0 0 0 .5px rgba(255,255,255,.22),0 2px 8px rgba(0,0,0,.35)';
const TILE = 'rgba(255,255,255,.04)';
const pill = (on: boolean): CSSProperties => ({ fontWeight: 500, color: on ? W : MU, background: on ? THUMB : 'transparent', boxShadow: on ? TH_SH : 'none', transition: 'background .2s,color .2s' });
const WRAP = { textWrap: 'pretty' } as CSSProperties;

/* The session's picks (README §4): the ticker with the account it was picked on, the week and the view. */
const KEY = 'sw-inc-cal';
interface Saved { b?: string; t?: string; w?: number; v?: View }
const load = (): Saved => { try { return JSON.parse(sessionStorage.getItem(KEY) || '{}') || {}; } catch { return {}; } };
const keep = (s: Saved) => { try { sessionStorage.setItem(KEY, JSON.stringify(s)); } catch { /* private window */ } };

export function IncomeCalendar({ inc, payload, book }: { inc: Income; payload: J; book: BookId }) {
  const [sv, setSv] = useState<Saved>(load);
  const set = (p: Saved) => setSv((s) => { const n = { ...s, ...p }; keep(n); return n; });
  const together = book === 'T', names = inc.names;
  // A ticker picked on another account opens on All (the design resets it when the account changes).
  const one: IncName | null = sv.b === book && sv.t && sv.t !== 'All' ? names.find((n) => n.t === sv.t) ?? null : null;
  const tk = one ? one.t : 'All';
  const view: View = sv.v === 'm' ? 'm' : 'w', week = view === 'w', wk = Math.max(0, Math.min(3, sv.w ?? 0));
  const pick = (t: string) => set({ b: book, t });

  const today = inc.today || ny().date;
  const cal = useMemo(() => calOf(inc), [inc]);
  const closed = useMemo(() => closedDays(payload, inc), [payload, inc]);
  const days = useMemo(() => daysOf(today, closed), [today, closed]);
  const scope = one ? [one] : names;
  const st = statusOf(inc, scope, one);
  const rg = rangeOf(days, view, wk, today);
  const weeks = (week ? [wk] : [0, 1, 2, 3]).map((w) => days.filter((x) => x.w === w));

  // The strip: All, then each account's names (Together: Nicolay's, a hairline, Sunny's).
  const groups = together
    ? [names.filter((n) => n.books.includes('Nicolay')), names.filter((n) => !n.books.includes('Nicolay'))].filter((g) => g.length)
    : names.length ? [names] : [];
  const flags = (n: IncName) => {
    const rs = inc.rungs.filter((r) => r.t === n.t);
    return { im: rs.some((r) => r.st === 'itm'), rl: rs.some((r) => r.st === 'roll') };
  };
  const ctxT = one ? (one.co ? `${one.t} · ${one.co}` : one.t) : together ? 'All names' : `${BOOK_NAME[book]}’s names`;

  // Keep the picked pill in view when a name line opens it.
  const strip = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = strip.current?.querySelector<HTMLElement>('[aria-checked="true"]');
    const box = strip.current;
    if (!el || !box) return;
    const l = el.offsetLeft, r = l + el.offsetWidth;
    if (l < box.scrollLeft || r > box.scrollLeft + box.clientWidth) box.scrollTo({ left: Math.max(0, l - 12) });
  }, [tk]);

  // A plain function, not a component: the pills keep their buttons (and focus) across renders.
  const pillEl = (k: string, t: string, n: IncName | null) => {
    const on = tk === k, f = n ? flags(n) : null;
    return (
      <button key={k} type="button" role="radio" aria-checked={on} className="bare sw-ic-p" onClick={() => pick(k)}
        aria-label={n ? `${n.co || n.t}${f!.im ? ', in the money' : f!.rl ? ', needs you' : ''}` : 'All names'}
        style={{ flex: 'none', height: 36, padding: `0 13px 0 ${n ? 5 : 15}px`, borderRadius: 999, display: 'flex', alignItems: 'center', gap: 7,
          fontSize: 13, lineHeight: 1, ...pill(on) }}>
        {n && <Disc t={n.t} size={26} fs={6} />}
        <span>{t}</span>
        {f && (f.im || f.rl) && <span aria-hidden="true" style={{ flex: 'none', width: 7, height: 7, borderRadius: '50%', background: f.im ? RED : GRN }} />}
      </button>
    );
  };

  return (
    <div role="region" aria-label="Income calendar" className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 18, minWidth: 0 }}>
      <div ref={strip} role="radiogroup" aria-label="Ticker" className="noscroll"
        style={{ alignSelf: 'flex-start', maxWidth: '100%', display: 'flex', alignItems: 'center', gap: 2, padding: 3, borderRadius: 999, background: TRK, overflowX: 'auto' }}>
        {pillEl('All', 'All', null)}
        {groups.map((g, i) => (
          <Fragment key={i}>
            <span aria-hidden="true" style={{ flex: 'none', width: 1, height: 20, margin: '0 6px', background: ln(0.16) }} />
            {g.map((n) => pillEl(n.t, n.t, n))}
          </Fragment>
        ))}
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '12px 20px', flexWrap: 'wrap', padding: '16px 0',
        borderTop: `1px solid ${ln(0.08)}`, borderBottom: `1px solid ${ln(0.08)}` }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, flex: '1 1 0', minWidth: 0 }}>
          {one && <Disc t={one.t} size={44} fs={9} />}
          <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
            <span style={{ fontSize: 20, lineHeight: '26px', fontWeight: 700, letterSpacing: '-.01em' }}>{ctxT}</span>
            <span style={{ fontSize: 13, lineHeight: '18px', color: MU, ...WRAP }}>{ctxSub(one, scope, together)}</span>
          </span>
        </div>
        <div style={{ flex: 'none', display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 2, textAlign: 'right' }}>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
            {st.big > 0 && <span style={{ fontSize: 34, lineHeight: 1.12, fontWeight: 800, letterSpacing: '-.03em', color: wordOf(st.c, 34) }}>{st.big}</span>}
            <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 500, color: st.wc }}>{st.w}</span>
          </span>
          <span style={{ fontSize: 13, lineHeight: '18px', color: MU }}>{st.sub}</span>
        </div>
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '10px 16px', flexWrap: 'wrap' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
          {week && (
            <div style={{ display: 'flex', gap: 6 }}>
              {([['Week before', '‹', wk === 0, wk - 1], ['Week after', '›', wk === 3, wk + 1]] as const).map(([l, g, off, to]) => (
                <button key={l} type="button" aria-label={l} disabled={off} className="bare sw-ic-a" onClick={() => set({ w: to })}
                  style={{ width: 32, height: 32, borderRadius: '50%', background: TRK, display: 'flex', alignItems: 'center', justifyContent: 'center',
                    fontSize: 18, lineHeight: 1, color: W, opacity: off ? 0.35 : undefined, cursor: off ? 'default' : 'pointer' }}>{g}</button>
              ))}
            </div>
          )}
          <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
            <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 500, whiteSpace: 'nowrap' }}>{rg.t}</span>
            <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>{rg.s}</span>
          </span>
        </div>
        <div role="radiogroup" aria-label="Week or month" style={{ display: 'flex', padding: 2, borderRadius: 999, background: TRK }}>
          {([['w', 'Week'], ['m', 'Month']] as const).map(([k, l]) => (
            <button key={k} type="button" role="radio" aria-checked={view === k} className="bare" onClick={() => set({ v: k })}
              style={{ minWidth: 76, height: 30, padding: '0 12px', borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, ...pill(view === k) }}>{l}</button>
          ))}
        </div>
      </div>

      <div role="grid" aria-label={`Income calendar, ${ctxT}, ${rg.t}`} style={{ borderRadius: 20, background: 'rgba(255,255,255,.04)', boxShadow: `inset 0 0 0 1px ${ln(0.08)}`, overflow: 'hidden' }}>
        <div role="row" style={{ display: 'grid', gridTemplateColumns: 'repeat(5,minmax(0,1fr))', borderBottom: `1px solid ${ln(0.08)}` }}>
          {DN.map((l) => (
            <span key={l} role="columnheader" style={{ padding: '10px 14px', ...LABEL, lineHeight: '16px' }}>{l}</span>
          ))}
        </div>
        {weeks.map((ws, wi) => (
          <div key={ws[0].d} role="row" style={{ display: 'grid', gridTemplateColumns: 'repeat(5,minmax(0,1fr))', borderBottom: wi === weeks.length - 1 ? 'none' : `1px solid ${ln(0.08)}` }}>
            {ws.map((x) => <Cell key={x.d} x={x} label={dayLabel(x, days, week)} week={week} ct={contentOf(cal, scope, one, x, week, true)} open={pick} />)}
          </div>
        ))}
      </div>
      <style>{'.sw .sw-ic-p:hover{opacity:.85}.sw .sw-ic-a:not(:disabled):hover{opacity:.8}.sw .sw-ic-r:hover{opacity:.75}'}</style>
    </div>
  );
}

/** One day: its date (today a white circle), then its rungs (one ticker) or a line a name (All), the folded line and
    the dashed landing day. */
function Cell({ x, label, week, ct, open }: { x: Day; label: string; week: boolean; ct: Content; open: (t: string) => void }) {
  return (
    <div role="gridcell" aria-label={dayAria(x, ct)}
      style={{ minWidth: 0, minHeight: week ? 440 : 150, padding: '10px 12px 14px', borderRight: x.i === 4 ? 'none' : `1px solid ${ln(0.08)}`, background: x.today ? ln(0.03) : 'transparent' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0, opacity: x.past || x.closed ? 0.45 : 1 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ minWidth: 26, height: 26, padding: '0 7px', borderRadius: 13, background: x.today ? W : 'transparent', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 13, lineHeight: 1, fontWeight: 500, color: x.today ? ONW : x.past ? MU : W, whiteSpace: 'nowrap' }}>{label}</span>
          {x.today && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 400 }}>Today</span>}
          {x.closed && <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 400, color: MU }}>Closed</span>}
        </div>
        {ct.tiles.map((l) => (
          <div key={l.k} role="group" aria-label={l.aria}
            style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, padding: '10px 12px 11px', borderRadius: 14, background: TILE, boxShadow: l.ring }}>
            <span style={{ fontSize: 13, lineHeight: '18px', color: MU, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{l.nm}</span>
            {l.big && (
              <span style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                <span style={{ fontSize: 30, lineHeight: 1.12, fontWeight: 800, letterSpacing: '-.03em', color: wordOf(l.bc, 30), whiteSpace: 'nowrap' }}>{l.big}</span>
                <span style={{ fontSize: 13, lineHeight: '18px', color: MU }}>{l.bw}</span>
              </span>
            )}
            <span aria-hidden="true" style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              <span style={{ fontWeight: 400, color: W }}>{l.prem[0]}</span> premium · <span style={{ fontWeight: 400, color: W }}>{l.prem[1]}</span> to collect
            </span>
            {l.act && <span style={{ paddingTop: 2, fontSize: 13, lineHeight: '18px', fontWeight: 400, color: wordOf(l.bc, 13), ...WRAP }}>{l.act}</span>}
            {l.sub && <span style={{ fontSize: 12, lineHeight: '16px', color: MU, ...WRAP }}>{l.sub}</span>}
          </div>
        ))}
        {ct.rows.map((r) => (
          <button key={r.k} type="button" className="bare sw-ic-r" onClick={() => open(r.t)} aria-label={r.aria}
            style={{ display: 'grid', gridTemplateColumns: '24px minmax(0,1fr)', columnGap: 9, rowGap: 1, alignItems: 'center', margin: '0 -6px', padding: '5px 6px', borderRadius: 10 }}>
            <Disc t={r.t} size={24} fs={6} />
            {/* The ticker and the word share a line; in a narrow column the word drops under the ticker rather than
                cutting the ticker short. */}
            <span style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', columnGap: 9, minWidth: 0 }}>
              <span style={{ minWidth: 0, fontSize: 13, lineHeight: '18px', fontWeight: 400, color: r.tc, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.t}</span>
              <span style={{ marginLeft: 'auto', fontSize: 14, lineHeight: '18px', fontWeight: 500, color: wordOf(r.wc, 14), whiteSpace: 'nowrap' }}>{signBy(r.wc, r.word)}</span>
            </span>
            {r.why && <span style={{ gridColumn: '2 / 3', fontSize: 12, lineHeight: '16px', color: MU, ...WRAP }}>{r.why}</span>}
          </button>
        ))}
        {ct.more && <span style={{ fontSize: 12, lineHeight: '16px', color: MU, ...WRAP }}>{ct.more}</span>}
        {ct.nx.map((z) => (
          <div key={z.k} style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0, padding: '8px 12px 9px', borderRadius: 14, border: `1px dashed ${ln(0.28)}` }}>
            <span style={{ fontSize: 12, lineHeight: '16px', color: MU, ...WRAP }}>{z.top}</span>
            <span style={{ fontSize: 14, lineHeight: '19px', fontWeight: 500, color: QT, ...WRAP }}>{z.main}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
