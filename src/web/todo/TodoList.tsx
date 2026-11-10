// To do (handoff 2026-11-10-todo, "The list"): the add field on top, the open items sorted by date (no date last,
// ties in the order added), then Done · N. Ported from the prototype's SunnyTodo with its web values (`web` true):
// rows 11 0, circles 20, the picker's days 36 tall with 32 circles. The host owns the list (useTodos).
import { useEffect, useRef, useState, type CSSProperties, type MutableRefObject } from 'react';
import { due as dueWords, full, lab, month, parse, quick, shiftMonth, tk } from './parse';
import type { Todo, TodoPatch } from './useTodos';

/** The web colour column of the README's table. */
const K = {
  ink: '#F5F5F7', mu: '#98989D', rule: 'rgba(255,255,255,.08)', ring: 'rgba(235,235,245,.36)', G: '#65C466', RD: '#FF6961', OR: '#FF9F0A',
  acc: '#86A8F0', accBg: 'rgba(134,168,240,.16)', trk: 'rgba(118,118,128,.24)', pkBg: 'rgba(255,255,255,.06)', btn: '#F5F5F7', btnI: '#000000',
};
const PAD = '11px 0', CZ = 20, IND = 32, DAY_H = 36, DAY_Z = 32;
const pretty = { textWrap: 'pretty' } as CSSProperties;

const CalIcon = () => (
  <svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true" style={{ flex: 'none', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' }}>
    <rect x="3.5" y="5" width="17" height="15.5" rx="3" /><path d="M3.5 10h17M8 3v4M16 3v4" />
  </svg>
);
const Check = () => (
  <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true">
    <path d="M2.5 6.2l2.3 2.3 4.7-4.9" style={{ fill: 'none', stroke: '#FFFFFF', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' }} />
  </svg>
);
const Chev = ({ d }: { d: string }) => (
  <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true">
    <path d={d} style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' }} />
  </svg>
);

/** The date picker (our own): quick chips, the month, the days Monday first. A pick closes it. */
function Picker({ cur, today, base, onBase, onPick }: { cur: string | null; today: string; base: string; onBase: (b: string) => void; onPick: (s: string | null) => void }) {
  const { title, cells } = month(base);
  const chip: CSSProperties = { height: 30, padding: '0 12px', borderRadius: 15, display: 'flex', alignItems: 'center', fontSize: 13, lineHeight: '16px', fontWeight: 600 };
  const nav: CSSProperties = { width: 32, height: 32, borderRadius: 16, display: 'flex', alignItems: 'center', justifyContent: 'center', color: K.ink };
  return (
    <div role="group" aria-label="Pick a date" style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: 12, borderRadius: 16, background: K.pkBg }}>
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        {quick(today).map(([t, s]) => {
          const on = cur === s;
          return <button key={s} type="button" className="bare" aria-pressed={on} onClick={() => onPick(s)} style={{ ...chip, background: on ? K.btn : K.trk, color: on ? K.btnI : K.ink }}>{t}</button>;
        })}
        {cur && <button type="button" className="bare" aria-pressed={false} onClick={() => onPick(null)} style={{ ...chip, background: K.trk, color: K.mu }}>No date</button>}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, padding: '2px 0 0 4px' }}>
        <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{title}</span>
        <div style={{ display: 'flex', gap: 2 }}>
          <button type="button" className="bare td-mo" aria-label="Previous month" onClick={() => onBase(shiftMonth(base, -1))} style={nav}><Chev d="M7.5 2 3.5 6l4 4" /></button>
          <button type="button" className="bare td-mo" aria-label="Next month" onClick={() => onBase(shiftMonth(base, 1))} style={nav}><Chev d="M4.5 2l4 4-4 4" /></button>
        </div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,minmax(0,1fr))', fontVariantNumeric: 'tabular-nums' }}>
        {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((t, i) => (
          <span key={'w' + i} aria-hidden="true" style={{ height: 20, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 11, lineHeight: '14px', fontWeight: 600, color: K.mu }}>{t}</span>
        ))}
        {cells.map((s, i) => {
          if (!s) return <span key={'b' + i} style={{ height: DAY_H }} />;
          const on = s === cur, td = s === today;
          return (
            <button key={s} type="button" className="bare" aria-label={full(s) + (td ? ', today' : '')} aria-pressed={on} onClick={() => onPick(s)}
              style={{ height: DAY_H, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <span style={{ width: DAY_Z, height: DAY_Z, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, lineHeight: '20px',
                fontWeight: on || td ? 700 : 400, background: on ? K.btn : 'transparent', color: on ? K.btnI : td ? K.acc : s < today ? K.mu : K.ink, transition: 'background .15s' }}>{+s.slice(8)}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

/** The open row's note: shows as it is typed, saved when typing stops. */
function NoteField({ x, onNote }: { x: Todo; onNote: (id: string, v: string) => void }) {
  const [v, setV] = useState(x.note);
  return (
    <input className="td-in" type="text" value={v} maxLength={2000} placeholder="Add a note" aria-label="Note"
      onChange={(e) => { setV(e.target.value); onNote(x.id, e.target.value); }}
      style={{ fontSize: 13, lineHeight: '18px', padding: '9px 12px', borderRadius: 10, background: K.trk, color: K.ink }} />
  );
}

export interface TodoListProps {
  items: Todo[];
  /** New York's calendar day, yyyy-mm-dd. */
  today: string;
  /** The book's names and its watchlist: the first of these in a to do's text is bold. */
  known: Set<string>;
  add: (text: string, due: string | null) => void;
  set: (id: string, p: TodoPatch) => void;
  note: (id: string, v: string) => void;
  remove: (id: string) => void;
  /** The host's Escape asks here first: an open picker closes alone. */
  escRef: MutableRefObject<(() => boolean) | null>;
  /** Put the caret in the add field on open (when the popover was opened from the keyboard). */
  focusAdd?: boolean;
}

const at = (s: string) => Date.parse(s) || 0;
const byDue = (a: Todo, b: Todo) => {
  const da = a.due || '9999', db = b.due || '9999';
  return da < db ? -1 : da > db ? 1 : at(a.created_at) - at(b.created_at) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
};

export function TodoList({ items, today: T, known, add, set, note, remove, escRef, focusAdd }: TodoListProps) {
  const [draft, setDraft] = useState('');
  /** null: the date comes from the text; 'none': picked No date; else the picked day. A picked date wins. */
  const [adM, setAdM] = useState<string | null>(null);
  /** Which picker is open: 'add' or a row's id. One at a time. */
  const [pk, setPk] = useState<string | null>(null);
  const [cm, setCm] = useState<string | null>(null);
  const [ex, setEx] = useState<string | null>(null);
  const [dOpen, setDOpen] = useState(false);
  /** Rows just checked off: they stay in place, faded and struck through, for 1.2 s. */
  const [lv, setLv] = useState<ReadonlySet<string>>(() => new Set());
  const timers = useRef(new Map<string, ReturnType<typeof setTimeout>>());
  useEffect(() => { const t = timers.current; return () => t.forEach(clearTimeout); }, []);
  useEffect(() => {
    escRef.current = () => { if (pk == null) return false; setPk(null); return true; };
    return () => { escRef.current = null; };
  }, [pk, escRef]);

  const unLv = (id: string) => setLv((s) => { if (!s.has(id)) return s; const n = new Set(s); n.delete(id); return n; });
  const tg = (x: Todo) => {
    const tm = timers.current;
    clearTimeout(tm.get(x.id));
    tm.delete(x.id);
    if (!x.done) {
      set(x.id, { done: true });
      setLv((s) => new Set(s).add(x.id));
      tm.set(x.id, setTimeout(() => { tm.delete(x.id); unLv(x.id); }, 1200));
    } else {
      set(x.id, { done: false });
      unLv(x.id);
    }
  };

  const open = items.filter((x) => !x.done || lv.has(x.id)).sort(byDue);
  const done = items.filter((x) => x.done && !lv.has(x.id));
  const dcol = (iso: string | null) => (!iso ? K.mu : iso < T ? K.RD : iso === T ? K.OR : K.mu);

  // The add field: a date found in the text shows in accent until one is picked.
  const Pv = adM === null ? parse(draft, T) : null;
  const eff = adM === 'none' ? null : adM || (Pv ? Pv.iso : null);
  const adT = eff ? lab(eff, T) : 'Date';
  const adC = adM && adM !== 'none' ? K.ink : Pv ? K.acc : K.mu;
  const adBg = Pv && adM === null ? K.accBg : pk === 'add' ? K.pkBg : 'transparent';
  const has = !!draft.trim();

  const dueOf = (id: string) => items.find((i) => i.id === id)?.due ?? null;
  const pkCur = pk === 'add' ? eff : pk != null ? dueOf(pk) : null;
  const base = cm || (pkCur || T).slice(0, 8) + '01';
  const openPk = (tgt: string) => {
    const cur = tgt === 'add' ? eff : dueOf(tgt);
    if (pk === tgt) setPk(null);
    else { setPk(tgt); setCm((cur || T).slice(0, 8) + '01'); }
  };
  const pick = (s: string | null) => {
    if (pk === 'add') setAdM(s || 'none');
    else if (pk != null) set(pk, { due: s || null });
    setPk(null);
  };
  const addNew = () => {
    const raw = draft.trim();
    if (!raw) return;
    const P = adM === null ? parse(raw, T) : null;
    const t = P ? P.t : raw.charAt(0).toUpperCase() + raw.slice(1);
    const d = adM && adM !== 'none' ? adM : P ? P.iso : null;
    add(t.slice(0, 500), d);
    setDraft('');
    setAdM(null);
    if (pk === 'add') setPk(null);
  };
  const picker = <Picker cur={pkCur} today={T} base={base} onBase={setCm} onPick={pick} />;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', color: K.ink }}>
      <div style={{ margin: '0 0 8px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, height: 44, padding: '0 6px 0 16px', borderRadius: 22, background: K.trk }}>
          <input className="td-in" type="text" value={draft} maxLength={500} enterKeyHint="done" autoFocus={focusAdd} placeholder="Try “call accountant tomorrow”" aria-label="Add a to do"
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.nativeEvent.isComposing) { e.preventDefault(); addNew(); } }}
            style={{ flex: 1, minWidth: 0, fontSize: 15, lineHeight: '20px', color: K.ink }} />
          <button type="button" className="bare" aria-expanded={pk === 'add'} aria-label={'Date: ' + adT} onClick={() => openPk('add')}
            style={{ flex: 'none', height: 32, padding: '0 10px', borderRadius: 16, display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, lineHeight: '16px', fontWeight: 600,
              whiteSpace: 'nowrap', color: adC, background: adBg, transition: 'background .2s,color .2s' }}>
            <CalIcon /><span>{adT}</span>
          </button>
          <button type="button" className="bare" aria-label="Add" onClick={addNew}
            style={{ flex: 'none', width: 32, height: 32, borderRadius: 16, display: 'flex', alignItems: 'center', justifyContent: 'center', background: K.btn, opacity: has ? 1 : 0.3, transition: 'opacity .2s' }}>
            <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><path d="M7 2v10M2 7h10" style={{ fill: 'none', stroke: K.btnI, strokeWidth: 2, strokeLinecap: 'round' }} /></svg>
          </button>
        </div>
        {Pv && (
          <span style={{ padding: '0 16px', fontSize: 13, lineHeight: '18px', color: K.mu, ...pretty }}>
            Adds “<span style={{ fontWeight: 500, color: K.ink }}>{Pv.t}</span>”, due <span style={{ fontWeight: 600, color: K.acc }}>{dueWords(Pv.iso, T)}</span>
          </span>
        )}
        {pk === 'add' && picker}
      </div>

      {open.map((x) => {
        const ck = x.done, m = tk(x.text, known), isEx = ex === x.id;
        return (
          <div key={x.id} style={{ display: 'flex', flexDirection: 'column', borderTop: `1px solid ${K.rule}`, opacity: ck ? 0.5 : 1, transition: 'opacity .4s' }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12, padding: PAD }}>
              <button type="button" className="bare" aria-pressed={ck} aria-label={(ck ? 'Not done: ' : 'Done: ') + x.text} onClick={() => tg(x)}
                style={{ flex: 'none', width: CZ, height: CZ, borderRadius: '50%', border: `1.5px solid ${ck ? K.G : K.ring}`, background: ck ? K.G : 'transparent',
                  display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'background .2s,border-color .2s' }}>
                {ck && <Check />}
              </button>
              <button type="button" className="bare" aria-expanded={isEx}
                onClick={() => { setEx((e) => (e === x.id ? null : x.id)); setPk((p) => (p === x.id ? null : p)); }}
                style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                <span style={{ fontSize: 15, lineHeight: '20px', textDecoration: ck ? 'line-through' : 'none', overflowWrap: 'anywhere', ...pretty }}>
                  {/* The prototype's structure as is (an empty <b> when no ticker): it is what sets the line breaks. */}
                  {m ? x.text.slice(0, m.i) : x.text}<b style={{ fontWeight: 600 }}>{m ? m.t : ''}</b>{m ? x.text.slice(m.i + m.t.length) : ''}
                </span>
                {x.note && <span style={{ fontSize: 13, lineHeight: '18px', color: K.mu, ...pretty }}>{x.note}</span>}
              </button>
              {x.due && <span style={{ flex: 'none', fontSize: 13, lineHeight: '20px', fontWeight: 500, fontVariantNumeric: 'tabular-nums', color: dcol(x.due) }}>{lab(x.due, T)}</span>}
            </div>
            {isEx && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, padding: `0 0 14px ${IND}px` }}>
                <NoteField x={x} onNote={note} />
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <button type="button" className="bare" aria-expanded={pk === x.id} onClick={() => openPk(x.id)}
                    style={{ height: 32, padding: '0 12px 0 10px', borderRadius: 16, display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, lineHeight: '16px', fontWeight: 600,
                      whiteSpace: 'nowrap', background: K.trk, color: !x.due ? K.mu : x.due < T ? K.RD : x.due === T ? K.OR : K.ink }}>
                    <CalIcon />{x.due ? lab(x.due, T) : 'Add a date'}
                  </button>
                  <span style={{ flex: 1 }} />
                  <button type="button" className="bare" onClick={() => { remove(x.id); setEx(null); setPk(null); }}
                    style={{ fontSize: 13, lineHeight: '16px', fontWeight: 500, color: K.RD }}>Delete</button>
                </div>
                {pk === x.id && picker}
              </div>
            )}
          </div>
        );
      })}

      {!open.length && (
        <span style={{ padding: '14px 0 4px', borderTop: `1px solid ${K.rule}`, fontSize: 15, lineHeight: '20px', color: K.mu }}>Nothing on the list.</span>
      )}

      {done.length > 0 && (
        <button type="button" className="bare" aria-expanded={dOpen} onClick={() => setDOpen((o) => !o)}
          style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '12px 0 4px', borderTop: `1px solid ${K.rule}`, fontSize: 13, lineHeight: '18px', fontWeight: 600, color: K.mu }}>
          {'Done · ' + done.length}
          <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true" style={{ transform: `rotate(${dOpen ? 90 : 0}deg)`, transition: 'transform .2s' }}>
            <path d="M3.5 1.5 7 5l-3.5 3.5" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round' }} />
          </svg>
        </button>
      )}
      {dOpen && done.map((x) => (
        <div key={x.id} style={{ display: 'flex', alignItems: 'flex-start', gap: 12, padding: PAD }}>
          <button type="button" className="bare" aria-pressed={true} aria-label={'Not done: ' + x.text} onClick={() => tg(x)}
            style={{ flex: 'none', width: CZ, height: CZ, borderRadius: '50%', border: `1.5px solid ${K.G}`, background: K.G, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Check />
          </button>
          <span style={{ flex: 1, minWidth: 0, fontSize: 15, lineHeight: '20px', color: K.mu, textDecoration: 'line-through' }}>{x.text}</span>
          {x.due && <span style={{ flex: 'none', fontSize: 13, lineHeight: '20px', fontVariantNumeric: 'tabular-nums', color: K.mu }}>{lab(x.due, T)}</span>}
        </div>
      ))}
    </div>
  );
}
