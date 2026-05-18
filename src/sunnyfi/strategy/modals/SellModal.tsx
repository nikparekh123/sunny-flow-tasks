import { useState } from 'react';
import { Modal } from './Modal';
import type { Bucket, StrategyPosition } from '../types';
import { fmt$, fmtK, fmtPx } from '../calc';

interface Props {
  position: StrategyPosition;
  bucket: Bucket;
  onClose: () => void;
  onConfirm: (p: StrategyPosition, bucket: Bucket, sellPx: number) => void;
}

const fmtSignedK = (n: number): string =>
  (n >= 0 ? '+' : '−') + fmtK(Math.abs(n)).replace(/^−/, '');

export function SellModal({ position, bucket, onClose, onConfirm }: Props) {
  const qty = position.quantity ?? 0;
  const avg = position.avg_cost ?? 0;
  const cur = position.current_price ?? avg;
  const [sellPx, setSellPx] = useState(cur);

  const proceeds = Math.round(qty * sellPx);
  const cost = qty * avg;
  const sharePL = proceeds - cost;
  const sharePLPct = cost > 0 ? (sharePL / cost) * 100 : 0;
  const collected = position.entries
    .filter((e) => e.source === 'call')
    .reduce((s, e) => s + (e.amount || 0), 0);
  const realized = position.entries
    .filter((e) => e.source === 'stock')
    .reduce((s, e) => s + (e.amount || 0), 0);
  const total = sharePL + collected + realized;
  const totalPct = cost > 0 ? (total / cost) * 100 : 0;
  const daysHeld = position.overlay?.days_held ?? 0;

  return (
    <Modal accent="var(--navi-negative)" onClose={onClose}>
      <div className="mh">
        <div>
          <div className="sub">close · return ticker to watchlist</div>
          <div className="title">Sell {position.ticker}</div>
        </div>
        <button className="x" onClick={onClose}>✕</button>
      </div>

      <div className="form-grid">
        <div className="field">
          <label>Sell price</label>
          <input
            type="number"
            step="0.01"
            value={sellPx}
            onChange={(e) => setSellPx(parseFloat(e.target.value || '0'))}
          />
        </div>
        <div className="field">
          <label>Shares</label>
          <div className="derived">{qty.toLocaleString('en-US')}</div>
        </div>
        <div className="field">
          <label>Buy price</label>
          <div className="derived">{fmtPx(avg)}</div>
        </div>
        <div className="field">
          <label>Total proceeds</label>
          <div className="derived">{fmt$(proceeds)}</div>
        </div>
        <div className="field">
          <label>Cost basis</label>
          <div className="derived">{fmt$(cost)}</div>
        </div>
        <div className="field">
          <label>Share P&amp;L</label>
          <div className={'derived ' + (sharePL >= 0 ? 'pos' : 'neg')}>
            {fmtSignedK(sharePL)} · {sharePLPct >= 0 ? '+' : ''}
            {sharePLPct.toFixed(1)}%
          </div>
        </div>
        <div className="field">
          <label>Premium kept</label>
          <div className="derived pos">+{fmtK(collected)}</div>
        </div>
        <div className="field">
          <label>Realized gains</label>
          <div className="derived pos">+{fmtK(realized)}</div>
        </div>
      </div>

      <div className={'verdict-strip ' + (total >= 0 ? '' : 'bad')}>
        <span className="label">
          <b>TOTAL RETURN</b> over <b>{daysHeld} days</b> · {totalPct >= 0 ? '+' : ''}
          {totalPct.toFixed(1)}%
        </span>
        <span className={'total ' + (total >= 0 ? 'pos' : '')}>
          {fmtSignedK(total)}
        </span>
      </div>

      <div className="actions">
        <div />
        <div className="group">
          <button className="btn ghost" onClick={onClose}>cancel</button>
          <button className="btn danger" onClick={() => onConfirm(position, bucket, sellPx)}>
            ✓ confirm sell
          </button>
        </div>
      </div>
    </Modal>
  );
}
