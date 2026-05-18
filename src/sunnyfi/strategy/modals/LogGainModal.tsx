import { useState } from 'react';
import { Modal } from './Modal';
import type { Bucket, StrategyPosition } from '../types';
import { BUCKET_META } from '../types';
import { fmtK, mondayOf } from '../calc';

type Kind = 'options' | 'stock';

interface Props {
  position: StrategyPosition;
  bucket: Bucket;
  onClose: () => void;
  /** Adds `amount` to this week's existing entry (kind = options | stock). */
  onConfirm: (p: {
    ticker: string;
    kind: Kind;
    amount: number;
    notes: string;
  }) => void;
}

export function LogGainModal({ position, bucket, onClose, onConfirm }: Props) {
  const [amount, setAmount] = useState(0);
  const [kind, setKind] = useState<Kind>('options');
  const [notes, setNotes] = useState('');

  const thisMonday = mondayOf();
  const thisWeekEntry = position.entries.find((e) => e.week_start_date === thisMonday);
  const newOptions = (thisWeekEntry?.options ?? 0) + (kind === 'options' ? amount : 0);
  const newStock = (thisWeekEntry?.stock ?? 0) + (kind === 'stock' ? amount : 0);

  return (
    <Modal accent={`var(--b-${bucket})`} onClose={onClose}>
      <div className="mh">
        <div>
          <div className="sub">
            {position.ticker} · {BUCKET_META[bucket].name} · this week
          </div>
          <div className="title">Log a gain</div>
        </div>
        <button className="x" onClick={onClose}>✕</button>
      </div>

      <div className="form-grid">
        <div className="field full">
          <label>Source</label>
          <div style={{ display: 'flex', gap: 8 }}>
            <button
              onClick={() => setKind('options')}
              className={'btn ' + (kind === 'options' ? 'primary' : 'ghost')}
              style={{ flex: 1 }}
            >
              Options premium
            </button>
            <button
              onClick={() => setKind('stock')}
              className={'btn ' + (kind === 'stock' ? 'primary' : 'ghost')}
              style={{ flex: 1 }}
            >
              Stock (dividend / realized)
            </button>
          </div>
        </div>
        <div className="field">
          <label>Amount</label>
          <input
            type="number"
            step="50"
            value={amount}
            onChange={(e) => setAmount(parseInt(e.target.value || '0', 10))}
            placeholder="0"
            autoFocus
          />
        </div>
        <div className="field full">
          <label>Notes (optional)</label>
          <input
            type="text"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="strike, ex-div date, etc."
          />
        </div>
      </div>

      <div className="verdict-strip">
        <span className="label">
          this week's entry for <b>{position.ticker}</b>: options{' '}
          <b>{fmtK(newOptions)}</b> · stock <b>+{fmtK(newStock)}</b>
        </span>
        <span className="total pos">+{fmtK(amount || 0)}</span>
      </div>

      <div className="actions">
        <div />
        <div className="group">
          <button className="btn ghost" onClick={onClose}>cancel</button>
          <button
            className="btn primary"
            disabled={!amount || amount <= 0}
            onClick={() => onConfirm({ ticker: position.ticker, kind, amount, notes })}
          >
            ✓ log {fmtK(amount || 0)}
          </button>
        </div>
      </div>
    </Modal>
  );
}
