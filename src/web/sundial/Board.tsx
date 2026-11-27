// The Sundial board (handoff 2026-11-27 README §2, SunnyIncomeBoard.dc.html; 207a on the web, 207c narrow): five
// columns, each with one job, so each looks different (structure, weight and marks, never coloured words):
//   To sell          action: lighter cards, the largest figures; the plan dimmer until 3:45 PM; a big-drop card on top
//   Close            warning: small cards, a red dot, the kept % and "Day 2 of 2" or "Due now"
//   Working          calm: one quiet box a name, rows only
//   Expiring today   watch: a live clock, the distance, a price line with the strike in orange
//   Banked this week done: a stack a name, the total on top, tap to fan
// Every number, total and order comes from the server (sundial mode 'board'); this file only lays it out. Dark only,
// as the rest of the web. Under 960 px of content the columns become sections down the page (narrow).
import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { type J } from '../lib/data';
import { clock12, ny, useNY } from '../lib/clock';
import { signed, GREEN, RED, ORANGE, INK, INK2, GREY, CHIP_ON } from '../lib/focus';
import { Disc } from '../income/ui';

const BOX = '#212121', SELL = '#313131', PLAN = '#232323', E1 = '#1D1D1D', E2 = '#1A1A1A';
const TRK = 'rgba(255,255,255,.14)', L8 = 'rgba(255,255,255,.08)', L12 = 'rgba(255,255,255,.12)', DASH = 'rgba(255,255,255,.24)';
const RING = 'inset 0 0 0 1px rgba(255,255,255,.08)', SRING = 'inset 0 0 0 1px rgba(255,255,255,.14)', DRING = 'inset 0 0 0 1.5px rgba(255,255,255,.42)';
const FILLC = '#8C8C8C';

/* ── words and numbers (README §2.2) ── */
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const md = (d: string) => `${MO[Number(d.slice(5, 7)) - 1]} ${Number(d.slice(8, 10))}`;
const kfmt = (K: number) => (Number.isInteger(K) ? String(K) : K.toFixed(2));
const A = Math.abs;
/** Totals in whole K: $3K, $970. */
const kT = (x: number) => (A(x) >= 1000 ? `$${Math.round(A(x) / 1000)}K` : `$${Math.round(A(x)).toLocaleString('en-US')}`);
/** Card heroes with one decimal: $2.3K, $709. */
const kC = (x: number) => (A(x) >= 1000 ? `$${String(+(A(x) / 1000).toFixed(1))}K` : `$${Math.round(A(x)).toLocaleString('en-US')}`);
const sT = (x: number) => signed(Math.round(x), kT(x));
const sC = (x: number) => signed(Math.round(x), kC(x));
const contract = (q: number, K: number, ty: string) => `${q} $${kfmt(K)} ${ty}${q === 1 ? '' : 's'}`;
const sdW = (x: number | null | undefined) => (x == null ? '' : `${String(+(+x).toFixed(2))} SD`);
const hm12 = (hm: string) => { const h = Number(hm.slice(0, 2)), m = hm.slice(3, 5); return `${((h + 11) % 12) + 1}:${m} ${h < 12 ? 'AM' : 'PM'}`; };
const minsOf = (hm: string) => Number(hm.slice(0, 2)) * 60 + Number(hm.slice(3, 5));
const legsN = (n: number) => `${n} ${n === 1 ? 'leg' : 'legs'}`;
/** When a To sell card was last worked out and the stock price it used (Nik, 27 Nov: "Updated 8:45 AM ($149.36)",
    short). Before the final time it is worked out again every minute; after it, the time the plan locked at. */
const basisLine = (b: { price: number; at: string; locked: boolean }) => `Updated ${clock12(ny(new Date(b.at)))} ($${(+b.price).toFixed(2)})`;

/* ── motion (README §2.5, very subtle, none under Reduce Motion) ── */
type Anim = HTMLElement & { __ib?: 1 };
function useEntrance(root: React.RefObject<HTMLDivElement | null>, dep: unknown) {
  useEffect(() => {
    const r = root.current;
    if (!r || !r.animate) return;
    const rm = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    let n = 0;
    r.querySelectorAll<Anim>('[data-ib]').forEach((el) => {
      if (el.__ib) return; el.__ib = 1; if (rm) return;
      el.animate([{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1, transform: 'none' }],
        { duration: 460, delay: (+(el.getAttribute('data-ib') ?? 0)) * 70 + Math.min(n++, 8) * 30, easing: 'cubic-bezier(.2,.7,.2,1)', fill: 'backwards' });
    });
    r.querySelectorAll<Anim>('[data-ib-bar]').forEach((el) => {
      if (el.__ib) return; el.__ib = 1; if (rm) return;
      el.animate([{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], { duration: 800, delay: 260, easing: 'cubic-bezier(.2,.7,.2,1)', fill: 'backwards' });
    });
    r.querySelectorAll<Anim>('[data-ib-pulse]').forEach((el) => {
      if (el.__ib) return; el.__ib = 1; if (rm) return;
      el.animate([{ transform: 'scale(1)', opacity: 0.55 }, { transform: 'scale(2.8)', opacity: 0 }], { duration: 2200, iterations: Infinity, easing: 'ease-out' });
    });
  }, [root, dep]);
}

/* ── pieces ── */
const T13: CSSProperties = { fontSize: 13, lineHeight: '17px', fontWeight: 400, color: GREY };
const Logo = ({ t, size }: { t: string; size: number }) => <Disc t={t} size={size} fs={Math.max(6, size * 0.28)} />;
const NameRow = ({ t, nm }: { t: string; nm: string }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 2px' }}>
    <Logo t={t} size={20} /><span style={{ fontSize: 13, lineHeight: '16px', fontWeight: 500, color: GREY }}>{nm}</span>
  </div>
);
const Empty = ({ children }: { children: ReactNode }) => (
  <div style={{ padding: '14px 16px', borderRadius: 16, border: `1px dashed ${DASH}`, fontSize: 15, lineHeight: '20px', fontWeight: 400, color: GREY }}>{children}</div>
);
const RDot = ({ c, top }: { c: string; top?: number }) => <span aria-hidden="true" style={{ flex: 'none', width: 8, height: 8, borderRadius: '50%', marginTop: top, background: c }} />;
function Head({ title, sum, sub, ct }: { title: string; sum: string; sub?: string; ct: number }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 2, padding: '0 2px 12px', borderBottom: `1px solid ${L12}` }}>
      <h2 style={{ margin: 0, fontSize: ct, lineHeight: '26px', fontWeight: 700 }}>{title}</h2>
      <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 400, color: GREY }}>{sum}</span>
      {sub && <span style={T13}>{sub}</span>}
    </div>
  );
}
/** Done and New (Nik 27 Nov): what was sold today stays on the card, marked Done; what is still to sell is New. New is
    the ready-to-act mark (a green pill with a word), Done a quiet outlined one. */
function Tag({ k }: { k: 'New' | 'Done' }) {
  return (
    <span style={{ flex: 'none', display: 'inline-block', marginRight: 8, padding: '0 7px', borderRadius: 9, fontSize: 12, lineHeight: '18px', fontWeight: 500, verticalAlign: '.1em',
      background: k === 'New' ? GREEN : 'transparent', color: k === 'New' ? '#171717' : GREY, boxShadow: k === 'New' ? 'none' : 'inset 0 0 0 1px rgba(255,255,255,.22)' }}>{k}</span>
  );
}
function SellLeg({ l, many, tag }: { l: J; many: boolean; tag?: 'New' | 'Done' }) {
  const done = tag === 'Done';
  const meta = done
    ? [md(l.expiry), `sold at $${(+l.price).toFixed(2)}`, l.at ? clock12(ny(new Date(l.at))) : ''].filter(Boolean).join(' · ')
    : [md(l.expiry), sdW(l.sd), `$${(+l.price).toFixed(2)} each`].filter(Boolean).join(' · ');
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: '2px 12px', alignItems: 'baseline' }}>
      <span style={{ fontSize: 16, lineHeight: '21px', fontWeight: 500, color: done ? INK2 : INK }}>{contract(l.qty, l.strike, l.type)}</span>
      <span style={{ fontSize: 16, lineHeight: '21px', fontWeight: 500, textAlign: 'right', color: done ? INK2 : INK }}>{many ? sC(l.credit) : ''}</span>
      <span style={{ gridColumn: '1 / -1', ...T13 }}>{tag && <Tag k={tag} />}{meta}</span>
      {l.keep && (
        <span style={{ gridColumn: '1 / -1', display: 'flex', alignItems: 'baseline', gap: 8, marginTop: 4 }}>
          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 500 }}>Keep {l.keep.qty}</span>
          <span style={T13}>{l.keep.total} on {md(l.expiry)}</span>
        </span>
      )}
    </div>
  );
}

export function Board({ data, narrow, tk, setTk, mask }: { data: J; narrow: boolean; tk: string; setTk: (t: string) => void; mask: (s: string) => string }) {
  const root = useRef<HTMLDivElement>(null);
  const n = useNY(1000);
  const [fan, setFan] = useState<Record<string, boolean>>({});
  const names: { t: string; name: string }[] = useMemo(() => data?.names ?? [], [data]);
  const nm = useMemo(() => Object.fromEntries(names.map((x) => [x.t, x.name])), [names]);
  const nameOf = (t: string) => nm[t] ?? t;
  useEntrance(root, data);

  const final = !!data?.final, closeAt: string = data?.closeAt ?? '16:00', finalAt: string = data?.finalAt ?? '15:45';
  // The clock: h:mm to the close, the ring empties over the session; the header's time is the same clock.
  const nowS = n.mins * 60 + new Date().getSeconds(), closeS = minsOf(closeAt) * 60, openS = 9.5 * 3600;
  const left = Math.max(0, closeS - nowS), mL = Math.ceil(left / 60);
  const clockT = `${Math.floor(mL / 60)}:${String(mL % 60).padStart(2, '0')}`;
  const ring = Math.max(0, Math.min(1, left / Math.max(1, closeS - openS)));
  const asOf = data?.asOf ? ny(new Date(data.asOf)) : n;
  const who = `${data?.book ?? ''} · ${asOf.wd} ${MO[asOf.month - 1]} ${asOf.day} · ${clock12(n)}`;

  const S = narrow
    ? { h1: 30, hero: 48, ct: 22, cols: 'minmax(0,1fr)', cg: 32, minW: 0, ox: 'visible' as const, gap: 28 }
    : { h1: 32, hero: 64, ct: 20, cols: 'repeat(5,minmax(200px,1fr))', cg: 16, minW: 1080, ox: 'auto' as const, gap: 36 };

  const toSell = data?.toSell ?? { total: 0, cards: [] }, drops: J[] = data?.drops ?? (data?.drop ? [data.drop] : []);
  const close = data?.close ?? { total: 0, cards: [] }, working = data?.working ?? { total: 0, groups: [] };
  const expiring = data?.expiring ?? { total: 0, cards: [] }, banked = data?.banked ?? { total: 0, groups: [] };
  const byName = (cards: J[]) => { const o: { t: string; items: J[] }[] = []; for (const c of cards) { let g = o.find((x) => x.t === c.t); if (!g) o.push(g = { t: c.t, items: [] }); g.items.push(c); } return o; };

  const sellN = toSell.cards.length + drops.length;
  // What is still to sell (New), apart from what was already sold today (Done)
  const newN = toSell.cards.reduce((a: number, c: J) => a + c.legs.length, 0) + drops.length;
  const chips = [{ t: 'all', l: 'All' }, ...names.map((x) => ({ t: x.t, l: x.name }))];
  return (
    <div ref={root} className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: S.gap, color: INK }}>
      {/* Header: the title and whose book, the name chips, one hero (README §2.1: nothing else) */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: '6px 16px', flexWrap: 'wrap' }}>
          <h1 style={{ margin: 0, fontSize: S.h1, lineHeight: 1.1, fontWeight: 700, letterSpacing: '-.01em' }}>Sundial</h1>
          {data && <span style={{ ...T13, lineHeight: '16px' }}>{who}</span>}
        </div>
        <div role="group" aria-label="Names" className="noscroll"
          style={{ display: 'flex', gap: 8, flexWrap: narrow ? 'nowrap' : 'wrap', overflowX: narrow ? 'auto' : 'visible' }}>
          {chips.map((c) => {
            const on = tk === c.t;
            return (
              <button key={c.t} type="button" aria-pressed={on} onClick={() => setTk(c.t)} className="bare"
                style={{ flex: 'none', height: 36, padding: '0 16px', borderRadius: 18, background: on ? CHIP_ON : 'transparent', boxShadow: on ? 'none' : 'inset 0 0 0 1px rgba(255,255,255,.2)', color: INK, fontSize: 15, lineHeight: '20px', fontWeight: 500, cursor: 'pointer' }}>
                {c.l}
              </button>
            );
          })}
        </div>
        {data && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <span style={{ fontSize: 13, lineHeight: '16px', fontWeight: 500, color: GREY }}>{data.month?.label}</span>
            <span style={{ fontSize: S.hero, lineHeight: 1, fontWeight: 700, letterSpacing: '-.02em' }}>{mask(sT(data.month?.amount ?? 0))}</span>
          </div>
        )}
      </div>

      {data && (
        <div className="noscroll" style={{ overflowX: S.ox, margin: narrow ? 0 : '0 -4px', padding: narrow ? 0 : '0 4px 4px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: S.cols, gap: S.cg, alignItems: 'start', minWidth: S.minW }}>

            {/* To sell */}
            <section aria-label="To sell" style={{ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 }}>
              <Head title="To sell" ct={S.ct} sum={newN ? mask(sT(toSell.total)) : sellN ? 'All sold' : 'None'} sub={!final && newN ? `Plan · final at ${hm12(finalAt)}` : undefined} />
              {drops.map((d) => (
                <div key={'drop' + d.t} data-ib="0" style={{ padding: '16px 18px 18px', borderRadius: 18, background: SELL, boxShadow: DRING, display: 'flex', flexDirection: 'column', gap: 14 }}>
                  <span style={{ fontSize: 13, lineHeight: '16px', fontWeight: 500, color: GREY }}>Big drop · {clock12(ny(new Date(d.at)))}{d.price ? ` · $${(+d.price).toFixed(2)}` : ''}</span>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <Logo t={d.t} size={32} />
                    <span style={{ flex: 1, minWidth: 0, fontSize: 17, lineHeight: '22px', fontWeight: 500 }}>{nameOf(d.t)}</span>
                    <span style={{ flex: 'none', fontSize: 32, lineHeight: '36px', fontWeight: 700, letterSpacing: '-.02em' }}>{mask(sC(d.credit))}</span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ position: 'relative', flex: 'none', width: 8, height: 8 }}>
                      <span data-ib-pulse="1" style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: GREEN }} />
                      <span style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: GREEN }} />
                    </span>
                    <span style={{ fontSize: 20, lineHeight: '24px', fontWeight: 700 }}>{d.line}</span>
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{d.legs.map((l: J, i: number) => <SellLeg key={i} l={l} many={d.legs.length > 1} />)}</div>
                </div>
              ))}
              {toSell.cards.map((c: J) => (
                <div key={c.t} data-ib="0" style={{ padding: '16px 18px 18px', borderRadius: 18, background: final ? SELL : PLAN, border: final ? 'none' : '1px dashed rgba(255,255,255,.26)', boxShadow: final ? SRING : 'none', display: 'flex', flexDirection: 'column', gap: 14 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <Logo t={c.t} size={32} />
                    <span style={{ flex: 1, minWidth: 0, fontSize: 17, lineHeight: '22px', fontWeight: 500 }}>{nameOf(c.t)}</span>
                    <span style={{ flex: 'none', fontSize: 32, lineHeight: '36px', fontWeight: 700, letterSpacing: '-.02em', color: final && c.legs.length ? INK : INK2 }}>{mask(sC(c.legs.length ? c.credit : (c.doneCredit ?? 0)))}</span>
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                    {c.legs.map((l: J, i: number) => <SellLeg key={'n' + i} l={l} many={c.legs.length + (c.done?.length ?? 0) > 1} tag={c.done?.length ? 'New' : undefined} />)}
                    {(c.done ?? []).map((l: J, i: number) => <SellLeg key={'d' + i} l={l} many={c.legs.length + c.done.length > 1} tag="Done" />)}
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 3, paddingTop: 12, borderTop: `1px solid ${L8}` }}>
                    <span style={T13}>{c.reason}</span>
                    <span style={T13}>{c.safe}</span>
                    {c.basis && <span style={T13}>{basisLine(c.basis)}</span>}
                  </div>
                </div>
              ))}
              {!sellN && <Empty>None today</Empty>}
            </section>

            {/* Close */}
            <section aria-label="Close" style={{ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 }}>
              <Head title="Close" ct={S.ct} sum={close.cards.length ? `${mask(kT(close.total))} to buy back` : 'None'} />
              {byName(close.cards).map((g) => (
                <div key={g.t} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <NameRow t={g.t} nm={nameOf(g.t)} />
                  {g.items.map((c: J) => (
                    <div key={`${c.expiry}${c.strike}`} data-ib="1" style={{ padding: '12px 14px 14px', borderRadius: 14, background: BOX, boxShadow: RING, display: 'flex', flexDirection: 'column', gap: 10 }}>
                      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 7 }}>
                        <RDot c={RED} top={6} />
                        <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 500 }}>{contract(c.qty, c.strike, c.type)}</span>
                          <span style={T13}>{md(c.expiry)} · ${(+c.soldAt).toFixed(2)} → ${(+c.now).toFixed(2)}</span>
                        </span>
                      </div>
                      <span style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                        <span style={{ fontSize: 24, lineHeight: '28px', fontWeight: 700, letterSpacing: '-.01em' }}>{c.keptPct}%</span>
                        <span style={{ ...T13, lineHeight: '16px' }}>kept</span>
                      </span>
                      <span style={{ position: 'relative', height: 6, borderRadius: 3, background: TRK, overflow: 'hidden', display: 'flex' }}>
                        <span data-ib-bar="1" style={{ width: `${Math.max(0, Math.min(100, c.keptPct))}%`, background: FILLC, transformOrigin: '0 50%' }} />
                        <span style={{ position: 'absolute', left: '50%', top: 0, bottom: 0, width: 2, marginLeft: -1, background: BOX }} />
                      </span>
                      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: '4px 10px', flexWrap: 'wrap' }}>
                        <span style={{ fontSize: 14, lineHeight: '19px', fontWeight: 500 }}>Buy back {mask(kC(c.buyBack))}</span>
                        <span style={T13}>{c.due ? 'Due now' : `Day ${c.day} of ${c.of} · ${hm12(c.deadline)}`}</span>
                      </div>
                    </div>
                  ))}
                </div>
              ))}
            </section>

            {/* Working */}
            <section aria-label="Working" style={{ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 }}>
              <Head title="Working" ct={S.ct} sum={working.groups.length ? `${mask(kT(working.total))} to go` : 'None'} />
              {working.groups.map((g: J) => (
                <div key={g.t} data-ib="2" style={{ display: 'flex', flexDirection: 'column', padding: '2px 14px 3px', borderRadius: 16, boxShadow: RING }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 0 9px' }}>
                    <Logo t={g.t} size={20} />
                    <span style={{ flex: 1, minWidth: 0, fontSize: 14, lineHeight: '19px', fontWeight: 500, color: INK2 }}>{nameOf(g.t)}</span>
                    <span style={{ ...T13, lineHeight: '16px' }}>{legsN(g.legs.length)}</span>
                  </div>
                  {g.legs.map((r: J) => (
                    <div key={`${r.type}${r.strike}${r.expiry}`} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) 56px', gap: '4px 12px', alignItems: 'center', padding: '9px 0 10px', borderTop: `1px solid ${L8}` }}>
                      <span style={{ minWidth: 0, fontSize: 14, lineHeight: '19px', fontWeight: 500, color: INK2 }}>{contract(r.qty, r.strike, r.type)}</span>
                      <span style={{ fontSize: 14, lineHeight: '19px', fontWeight: 500, color: INK2, textAlign: 'right' }}>{r.keptPct < 0 ? '−' : ''}{A(r.keptPct)}%</span>
                      <span style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0, ...T13 }}>
                        <span>{md(r.expiry)} · {r.daysLeft} {r.daysLeft === 1 ? 'day' : 'days'}{r.itm ? ' ·' : r.sd != null ? ` · ${sdW(r.sd)}` : ''}</span>
                        {r.itm && <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}><RDot c={RED} />In the money</span>}
                      </span>
                      <span style={{ height: 3, borderRadius: 2, background: TRK, overflow: 'hidden', display: 'flex' }}>
                        <span data-ib-bar="1" style={{ width: `${Math.max(0, Math.min(100, r.keptPct))}%`, background: FILLC, transformOrigin: '0 50%' }} />
                      </span>
                    </div>
                  ))}
                </div>
              ))}
              {!working.groups.length && <Empty>None</Empty>}
            </section>

            {/* Expiring today */}
            <section aria-label="Expiring today" style={{ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 }}>
              <Head title="Expiring today" ct={S.ct} sum={expiring.cards.length ? (expiring.total ? `${mask(kT(expiring.total))} to buy back` : legsN(expiring.cards.length)) : 'None'} />
              {byName(expiring.cards).map((g) => (
                <div key={g.t} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <NameRow t={g.t} nm={nameOf(g.t)} />
                  {g.items.map((c: J) => {
                    const lo = c.line?.lo ?? Math.min(c.price, c.strike), hi = c.line?.hi ?? Math.max(c.price, c.strike), w = Math.max(1e-9, hi - lo);
                    const kP = ((c.strike - lo) / w) * 100, pP = ((c.price - lo) / w) * 100, a = Math.min(kP, pP), b = Math.max(kP, pP);
                    return (
                      <div key={`${c.type}${c.strike}`} data-ib="3" style={{ padding: '14px 16px 16px', borderRadius: 16, background: BOX, boxShadow: RING, display: 'flex', flexDirection: 'column', gap: 12 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                          <svg width="16" height="16" viewBox="0 0 16 16" style={{ flex: 'none' }} aria-hidden="true">
                            <circle cx="8" cy="8" r="6" fill="none" stroke={TRK} strokeWidth="2" />
                            <circle cx="8" cy="8" r="6" fill="none" stroke={INK} strokeWidth="2" strokeLinecap="round" strokeDasharray={`${(37.7 * ring).toFixed(2)} 40`} transform="rotate(-90 8 8)" />
                          </svg>
                          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 500 }}>{clockT}</span>
                          <span style={{ ...T13, lineHeight: '16px' }}>to the close</span>
                        </div>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 500 }}>{contract(c.qty, c.strike, c.type)}</span>
                          <span style={T13}>{md(c.expiry)} · {nameOf(c.t)} ${(+c.price).toFixed(2)}</span>
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                          {c.itm && <RDot c={RED} />}
                          <span style={{ fontSize: 24, lineHeight: '28px', fontWeight: 700, letterSpacing: '-.01em' }}>${(+c.distance).toFixed(2)}</span>
                          <span style={{ ...T13, lineHeight: '16px' }}>{c.itm ? 'in the money' : c.sd != null ? `away · ${sdW(c.sd)}` : 'away'}</span>
                        </div>
                        <div aria-hidden="true" style={{ position: 'relative', height: 32 }}>
                          <span style={{ position: 'absolute', left: 0, right: 0, top: 6, height: 2, borderRadius: 1, background: TRK }} />
                          <span style={{ position: 'absolute', top: 6, height: 2, left: `${a}%`, width: `${b - a}%`, background: GREY }} />
                          <span style={{ position: 'absolute', top: 0, left: `${kP}%`, width: 2, height: 14, marginLeft: -1, borderRadius: 1, background: ORANGE }} />
                          <span style={{ position: 'absolute', top: 2, left: `${pP}%`, width: 10, height: 10, marginLeft: -5, borderRadius: '50%', background: INK }} />
                          <span style={{ position: 'absolute', top: 18, left: `${kP}%`, transform: 'translateX(-50%)', fontSize: 12, lineHeight: '14px', color: GREY, whiteSpace: 'nowrap' }}>${kfmt(c.strike)}</span>
                        </div>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, paddingTop: 10, borderTop: `1px solid ${L8}` }}>
                          <span style={{ ...T13, lineHeight: '16px' }}>At the close</span>
                          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 500 }}>{c.outcome}</span>
                          {c.buyBack != null && (
                            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: '4px 10px', flexWrap: 'wrap', marginTop: 8 }}>
                              <span style={{ fontSize: 14, lineHeight: '19px', fontWeight: 500 }}>Buy back {mask(kC(c.buyBack))}</span>
                              <span style={T13}>Before {hm12(closeAt)}</span>
                            </div>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              ))}
              {!expiring.cards.length && <Empty>None today</Empty>}
            </section>

            {/* Banked this week */}
            <section aria-label="Banked this week" style={{ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 }}>
              <Head title="Banked this week" ct={S.ct} sum={banked.groups.length ? mask(sT(banked.total)) : 'None'} />
              {banked.groups.map((b: J) => {
                const o = !!fan[b.t], nL = b.legs.length;
                return (
                  <div key={b.t} data-ib="4" style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 2px' }}>
                      <Logo t={b.t} size={24} />
                      <span style={{ flex: 1, minWidth: 0, fontSize: 15, lineHeight: '20px', fontWeight: 500 }}>{nameOf(b.t)}</span>
                      <span style={{ flex: 'none', fontSize: 28, lineHeight: '32px', fontWeight: 700, letterSpacing: '-.01em' }}>{mask(sC(b.total))}</span>
                    </div>
                    <button type="button" className="bare sw-stack" onClick={() => setFan((f) => ({ ...f, [b.t]: !f[b.t] }))} aria-expanded={o} aria-label={`${nameOf(b.t)}, ${legsN(nL)}`}
                      style={{ display: 'flex', flexDirection: 'column', width: '100%', textAlign: 'left', cursor: 'pointer' }}>
                      {b.legs.map((l: J, i: number) => (
                        <div key={`${l.type}${l.strike}${l.expiry}${l.how}`}
                          style={{ position: 'relative', zIndex: 10 - i, boxSizing: 'border-box', height: 59, marginTop: i === 0 ? 0 : o ? 8 : i < 3 ? -53 : -59,
                            transform: o || i === 0 ? 'scale(1)' : i === 1 ? 'scale(.95)' : 'scale(.9)', transformOrigin: '50% 100%', opacity: o || i < 3 ? 1 : 0,
                            padding: '10px 12px 11px', borderRadius: 12, background: o || i === 0 ? BOX : i === 1 ? E1 : E2, boxShadow: RING,
                            transition: 'margin-top .45s cubic-bezier(.32,.72,0,1),transform .45s cubic-bezier(.32,.72,0,1),opacity .3s ease,background-color .3s ease' }}>
                          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: '2px 10px', alignItems: 'baseline', opacity: o || i === 0 ? 1 : 0, transition: 'opacity .25s ease' }}>
                            <span style={{ minWidth: 0, fontSize: 14, lineHeight: '19px', fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{contract(l.qty, l.strike, l.type)}</span>
                            <span style={{ fontSize: 14, lineHeight: '19px', fontWeight: 500, textAlign: 'right' }}>{mask(sC(l.kept))}</span>
                            <span style={{ gridColumn: '1 / -1', ...T13 }}>{md(l.expiry)} · {l.how}</span>
                          </div>
                        </div>
                      ))}
                    </button>
                    <span style={{ padding: '0 2px', ...T13, lineHeight: '16px' }}>{o ? 'Fold' : nL > 1 ? legsN(nL) : ''}</span>
                  </div>
                );
              })}
              {!banked.groups.length && <Empty>None yet</Empty>}
            </section>
          </div>
        </div>
      )}
    </div>
  );
}
