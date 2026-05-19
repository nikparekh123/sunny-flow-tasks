import { useEffect, useMemo, useState } from 'react';
import {
  computePutProtection,
  fmtUSD,
  fmtUSD2,
  fmtQty,
  type ExpenseEntry,
  type GainEntry,
  type GainSource,
  type PositionComputed,
  type PutProtectionRow,
} from './types';
import { PutProtectionPanel } from './PutProtectionPanel';

const SOURCE_META: Record<GainSource, { label: string; short: string }> = {
  stock: { label: 'Stock', short: 'S' },
  call:  { label: 'Call',  short: 'C' },
  put:   { label: 'Put',   short: 'P' },
};

type Bucket = 'income' | 'invest' | 'yield';
const BUCKET_LABEL: Record<Bucket, string> = {
  income: 'Income',
  invest: 'Investment',
  yield: 'Yield',
};

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

function mondayOf(d: Date): Date {
  const x = new Date(d);
  const day = (x.getUTCDay() + 6) % 7;
  x.setUTCDate(x.getUTCDate() - day);
  x.setUTCHours(0, 0, 0, 0);
  return x;
}

function weekIdxOf(iso: string, todayWeek: Date): number {
  const d = new Date(iso + 'T12:00:00Z');
  const w = mondayOf(d);
  return Math.round((todayWeek.getTime() - w.getTime()) / WEEK_MS);
}

function weekLabel(idx: number): string {
  if (idx === 0) return 'This wk';
  if (idx === 1) return 'Last wk';
  return `−${idx}w`;
}

function weekDateLabel(idx: number, todayWeek: Date): string {
  const d = new Date(todayWeek.getTime() - idx * WEEK_MS);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return `${months[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

const todayIso = () => new Date().toISOString().slice(0, 10);

interface Props {
  position: PositionComputed;
  entries: GainEntry[];
  expenseEntries: ExpenseEntry[];
  putProtection: PutProtectionRow | undefined;
  bucket?: Bucket;
  /** Which ledger this modal is viewing. Defaults to 'gain'. */
  mode?: 'gain' | 'expense';
  onClose: () => void;
  onAddGain: (p: { ticker: string; gain_date: string; source: GainSource; amount: number; note?: string }) => void;
  onDeleteGain: (id: string) => void;
  onAddExpense: (p: { ticker: string; expense_date: string; source: GainSource; amount: number; note?: string }) => void;
  onDeleteExpense: (id: string) => void;
  onSetPutProtection: (p: { ticker: string; total_cost: number; expiry: string; purchase_date?: string }) => void;
  onClearPutProtection: (ticker: string) => void;
  onSetStatus: (p: { ticker: string; status: 'open' | 'closed' }) => void;
}

export function PositionDetailModal({
  position,
  entries,
  expenseEntries,
  putProtection,
  bucket,
  mode = 'gain',
  onClose,
  onAddGain,
  onDeleteGain,
  onAddExpense,
  onDeleteExpense,
  onSetPutProtection,
  onClearPutProtection,
  onSetStatus,
}: Props) {
  const [sourceFilter, setSourceFilter] = useState<'all' | GainSource>('all');
  // Open the inline log form by default in gain mode so the user lands on
  // the entry fields. Expense mode uses the put-protection editor instead.
  const [showAdd, setShowAdd] = useState<null | 'gain' | 'expense'>(mode === 'gain' ? 'gain' : null);
  // In expense mode the modal collapses to just the put-protection editor —
  // put cost *is* the expense in this app, so we auto-open the form.
  const [editPP, setEditPP] = useState(mode === 'expense');

  // Normalize the two ledgers to a common shape so the rest of the modal
  // doesn't have to branch. Expense rows carry expense_date → date.
  type LedgerRow = { id: string; date: string; source: GainSource; amount: number; note?: string };
  const ledger: LedgerRow[] = useMemo(() => {
    if (mode === 'expense') {
      const rows: LedgerRow[] = expenseEntries.map((e) => ({
        id: e.id, date: e.expense_date, source: e.source, amount: e.amount, note: e.note,
      }));
      // Surface put-protection cost as a synthetic put-source expense so the
      // user can see "why is my expense total $X" in one place.
      if (putProtection && putProtection.total_cost > 0) {
        rows.push({
          id: `pp:${putProtection.ticker}`,
          date: putProtection.purchase_date ?? new Date().toISOString().slice(0, 10),
          source: 'put',
          amount: putProtection.total_cost,
          note: 'put protection',
        });
      }
      return rows;
    }
    return entries.map((e) => ({
      id: e.id, date: e.gain_date, source: e.source, amount: e.amount, note: e.note,
    }));
  }, [mode, entries, expenseEntries, putProtection]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
    };
  }, [onClose]);

  const todayWeek = useMemo(() => mondayOf(new Date()), []);

  const filtered = useMemo(() => {
    const list = sourceFilter === 'all' ? ledger : ledger.filter((e) => e.source === sourceFilter);
    return [...list].sort((a, b) => b.date.localeCompare(a.date));
  }, [ledger, sourceFilter]);

  const grouped = useMemo(() => {
    const groups: Record<number, LedgerRow[]> = {};
    filtered.forEach((e) => {
      const w = weekIdxOf(e.date, todayWeek);
      if (!groups[w]) groups[w] = [];
      groups[w].push(e);
    });
    return Object.entries(groups)
      .map(([w, items]) => ({
        weekIdx: parseInt(w, 10),
        items,
        total: items.reduce((s, x) => s + x.amount, 0),
      }))
      .sort((a, b) => a.weekIdx - b.weekIdx);
  }, [filtered, todayWeek]);

  const counts = useMemo(
    () => ({
      all: ledger.length,
      stock: ledger.filter((e) => e.source === 'stock').length,
      call: ledger.filter((e) => e.source === 'call').length,
      put: ledger.filter((e) => e.source === 'put').length,
    }),
    [ledger],
  );

  const ppCalc = computePutProtection(putProtection);
  const isClosed = position.status === 'closed';

  return (
    <div className="np-modal-back" onClick={onClose}>
      <div className="np-modal pd-modal" onClick={(e) => e.stopPropagation()}>
        {/* HEADER */}
        <div className="pd-hd">
          <div>
            <div className="pd-ticker">
              {position.ticker}
              {isClosed && <span className="status-pill closed">closed</span>}
            </div>
            <div className="pd-meta">
              {bucket && <span className={'strategy-badge st-' + bucket}>{BUCKET_LABEL[bucket]}</span>}
              <span className="pd-meta-dot">·</span>
              <span>{position.sector}</span>
              {!isClosed && (
                <>
                  <span className="pd-meta-dot">·</span>
                  <span>
                    {fmtQty(position.quantity)} sh @ {fmtUSD2(position.avg_cost)}
                  </span>
                </>
              )}
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <button
              className={'np-btn ' + (isClosed ? 'tinted' : 'danger')}
              onClick={() =>
                onSetStatus({
                  ticker: position.ticker,
                  status: isClosed ? 'open' : 'closed',
                })
              }
              title={isClosed ? 'Reopen this position' : 'Mark as closed (sold)'}
            >
              {isClosed ? '↻ Reopen' : '✕ Mark closed'}
            </button>
            <button className="np-btn ghost" onClick={onClose}>✕ Close</button>
          </div>
        </div>

        {/* PUT PROTECTION — only in expense mode. Put cost is the
            expense in this app, so it has no place in the gains view. */}
        {mode === 'expense' && (
          <PutProtectionPanel
            ticker={position.ticker}
            calc={ppCalc}
            editing={editPP}
            onEditStart={() => setEditPP(true)}
            onEditCancel={() => setEditPP(false)}
            onSave={(p) => {
              onSetPutProtection({ ticker: position.ticker, ...p });
              setEditPP(false);
            }}
            onClear={() => {
              onClearPutProtection(position.ticker);
              setEditPP(false);
            }}
          />
        )}

        {mode === 'gain' && <>
        {/* SOURCE FILTER */}
        <div className="pd-filter">
          <div className="np-status-filter">
            <button className={sourceFilter === 'all' ? 'on' : ''} onClick={() => setSourceFilter('all')}>
              All <span className="ct">{counts.all}</span>
            </button>
            <button className={sourceFilter === 'stock' ? 'on' : ''} onClick={() => setSourceFilter('stock')}>
              <span className="rchip rk-s rchip-static">S</span>Stock <span className="ct">{counts.stock}</span>
            </button>
            <button className={sourceFilter === 'call' ? 'on' : ''} onClick={() => setSourceFilter('call')}>
              <span className="rchip rk-c rchip-static">C</span>Call <span className="ct">{counts.call}</span>
            </button>
            <button className={sourceFilter === 'put' ? 'on' : ''} onClick={() => setSourceFilter('put')}>
              <span className="rchip rk-p rchip-static">P</span>Put <span className="ct">{counts.put}</span>
            </button>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            {mode === 'gain' ? (
              <button className="np-btn add-gain" onClick={() => setShowAdd('gain')}>
                + Log gain
              </button>
            ) : (
              <button className="np-btn add-expense" onClick={() => setShowAdd('expense')}>
                + Log expense
              </button>
            )}
          </div>
        </div>

        {/* HISTORY */}
        <div className="pd-history">
          {grouped.length === 0 && (
            <div className="pd-empty">
              No {sourceFilter === 'all' ? '' : sourceFilter + ' '}
              {mode === 'expense' ? 'expenses' : 'gains'} yet.
            </div>
          )}
          {grouped.map((g) => (
            <div key={g.weekIdx} className="pd-week-group">
              <div className="pd-week-hd">
                <span className="pd-week-l">{weekLabel(g.weekIdx)}</span>
                <span className="pd-week-d">{weekDateLabel(g.weekIdx, todayWeek)}</span>
                <span className={'pd-week-tot ' + (mode === 'expense' || g.total < 0 ? 'down' : 'up')}>
                  {mode === 'expense' ? '−' + fmtUSD(g.total) : fmtUSD(g.total)}
                </span>
              </div>
              {g.items.map((e) => (
                <div key={e.id} className="pd-entry">
                  <span className={'rchip rk-' + e.source.charAt(0) + ' rchip-static'}>
                    {SOURCE_META[e.source].short}
                  </span>
                  <span className="pd-entry-date">{e.date}</span>
                  <span className={'pd-entry-amt ' + (mode === 'expense' || e.amount < 0 ? 'down' : 'up')}>
                    {mode === 'expense' ? '−' + fmtUSD(e.amount) : fmtUSD(e.amount)}
                  </span>
                  <span className="pd-entry-note">
                    {e.note || <span style={{ color: 'var(--navi-fg5)' }}>—</span>}
                  </span>
                  {e.id.startsWith('pp:') ? (
                    <button
                      className="np-btn ghost pd-entry-del"
                      onClick={() => onClearPutProtection(position.ticker)}
                      title="Clear the put protection for this position"
                    >
                      clear protection
                    </button>
                  ) : (
                    <button
                      className="np-btn ghost pd-entry-del"
                      onClick={() => (mode === 'expense' ? onDeleteExpense(e.id) : onDeleteGain(e.id))}
                    >
                      delete
                    </button>
                  )}
                </div>
              ))}
            </div>
          ))}
        </div>
        </>}

        {mode === 'gain' && showAdd === 'gain' && (
          <PDAddInline
            ticker={position.ticker}
            kind="gain"
            onCancel={() => setShowAdd(null)}
            onSave={(g) => {
              onAddGain({ ticker: position.ticker, gain_date: g.date, source: g.source, amount: g.amount, note: g.note });
              setShowAdd(null);
            }}
          />
        )}
        {mode === 'expense' && showAdd === 'expense' && (
          <PDAddInline
            ticker={position.ticker}
            kind="expense"
            onCancel={() => setShowAdd(null)}
            onSave={(g) => {
              onAddExpense({ ticker: position.ticker, expense_date: g.date, source: g.source, amount: g.amount, note: g.note });
              setShowAdd(null);
            }}
          />
        )}
      </div>
    </div>
  );
}

function PDAddInline({
  ticker,
  kind,
  onCancel,
  onSave,
}: {
  ticker: string;
  kind: 'gain' | 'expense';
  onCancel: () => void;
  onSave: (g: { date: string; source: GainSource; amount: number; note?: string }) => void;
}) {
  const [source, setSource] = useState<GainSource>('call');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [date, setDate] = useState(todayIso());

  const submit = () => {
    const amt = parseFloat(amount);
    if (isNaN(amt) || amt === 0 || !date) return;
    onSave({ date, source, amount: amt, note });
  };

  return (
    <div className="pd-add-inline">
      <div className="pd-add-hd">Log {kind === 'gain' ? 'a gain' : 'an expense'} on {ticker}</div>
      <div className="qa-grid">
        <div className="qa-field">
          <label>Source</label>
          <div className="qa-source">
            {(['stock', 'call', 'put'] as const).map((s) => (
              <button
                key={s}
                type="button"
                className={'qa-source-btn ' + s + (source === s ? ' on' : '')}
                onClick={() => setSource(s)}
              >
                <span className={'rchip rk-' + s.charAt(0) + ' rchip-static'}>
                  {SOURCE_META[s].short}
                </span>
                {SOURCE_META[s].label}
              </button>
            ))}
          </div>
        </div>
        <div className="qa-field">
          <label>Amount</label>
          <input
            className="np-input qa-amount"
            type="number"
            step="50"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0"
            autoFocus
          />
        </div>
        <div className="qa-field">
          <label>Date</label>
          <input
            type="date"
            className="np-input"
            value={date}
            onChange={(e) => setDate(e.target.value)}
          />
        </div>
        <div className="qa-field">
          <label>Note (optional)</label>
          <input
            className="np-input"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="strike, ex-div, source, etc."
          />
        </div>
      </div>
      <div className="qa-actions" style={{ justifyContent: 'flex-end' }}>
        <button className="np-btn ghost" onClick={onCancel}>Cancel</button>
        <button className="np-btn neon" onClick={submit} disabled={!amount || isNaN(parseFloat(amount))}>
          ✓ Add entry
        </button>
      </div>
    </div>
  );
}
