import { Modal } from './Modal';
import { BUCKET_META, type Bucket, type StrategyPosition } from '../types';

export interface AllocationImpact {
  fromBefore: number;
  fromAfter: number;
  toBefore: number;
  toAfter: number;
}

interface Props {
  position: StrategyPosition;
  from: Bucket;
  to: Bucket;
  allocationImpact: AllocationImpact;
  onClose: () => void;
  onConfirm: (p: StrategyPosition, from: Bucket, to: Bucket) => void;
}

export function MoveModal({ position, from, to, allocationImpact, onClose, onConfirm }: Props) {
  return (
    <Modal accent={`var(--b-${to})`} onClose={onClose}>
      <div className="mh">
        <div>
          <div className="sub">re-classify</div>
          <div className="title">
            Move {position.ticker}: {BUCKET_META[from].name} → {BUCKET_META[to].name}
          </div>
        </div>
        <button className="x" onClick={onClose}>✕</button>
      </div>

      <div style={{ fontSize: 13, color: 'var(--navi-fg2)', lineHeight: 1.7, padding: '10px 0' }}>
        cost basis stays the same · premium history stays attached · weekly target stays the same.
      </div>

      <div className="verdict-strip warn">
        <span className="label">
          allocation shifts: <b>{BUCKET_META[from].name}</b>{' '}
          {allocationImpact.fromBefore.toFixed(1)}% →{' '}
          <b>{allocationImpact.fromAfter.toFixed(1)}%</b> · <b>{BUCKET_META[to].name}</b>{' '}
          {allocationImpact.toBefore.toFixed(1)}% →{' '}
          <b>{allocationImpact.toAfter.toFixed(1)}%</b>
        </span>
      </div>

      <div className="actions">
        <div />
        <div className="group">
          <button className="btn ghost" onClick={onClose}>cancel</button>
          <button className="btn primary" onClick={() => onConfirm(position, from, to)}>
            ✓ confirm move
          </button>
        </div>
      </div>
    </Modal>
  );
}
