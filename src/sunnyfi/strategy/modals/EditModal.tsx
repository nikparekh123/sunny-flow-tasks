import { useState } from 'react';
import { Modal } from './Modal';
import type { Bucket, PutFrequency, StrategyPosition } from '../types';
import { BUCKET_META, PUT_FREQUENCIES, WEEKS_PER_PUT_PERIOD } from '../types';
import { fmt$, fmtK, fmtPx, type Cadence } from '../calc';

const PERIOD_DAYS: Record<Cadence, number> = { month: 30, quarter: 91, year: 365 };
const PERIOD_WEEKS: Record<Cadence, number> = { month: 4.33, quarter: 13, year: 52 };
const POSITIONS_HREF = 'https://positions.sunnyfi.co';

interface Props {
  position: StrategyPosition;
  bucket: Bucket;
  cadence: Cadence;
  onClose: () => void;
  onSave: (updated: {
    ticker: string;
    put_cost: number;
    put_frequency: PutFrequency;
    notes: string | null;
  }) => void;
  onSell: (p: StrategyPosition, bucket: Bucket) => void;
  onMove: (p: StrategyPosition, from: Bucket, to: Bucket) => void;
}

const fmtSignedK = (n: number): string =>
  (n >= 0 ? '+' : '−') + fmtK(Math.abs(n)).replace(/^−/, '');

export function EditModal({ position, bucket, cadence, onClose, onSave, onSell, onMove }: Props) {
  const [putCost, setPutCost] = useState(position.overlay?.put_cost ?? 0);
  const [putFrequency, setPutFrequency] = useState<PutFrequency>(
    position.overlay?.put_frequency ?? 'quarterly',
  );
  const [notes, setNotes] = useState(position.overlay?.notes ?? '');

  const qty = position.quantity ?? 0;
  const avg = position.avg_cost ?? 0;
  const px = position.current_price ?? avg;
  const daysHeld = position.overlay?.days_held ?? 0;

  const collected = position.entries
    .filter((e) => e.source === 'call')
    .reduce((s, e) => s + (e.amount || 0), 0);
  const realized = position.entries
    .filter((e) => e.source === 'stock')
    .reduce((s, e) => s + (e.amount || 0), 0);

  const cost = qty * avg;
  const value = qty * px;
  const sharePL = value - cost;
  const sharePLPct = cost > 0 ? (sharePL / cost) * 100 : 0;

  const daysInPeriod = PERIOD_DAYS[cadence];
  const periodWeeks = PERIOD_WEEKS[cadence];
  const weeksPer = WEEKS_PER_PUT_PERIOD[putFrequency];
  const weeklyTarget = putCost / weeksPer;
  const target = weeklyTarget * periodWeeks;
  const expected = (weeklyTarget * Math.min(daysHeld, daysInPeriod)) / 7;
  const onTrack = expected > 0 ? collected / expected : 1;
  const shortfall = expected - collected;
  const daysLeft = Math.max(7, daysInPeriod - (daysHeld % daysInPeriod));
  const weeksLeft = Math.max(1, daysLeft / 7);
  const catchUp = shortfall > 0 ? shortfall / weeksLeft : 0;
  const total = sharePL + collected + realized;
  const verdict: 'good' | 'warn' | 'bad' =
    onTrack >= 1 ? 'good' : onTrack >= 0.85 ? 'warn' : 'bad';

  const accent = `var(--b-${bucket})`;
  const otherBuckets: Bucket[] = (['income', 'invest', 'yield'] as Bucket[]).filter(
    (b) => b !== bucket,
  );

  return (
    <Modal accent={accent} onClose={onClose}>
      <div className="mh">
        <div>
          <div className="sub">
            {BUCKET_META[bucket].name} · {daysHeld}d held
          </div>
          <div className="title">
            {position.ticker}{' '}
            <span
              style={{
                color: 'var(--navi-fg3)',
                fontSize: 14,
                fontWeight: 400,
                marginLeft: 8,
              }}
            >
              {position.name}
            </span>
          </div>
        </div>
        <button className="x" onClick={onClose}>✕</button>
      </div>

      <div className="form-grid">
        <div className="field">
          <label>Shares (read-only)</label>
          <div className="derived">
            {qty.toLocaleString('en-US')}{' '}
            <a href={POSITIONS_HREF} target="_blank" rel="noreferrer">
              open in Positions ↗
            </a>
          </div>
        </div>
        <div className="field">
          <label>Buy price (read-only)</label>
          <div className="derived">{fmtPx(avg)}</div>
        </div>
        <div className="field">
          <label>Current price (read-only)</label>
          <div className="derived">{fmtPx(px)}</div>
        </div>
        <div className="field">
          <label>Share P&amp;L</label>
          <div className={'derived ' + (sharePL >= 0 ? 'pos' : 'neg')}>
            {fmtSignedK(sharePL)} · {sharePLPct >= 0 ? '+' : ''}
            {sharePLPct.toFixed(1)}%
          </div>
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
          <label>Implied weekly pace · {cadence} target</label>
          <div className="derived">
            {fmt$(Math.round(weeklyTarget))} / wk · {fmtK(target)} per {cadence}
          </div>
        </div>
        <div className="field">
          <label>Premium collected (derived)</label>
          <div className="derived">
            {fmtK(collected)} · from {position.entries.length} entries
          </div>
        </div>
        <div className="field">
          <label>Realized gains (derived)</label>
          <div className="derived pos">+{fmtK(realized)}</div>
        </div>
        <div className="field">
          <label>Cost basis</label>
          <div className="derived">{fmt$(cost)}</div>
        </div>
        <div className="field">
          <label>Current value</label>
          <div className="derived">{fmt$(value)}</div>
        </div>
        <div className="field full">
          <label>Notes (optional)</label>
          <input
            type="text"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="thesis, sell rules, rolls, etc."
          />
        </div>
      </div>

      <div className={'verdict-strip ' + (verdict === 'good' ? '' : verdict === 'warn' ? 'warn' : 'bad')}>
        <span className="label">
          {verdict === 'good' ? (
            <>
              <b>ON TRACK</b> · {(onTrack * 100).toFixed(0)}% of pace · +
              {fmt$(-shortfall)} ahead
            </>
          ) : (
            <>
              <b>{verdict === 'warn' ? 'SLIPPING' : 'BEHIND'}</b> ·{' '}
              {(onTrack * 100).toFixed(0)}% of pace · need{' '}
              <b style={{ color: 'var(--navi-neon)' }}>{fmt$(catchUp)}/wk</b> for{' '}
              {Math.ceil(weeksLeft)} wks
            </>
          )}
        </span>
        <span className={'total ' + (total >= 0 ? 'pos' : '')}>
          total {fmtSignedK(total)}
        </span>
      </div>

      <div className="actions">
        <button className="btn danger" onClick={() => onSell(position, bucket)}>
          ✕ sold (close)
        </button>
        <div className="group">
          <span
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 8,
              fontSize: 10,
              letterSpacing: 1.2,
              textTransform: 'uppercase',
              color: 'var(--navi-fg3)',
            }}
          >
            move to:
            {otherBuckets.map((b) => (
              <button
                key={b}
                className="btn ghost"
                style={{
                  padding: '4px 10px',
                  fontSize: 10,
                  borderColor: `var(--b-${b})`,
                  color: `var(--b-${b})`,
                }}
                onClick={() => onMove(position, bucket, b)}
              >
                {BUCKET_META[b].name}
              </button>
            ))}
          </span>
        </div>
        <div className="group">
          <button className="btn ghost" onClick={onClose}>cancel</button>
          <button
            className="btn primary"
            onClick={() =>
              onSave({
                ticker: position.ticker,
                put_cost: putCost,
                put_frequency: putFrequency,
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
