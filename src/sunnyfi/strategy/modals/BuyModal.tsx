import { useState } from 'react';
import { Modal } from './Modal';
import type { Bucket, PutFrequency } from '../types';
import {
  BUCKET_META,
  PUT_FREQUENCIES,
  WEEKS_PER_PUT_PERIOD,
  TOTAL_CAPITAL,
} from '../types';
import { fmt$, fmtK } from '../calc';

interface Props {
  ticker: string;
  bucket: Bucket;
  currentPx: number;
  /** When set, we're assigning an existing unassigned position (shares + buy price already chosen). */
  existingShares?: number;
  existingAvgCost?: number;
  /** Capital deployed so far (so we can show remaining). */
  deployedCost: number;
  onClose: () => void;
  onConfirm: (p: {
    ticker: string;
    bucket: Bucket;
    shares: number;
    buyPrice: number;
    putCost: number;
    putFrequency: PutFrequency;
  }) => void;
}

export function BuyModal({
  ticker,
  bucket,
  currentPx,
  existingShares,
  existingAvgCost,
  deployedCost,
  onClose,
  onConfirm,
}: Props) {
  const [shares, setShares] = useState(existingShares ?? 1000);
  const [buyPrice, setBuyPrice] = useState(existingAvgCost ?? currentPx);
  const [putCost, setPutCost] = useState(
    bucket === 'income' ? 15000 : bucket === 'invest' ? 10000 : 4000,
  );
  const [putFrequency, setPutFrequency] = useState<PutFrequency>('quarterly');

  const cost = Math.round(shares * buyPrice);
  const value = Math.round(shares * currentPx);
  const sharePL = value - cost;
  const weeksPer = WEEKS_PER_PUT_PERIOD[putFrequency];
  const weeklyTarget = Math.round(putCost / weeksPer);
  const bucketName = BUCKET_META[bucket].name;
  const cashRemaining = TOTAL_CAPITAL - deployedCost - (existingShares ? 0 : cost);

  return (
    <Modal accent={`var(--b-${bucket})`} onClose={onClose}>
      <div className="mh">
        <div>
          <div className="sub">add to {bucketName}</div>
          <div className="title">{existingShares ? `Assign ${ticker}` : `Buy ${ticker}`}</div>
        </div>
        <button className="x" onClick={onClose}>✕</button>
      </div>

      <div className="form-grid">
        <div className="field">
          <label>Shares</label>
          {existingShares != null ? (
            <div className="derived">{shares.toLocaleString('en-US')}</div>
          ) : (
            <input
              type="number"
              value={shares}
              onChange={(e) => setShares(parseInt(e.target.value || '0', 10))}
            />
          )}
        </div>
        <div className="field">
          <label>Buy price</label>
          {existingAvgCost != null ? (
            <div className="derived">${buyPrice.toFixed(2)}</div>
          ) : (
            <input
              type="number"
              step="0.01"
              value={buyPrice}
              onChange={(e) => setBuyPrice(parseFloat(e.target.value || '0'))}
            />
          )}
        </div>
        <div className="field">
          <label>Total cost</label>
          <div className="derived">{fmt$(cost)}</div>
        </div>
        <div className="field">
          <label>Current value</label>
          <div className="derived">{fmt$(value)}</div>
        </div>
        <div className="field">
          <label>Put cost</label>
          <input
            type="number"
            step="500"
            value={putCost}
            onChange={(e) => setPutCost(parseInt(e.target.value || '0', 10))}
          />
        </div>
        <div className="field">
          <label>Put frequency</label>
          <select
            value={putFrequency}
            onChange={(e) => setPutFrequency(e.target.value as PutFrequency)}
          >
            {PUT_FREQUENCIES.map((f) => (
              <option key={f} value={f}>{f}</option>
            ))}
          </select>
        </div>
        <div className="field full">
          <label>Implied weekly pace</label>
          <div className="derived">
            {fmt$(weeklyTarget)} / wk · {fmtK(putCost)} per {putFrequency.replace('ly', '')}
          </div>
        </div>
      </div>

      <div className={'verdict-strip ' + (sharePL >= 0 ? '' : 'bad')}>
        <span className="label">
          opening with <b>{fmt$(cost)}</b> cost basis · capital remaining{' '}
          <b>{fmtK(cashRemaining)}</b>
        </span>
        <span className={'total ' + (sharePL >= 0 ? 'pos' : '')}>
          {sharePL !== 0
            ? `mark-to-market: ${(sharePL >= 0 ? '+' : '−')}${fmtK(Math.abs(sharePL)).replace(/^−/, '')}`
            : ''}
        </span>
      </div>

      <div className="actions">
        <div />
        <div className="group">
          <button className="btn ghost" onClick={onClose}>cancel</button>
          <button
            className="btn primary"
            onClick={() =>
              onConfirm({ ticker, bucket, shares, buyPrice, putCost, putFrequency })
            }
          >
            ✓ confirm
          </button>
        </div>
      </div>
    </Modal>
  );
}
