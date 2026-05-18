import { useState } from 'react';
import { Modal } from './Modal';
import type { Bucket, StrategyPosition, GainEntryRow } from '../types';
import { BUCKET_META } from '../types';
import { fmt$, fmtK } from '../calc';
import { weekStartForIdx } from '../components/weeklyHistory';

interface Props {
  position: StrategyPosition;
  bucket: Bucket;
  /** 0 = this week, 1 = last week, …, 12 = oldest. */
  weekIdx: number;
  onClose: () => void;
  onSave: (p: {
    ticker: string;
    week_start_date: string;
    options: number;
    stock: number;
    notes: string | null;
  }) => void;
  onDelete: (p: { ticker: string; week_start_date: string }) => void;
}

const fmtSignedK = (n: number): string =>
  (n >= 0 ? '+' : '−') + fmtK(Math.abs(n)).replace(/^−/, '');

export function EntryEditor({
  position,
  bucket,
  weekIdx,
  onClose,
  onSave,
  onDelete,
}: Props) {
  const weekStart = weekStartForIdx(weekIdx);
  const existing: GainEntryRow | undefined = position.entries.find(
    (e) => e.week_start_date === weekStart,
  );
  const [options, setOptions] = useState(existing?.options ?? 0);
  const [stock, setStock] = useState(existing?.stock ?? 0);
  const [notes, setNotes] = useState(existing?.notes ?? '');
  const isExisting = !!(existing && (existing.options || existing.stock || existing.notes));

  const weekLabel =
    weekIdx === 0 ? 'This week' : weekIdx === 1 ? 'Last week' : `${weekIdx} weeks ago`;
  const newTotal = (options || 0) + (stock || 0);
  const existingTotal = existing ? (existing.options || 0) + (existing.stock || 0) : 0;

  return (
    <Modal accent={`var(--b-${bucket})`} onClose={onClose}>
      <div className="mh">
        <div>
          <div className="sub">
            {position.ticker} · {BUCKET_META[bucket].name} · {weekLabel}
          </div>
          <div className="title">{isExisting ? 'Edit entry' : 'Add entry'}</div>
        </div>
        <button className="x" onClick={onClose}>✕</button>
      </div>

      <div className="form-grid">
        <div className="field">
          <label>Options premium</label>
          <input
            type="number"
            step="50"
            value={options}
            onChange={(e) => setOptions(parseInt(e.target.value || '0', 10))}
            placeholder="0"
            autoFocus
          />
        </div>
        <div className="field">
          <label>Stock (dividend / realized)</label>
          <input
            type="number"
            step="50"
            value={stock}
            onChange={(e) => setStock(parseInt(e.target.value || '0', 10))}
            placeholder="0"
          />
        </div>
        <div className="field full">
          <label>Notes (optional)</label>
          <input
            type="text"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="strike, ex-div date, source, etc."
          />
        </div>
      </div>

      <div className="verdict-strip">
        <span className="label">
          week total · <b>{fmt$(newTotal)}</b>
          {isExisting && <> · was {fmt$(existingTotal)}</>}
        </span>
        <span className={'total ' + (newTotal >= 0 ? 'pos' : 'neg')}>
          {fmtSignedK(newTotal)}
        </span>
      </div>

      <div className="actions">
        {isExisting ? (
          <button
            className="btn danger"
            onClick={() => onDelete({ ticker: position.ticker, week_start_date: weekStart })}
          >
            delete
          </button>
        ) : (
          <div />
        )}
        <div className="group">
          <button className="btn ghost" onClick={onClose}>cancel</button>
          <button
            className="btn primary"
            disabled={!options && !stock && !notes}
            onClick={() =>
              onSave({
                ticker: position.ticker,
                week_start_date: weekStart,
                options: options || 0,
                stock: stock || 0,
                notes: notes || null,
              })
            }
          >
            ✓ save
          </button>
        </div>
      </div>
    </Modal>
  );
}
