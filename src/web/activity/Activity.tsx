// Activity on the web (handoff 2026-11-18; Nik picked 161a + 161c on 16 Nov; SunnyActivity.dc.html `nav: 'panel'`,
// Current Web "a bell in the nav with today's unread count opens a panel on the right").
//   The bell: in the nav between To do and the privacy eye, 20 px, the muted grey, no glass, a 44 px target. A small
//   red badge counts today's unread lines; a red ! when IBKR has stopped. It follows the account on screen, and is not
//   drawn when the payload has no `activity` (an older build).
//   The panel: 440 wide from the right, full height over the page and a light scrim; Esc, ✕ or the scrim closes it,
//   focus goes into it and comes back to where it was. Reduce Motion: a fade, not a slide.
//   Top to bottom: Activity and the book, the IBKR sync line, All · IBKR · Levels · Moves, then Today, Yesterday,
//   Earlier this week and Last week, newest first. A pickup opens in place to its trades; a level or a move opens
//   Positions on that name. Any tap marks the line read. A Levels card row on Home opens the panel on its line.
import { useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent as ReactKey } from 'react';
import { createPortal } from 'react-dom';
import { useNavigate } from 'react-router-dom';
import { BOOK_NAME } from '../components/AccountMenu';
import { clock12, shortDate, useNY } from '../lib/clock';
import { useHome, type BookId } from '../lib/data';
import { C } from '../lib/format';
import { useWeb } from '../lib/state';
import { Segmented, useReducedMotion } from '../positions/ui';
import { daysOf, eventTime, groupOf, readActivity, syncWords, unreadToday, useReadKeys, type ActEvent, type Activity, type Group, type Kind } from './model';

const INK = C.ink, SUB = C.ink2, LN = '1px solid rgba(255,255,255,.08)';
/** The unread dot (the design's dark blue) and the badge red. */
const BLUE = '#0A84FF', BADGE = '#FF3B30';
const GROUPS: Group[] = ['today', 'yday', 'week', 'last'];
type Filter = 'all' | Kind;
const FILTERS: [Filter, string][] = [['all', 'All'], ['ibkr', 'IBKR'], ['lvl', 'Levels'], ['move', 'Moves']];
/** The design's dark glass for the sync line. */
const GLASS: CSSProperties = {
  background: 'linear-gradient(160deg,#323234 0%,#1F1F21 55%,#28282A 100%)',
  boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.12),inset 1px 1px 0 -.5px rgba(255,255,255,.18),0 10px 24px -10px rgba(0,0,0,.6)',
};

/** A company logo (public/logos/TICKER.png) at 74% of a white disc; the ticker when there is no logo file. */
export function Logo({ t, size }: { t: string; size: number }) {
  const [bad, setBad] = useState(false);
  useEffect(() => setBad(false), [t]);
  return (
    <span aria-hidden="true" style={{ flex: 'none', width: size, height: size, borderRadius: '50%', background: '#FFFFFF', boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.08)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
      {bad
        ? <span style={{ fontSize: size > 28 ? 9 : 7, lineHeight: '10px', fontWeight: 700, color: '#1D1D1F' }}>{t.slice(0, 4)}</span>
        : <img src={`/logos/${encodeURIComponent(t)}.png`} alt="" draggable={false} onError={() => setBad(true)}
            style={{ width: '74%', height: '74%', objectFit: 'contain', pointerEvents: 'none' }} />}
    </span>
  );
}

/** An IBKR line with no name: trades coming in, a neutral circle with a down arrow. */
function InIcon() {
  return (
    <span aria-hidden="true" style={{ flex: 'none', width: 32, height: 32, borderRadius: '50%', background: 'rgba(118,118,128,.24)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: INK }}>
      <svg width="16" height="16" viewBox="0 0 24 24" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 2.2, strokeLinecap: 'round', strokeLinejoin: 'round' }}><path d="M12 5v14M6 13l6 6 6-6" /></svg>
    </span>
  );
}

function Chev({ open }: { open: boolean }) {
  return (
    <svg aria-hidden="true" width="10" height="10" viewBox="0 0 24 24"
      style={{ flex: 'none', fill: 'none', stroke: 'currentColor', strokeWidth: 3.2, strokeLinecap: 'round', strokeLinejoin: 'round', transform: `rotate(${open ? 90 : 0}deg)`, transition: 'transform .25s ease' }}>
      <path d="M9 6l6 6-6 6" />
    </svg>
  );
}

/** The bell and its panel. */
export function ActivityBell() {
  const { book, actOpen, actFocus, openActivity, closeActivity } = useWeb();
  const p = useHome(book).data?.payload;
  const act = useMemo(() => readActivity(p), [p]);
  const { read, mark } = useReadKeys(book);
  const btn = useRef<HTMLButtonElement>(null);
  const [host, setHost] = useState<Element | null>(null);
  const has = !!act;
  useLayoutEffect(() => { if (has) setHost(btn.current?.closest('.sw') ?? null); }, [has]);
  // The panel stays drawn while it slides out; the filter is kept between opens.
  const [mounted, setMounted] = useState(false);
  const [filter, setFilter] = useState<Filter>('all');
  useEffect(() => { if (actOpen && has) setMounted(true); }, [actOpen, has]);
  // An account whose payload has no Activity: nothing to show, the panel closes.
  useEffect(() => { if (!has && actOpen) closeActivity(); }, [has, actOpen, closeActivity]);
  if (!act || !book) return null;

  const n = unreadToday(act, read).length, stopped = act.sync.stopped;
  const aria = `Activity${stopped ? ', IBKR has stopped' : ''}${n ? `, ${n} unread` : ''}`;
  return (
    <>
      <button ref={btn} type="button" className="bare sw-bell" onClick={() => (actOpen ? closeActivity() : openActivity())}
        aria-haspopup="dialog" aria-expanded={actOpen} aria-label={aria} title="Activity"
        style={{ flex: 'none', position: 'relative', width: 44, height: 44, margin: '0 -30px 0 -12px', borderRadius: '50%', background: 'transparent',
          display: 'flex', alignItems: 'center', justifyContent: 'center', color: actOpen ? INK : SUB, transition: 'color .2s' }}>
        <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' }}>
          <path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 0 1-3.46 0" />
        </svg>
        {(stopped || n > 0) && (
          <span aria-hidden="true" style={{ position: 'absolute', top: 6, left: 23, minWidth: 16, height: 16, padding: '0 4px', borderRadius: 8, background: BADGE,
            color: '#FFFFFF', fontSize: 10, lineHeight: '16px', fontWeight: 700, textAlign: 'center', fontVariantNumeric: 'tabular-nums' }}>
            {stopped ? '!' : n > 99 ? '99+' : n}
          </span>
        )}
      </button>
      {mounted && host && createPortal(
        <Panel act={act} book={book} open={actOpen} focus={actFocus} read={read} mark={mark} filter={filter} setFilter={setFilter}
          onClose={closeActivity} onGone={() => setMounted(false)} />, host)}
      {/* Under 480 px the bar's gaps are 10; the bell's 44 px target overlaps them so the glyph sits 12 from To do and the
          eye. Under 400 px (a 390 phone) the bar needs about 12 px more for the clock to stay whole on two lines, so
          the bell overlaps a little more and the tabs close up a little, only while the bell is drawn. */}
      <style>{`.sw .sw-bell:hover{color:#F5F5F7!important}
@media (max-width:480px){.sw .sw-hd .sw-bell{margin:0 -10px!important}}
@media (max-width:400px){.sw .sw-hd .sw-bell{margin:0 -13px!important}.sw .sw-hd .sw-hd-l{gap:12px!important}.sw .sw-hd .sw-hd-tabs{gap:14px!important}}
.sw .act-row:hover{background:rgba(255,255,255,.03)}.sw .act-mark:hover{opacity:.7}`}</style>
    </>
  );
}

interface PanelProps {
  act: Activity; book: BookId; open: boolean; focus: { key: string; n: number } | null;
  read: Set<string>; mark: (keys: string[]) => void; filter: Filter; setFilter: (f: Filter) => void;
  onClose: () => void; onGone: () => void;
}

function Panel({ act, book, open, focus, read, mark, filter, setFilter, onClose, onGone }: PanelProps) {
  const navigate = useNavigate();
  const rm = useReducedMotion();
  const now = useNY(15_000);
  const sheet = useRef<HTMLDivElement>(null), scrim = useRef<HTMLButtonElement>(null), xRef = useRef<HTMLButtonElement>(null);
  const gone = useRef(onGone);
  gone.current = onGone;
  const [op, setOp] = useState<Record<string, boolean>>({});

  // In and out. The page's motion rule turns CSS motion off under Reduce Motion, so this uses the Web Animations API:
  // a slide from the right, or a fade under Reduce Motion.
  const anims = useRef<Animation[]>([]);
  const timer = useRef<number>();
  useLayoutEffect(() => {
    const el = sheet.current, sc = scrim.current;
    anims.current.forEach((a) => a.cancel());
    anims.current = [];
    window.clearTimeout(timer.current);
    if (!el || !sc || typeof el.animate !== 'function') { if (!open) gone.current(); return; }
    const kf: Keyframe[] = rm ? [{ opacity: 0 }, { opacity: 1 }] : [{ transform: 'translateX(100%)' }, { transform: 'translateX(0)' }];
    const ms = open ? (rm ? 200 : 450) : (rm ? 160 : 400);
    const a1 = el.animate(open ? kf : [...kf].reverse(),
      { duration: ms, easing: rm ? 'ease' : open ? 'cubic-bezier(.22,1,.36,1)' : 'cubic-bezier(.4,0,.2,1)', fill: 'both' });
    const a2 = sc.animate(open ? [{ opacity: 0 }, { opacity: 1 }] : [{ opacity: 1 }, { opacity: 0 }], { duration: 300, easing: 'ease', fill: 'both' });
    anims.current = [a1, a2];
    if (!open) {
      a1.onfinish = () => gone.current();
      // A tab that paints no frames (in the background) never finishes the animation: the panel goes anyway.
      timer.current = window.setTimeout(() => gone.current(), ms + 200);
    }
  }, [open]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => { anims.current.forEach((a) => a.cancel()); window.clearTimeout(timer.current); }, []);

  // Open: focus goes in (the ✕, or the line a Levels row asked for), the page behind stays put, Esc closes.
  useEffect(() => {
    if (!open) return;
    const was = document.activeElement as HTMLElement | null;
    if (!focus) xRef.current?.focus({ preventScroll: true });
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); onClose(); } };
    window.addEventListener('keydown', key, true);
    const html = document.documentElement, ov = html.style.overflow;
    html.style.overflow = 'hidden';
    return () => { window.removeEventListener('keydown', key, true); html.style.overflow = ov; was?.focus?.({ preventScroll: true }); };
  }, [open]); // eslint-disable-line react-hooks/exhaustive-deps

  // A Levels row opened the panel on its line: every kind shows, the line is read, and it scrolls into view.
  useEffect(() => {
    if (!open || !focus) return;
    setFilter('all');
    mark([focus.key]);
    let id = requestAnimationFrame(() => {
      id = requestAnimationFrame(() => {
        const sc = sheet.current, el = sc?.querySelector<HTMLElement>(`[data-a="${CSS.escape(focus.key)}"]`);
        if (!sc || !el) { xRef.current?.focus({ preventScroll: true }); return; }
        const top = sc.scrollTop + el.getBoundingClientRect().top - sc.getBoundingClientRect().top - 100;
        sc.scrollTo({ top: Math.max(0, top), behavior: rm ? 'auto' : 'smooth' });
        el.querySelector<HTMLElement>('button')?.focus({ preventScroll: true });
      });
    });
    return () => cancelAnimationFrame(id);
  }, [focus?.n, open]); // eslint-disable-line react-hooks/exhaustive-deps

  // Tab stays inside the panel.
  const trap = (e: ReactKey) => {
    if (e.key !== 'Tab' || !sheet.current) return;
    const fs = [...sheet.current.querySelectorAll<HTMLElement>('button:not([disabled]), [href], [tabindex]:not([tabindex="-1"])')];
    if (!fs.length) return;
    const first = fs[0], last = fs[fs.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  };

  const d = useMemo(() => daysOf(act.today), [act.today]);
  const unread = (e: ActEvent) => e.day === act.today && !read.has(e.key);
  const todays = act.events.filter((e) => e.day === act.today);
  const nU = todays.filter((e) => !read.has(e.key)).length;
  const shown = act.events.filter((e) => filter === 'all' || e.kind === filter);
  const groups = GROUPS.map((g) => ({ g, rows: shown.filter((e) => groupOf(e.day, d) === g) })).filter((x) => x.rows.length);
  const sy = syncWords(act);
  const names = new Map(act.levels.map((l) => [l.t, l.name]));

  const tap = (e: ActEvent) => {
    mark([e.key]);
    if (e.trades.length) { setOp((o) => ({ ...o, [e.key]: !o[e.key] })); return; }
    if ((e.kind === 'lvl' || e.kind === 'move') && e.t) { navigate('/positions/' + encodeURIComponent(e.t)); onClose(); }
  };

  return (
    <div className="tnum" style={{ position: 'fixed', inset: 0, zIndex: 30, display: 'flex', justifyContent: 'flex-end', overflow: 'hidden', pointerEvents: open ? 'auto' : 'none' }}>
      <button ref={scrim} type="button" tabIndex={-1} aria-label="Close Activity" className="bare" onClick={onClose}
        style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.4)', cursor: 'default' }} />
      <div ref={sheet} role="dialog" aria-modal="true" aria-label="Activity" className="noscroll" onKeyDown={trap}
        style={{ position: 'relative', width: 440, maxWidth: '100%', height: '100%', overflowY: 'auto', overflowX: 'hidden', overscrollBehavior: 'contain',
          padding: '28px 16px 40px', display: 'flex', flexDirection: 'column', gap: 20,
          background: 'rgba(28,28,30,.9)', WebkitBackdropFilter: 'blur(30px) saturate(180%)', backdropFilter: 'blur(30px) saturate(180%)',
          boxShadow: 'inset 1px 0 0 rgba(255,255,255,.12),-20px 0 60px rgba(0,0,0,.5)' }}>
        <div style={{ flex: 'none', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12, padding: '0 4px' }}>
          <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
            <span role="heading" aria-level={2} style={{ fontSize: 28, lineHeight: '34px', fontWeight: 700, letterSpacing: '-.03em' }}>Activity</span>
            <span style={{ fontSize: 14, lineHeight: '18px', color: SUB }}>{BOOK_NAME[book]}’s book · {shortDate(now.date)}, {clock12(now)}</span>
          </span>
          <button ref={xRef} type="button" onClick={onClose} aria-label="Close Activity" className="xbtn"
            style={{ flex: 'none', width: 32, height: 32, fontSize: 13 }}>✕</button>
        </div>

        <section aria-label="IBKR sync" style={{ ...GLASS, flex: 'none', borderRadius: 22, padding: '4px 16px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '8px minmax(0,1fr)', gap: 10, alignItems: 'center', minHeight: 56, padding: '8px 0' }}>
            <span aria-hidden="true" style={{ width: 8, height: 8, borderRadius: '50%', background: sy.dot === 'g' ? C.green : sy.dot === 'r' ? C.red : SUB }} />
            <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
              <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{sy.title}</span>
              <span style={{ fontSize: 12, lineHeight: '16px', color: SUB, textWrap: 'pretty' } as CSSProperties}>{sy.sub}</span>
            </span>
          </div>
        </section>

        <Segmented label="Show" items={FILTERS} value={filter} onPick={setFilter} size={13} wrapStyle={{ flex: 'none' }} />

        {groups.map(({ g, rows }) => (
          <section key={g} aria-label={d.label[g]} style={{ flex: 'none', display: 'flex', flexDirection: 'column', gap: 10 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12, padding: '0 4px' }}>
              <span role="heading" aria-level={3} style={{ fontSize: 20, lineHeight: '24px', fontWeight: 700 }}>{d.label[g]}</span>
              {g === 'today' && nU > 0 && (
                <button type="button" className="bare act-mark" onClick={() => mark(todays.map((e) => e.key))}
                  style={{ fontSize: 15, lineHeight: '20px', fontWeight: 500, color: INK }}>Mark all read</button>
              )}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', padding: '0 14px', borderRadius: 22, overflow: 'hidden', background: 'rgba(255,255,255,.05)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.08)' }}>
              {rows.map((e, i) => <Row key={e.key} e={e} first={!i} tm={eventTime(e, g)} unread={unread(e)} open={!!op[e.key]} name={e.t ? names.get(e.t) ?? e.t : ''} onTap={() => tap(e)} />)}
            </div>
          </section>
        ))}
        {!groups.length && <span style={{ padding: '0 4px', fontSize: 15, lineHeight: '20px', color: SUB }}>Nothing here this week.</span>}
      </div>
    </div>
  );
}

const STATUS: Record<string, [string, string]> = { added: ['Added', C.green], match: ['Matched', C.green], matched: ['Matched', C.green], check: ['Check', C.orange] };

function Row({ e, first, tm, unread, open, name, onTap }: { e: ActEvent; first: boolean; tm: string; unread: boolean; open: boolean; name: string; onTap: () => void }) {
  const { mask } = useWeb();
  const n = e.trades.length, pickup = n > 0;
  const tks = [...new Set(e.trades.map((x) => x.t).filter(Boolean))];
  const ck = e.trades.filter((x) => x.st === 'check').length;
  const body = e.body || (pickup ? `${tks.join(', ')} · ${ck ? `${ck} to check` : 'all in your book'}` : '');
  const goes = !pickup && (e.kind === 'lvl' || e.kind === 'move') && !!e.t;
  const said = body ? ' ' + mask(body).replace(/[.\s]+$/, '') + '.' : '';
  const aria = `${mask(e.title)}, ${tm}.${said}${unread ? ' Unread.' : ''}${goes ? ` Opens Positions, ${name}.` : ''}`;
  return (
    <div data-a={e.key} style={{ display: 'flex', flexDirection: 'column', borderTop: first ? 'none' : LN }}>
      <button type="button" className="bare act-row" onClick={onTap} aria-expanded={pickup ? open : undefined} aria-label={aria}
        style={{ display: 'grid', gridTemplateColumns: '32px minmax(0,1fr)', gap: 12, alignItems: 'start', margin: '0 -14px', padding: '12px 14px' }}>
        {e.t ? <Logo t={e.t} size={32} /> : <InIcon />}
        <span style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
          <span style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10 }}>
            <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, textWrap: 'pretty' } as CSSProperties}>{mask(e.title)}</span>
            <span style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, lineHeight: '18px', color: SUB, whiteSpace: 'nowrap' }}>
              {unread && <span aria-hidden="true" style={{ width: 8, height: 8, borderRadius: '50%', background: BLUE }} />}{tm}
            </span>
          </span>
          {body && <span style={{ fontSize: 14, lineHeight: '20px', color: SUB, textWrap: 'pretty' } as CSSProperties}>{mask(body)}</span>}
          {pickup && (
            <span style={{ display: 'flex', alignItems: 'center', gap: 4, paddingTop: 2, fontSize: 13, lineHeight: '18px', fontWeight: 600, color: INK }}>
              {open ? 'Hide' : 'Show'} {n === 1 ? 'the trade' : `${n} trades`}<Chev open={open} />
            </span>
          )}
        </span>
      </button>
      {pickup && open && (
        <div role="list" aria-label="Trades" style={{ display: 'flex', flexDirection: 'column', margin: '0 0 12px 44px', padding: '2px 12px', borderRadius: 14, background: 'rgba(255,255,255,.04)' }}>
          {e.trades.map((x, j) => {
            const [st, sc] = STATUS[x.st] ?? [x.st ? x.st[0].toUpperCase() + x.st.slice(1) : 'Added', INK];
            return (
              <div key={j} role="listitem" style={{ display: 'grid', gridTemplateColumns: '24px minmax(0,1fr) auto', gap: 10, alignItems: 'center', padding: '10px 0', borderTop: j ? LN : 'none' }}>
                {x.t ? <Logo t={x.t} size={24} /> : <span />}
                <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
                  <span style={{ fontSize: 14, lineHeight: '19px', fontWeight: 600, textWrap: 'pretty' } as CSSProperties}>{x.what}</span>
                  <span style={{ fontSize: 12, lineHeight: '16px', color: SUB }}>{x.at}</span>
                </span>
                <span style={{ flex: 'none', fontSize: 12, lineHeight: '16px', fontWeight: 600, color: sc, textAlign: 'right' }}>{st}</span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
