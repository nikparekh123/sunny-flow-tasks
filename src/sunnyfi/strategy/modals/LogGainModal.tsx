import { useState } from 'react';
import { Modal } from './Modal';
import type { Bucket, StrategyPosition, GainSource } from '../types';
import { BUCKET_META } from '../types';
import { fmtK } from '../calc';

interface Props {
  position: StrategyPosition;
  bucket: Bucket;
  onClose: () => void;
  /** Inserts ONE new gain_entries row. */
  onConfirm: (p: {
    ticker: string;
    source: GainSource;
    amount: number;
    note: string;
  }) => void;
}

export function LogGainModal({ position, bucket, onClose, onConfirm }: Props) {
  const [amount, setAmount] = useState(0);
  const [source, setSource] = useState<GainSource>('call');
  const [note, setNote] = useState('');

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
            {(['stock', 'call', 'put'] as const).map((s) => (
              <button
                key={s}
                onClick={() => setSource(s)}
                className={'btn ' + (source === s ? 'primary' : 'ghost')}
                style={{ flex: 1 }}
              >
                {s === 'stock' ? 'Stock' : s === 'call' ? 'Call' : 'Put'}
              </button>
            ))}
          </div>
        </div>
        <div className="field">
          <label>Amount (signed; − for losses)</label>
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
          <label>Note (optional)</label>
          <input
            type="text"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="strike, ex-div date, etc."
          />
        </div>
      </div>

      <div className="verdict-strip">
        <span className="label">
          new {source} entry for <b>{position.ticker}</b>
        </span>
        <span className={'total ' + (amount >= 0 ? 'pos' : 'neg')}>
          {amount >= 0 ? '+' : ''}
          {fmtK(amount || 0)}
        </span>
      </div>

      <div className="actions">
        <div />
        <div className="group">
          <button className="btn ghost" onClick={onClose}>cancel</button>
          <button
            className="btn primary"
            disabled={!amount}
            onClick={() => onConfirm({ ticker: position.ticker, source, amount, note })}
          >
            ✓ log {fmtK(amount || 0)}
          </button>
        </div>
      </div>
    </Modal>
  );
}
