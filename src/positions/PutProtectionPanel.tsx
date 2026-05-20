import { useEffect, useState } from 'react';
import { fmtUSD, fmtUSD2, type PutProtectionCalc } from './types';

const todayIso = () => new Date().toISOString().slice(0, 10);

function fmtExpiry(iso: string | null): string {
  if (!iso) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const d = new Date(iso + 'T12:00:00Z');
  return `${months[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
}

function defaultExpiry(daysFromNow: number): string {
  const d = new Date(Date.now() + daysFromNow * 86_400_000);
  return d.toISOString().slice(0, 10);
}

function daysBetween(fromIso: string, toIso: string): number {
  const a = new Date(fromIso + 'T12:00:00Z');
  const b = new Date(toIso + 'T12:00:00Z');
  return Math.max(0, Math.round((b.getTime() - a.getTime()) / 86_400_000));
}

interface Props {
  ticker: string;
  calc: PutProtectionCalc;
  editing: boolean;
  onEditStart: () => void;
  onEditCancel: () => void;
  onSave: (p: {
    total_cost: number;
    expiry: string;
    purchase_date: string;
    contracts: number | null;
    strike: number | null;
  }) => void;
  onClear: () => void;
}

export function PutProtectionPanel({
  ticker,
  calc,
  editing,
  onEditStart,
  onEditCancel,
  onSave,
  onClear,
}: Props) {
  const [expiry, setExpiry] = useState(calc.expiry ?? defaultExpiry(60));
  const [totalCost, setTotalCost] = useState(calc.has ? String(calc.total_cost) : '');
  const [contracts, setContracts] = useState(calc.contracts != null ? String(calc.contracts) : '');
  const [strike, setStrike] = useState(calc.strike != null ? String(calc.strike) : '');
  // When the user hits "Save protection" we don't write immediately —
  // we show a confirmation chip naming the ticker. This catches the
  // "I had the wrong position open" mistake before it hits the DB.
  const [pendingSave, setPendingSave] = useState<null | {
    total_cost: number;
    expiry: string;
    purchase_date: string;
    contracts: number | null;
    strike: number | null;
  }>(null);

  // Re-sync form state when the panel re-opens or switches position.
  useEffect(() => {
    setExpiry(calc.expiry ?? defaultExpiry(60));
    setTotalCost(calc.has ? String(calc.total_cost) : '');
    setContracts(calc.contracts != null ? String(calc.contracts) : '');
    setStrike(calc.strike != null ? String(calc.strike) : '');
    setPendingSave(null);
  }, [editing, calc.expiry, calc.total_cost, calc.has, calc.contracts, calc.strike, ticker]);

  const previewTotal = parseFloat(totalCost);
  const previewTotalDays = expiry ? daysBetween(todayIso(), expiry) : 0;
  const previewPerDay =
    previewTotalDays > 0 && !isNaN(previewTotal) ? previewTotal / previewTotalDays : 0;

  if (editing) {
    return (
      <div className="pp-panel pp-editing">
        <div className="pp-hd">
          <span className="pp-hd-label">Put protection · edit</span>
        </div>
        <div className="pp-form">
          <div className="qa-field">
            <label>Cost paid (premium, USD)</label>
            <input
              type="number"
              step="10"
              className="np-input qa-amount"
              value={totalCost}
              onChange={(e) => setTotalCost(e.target.value)}
              placeholder="e.g. 540"
            />
            <div className="pp-form-hint">
              {previewTotal && !isNaN(previewTotal) ? 'total premium you paid' : ''}
            </div>
          </div>
          <div className="qa-field">
            <label>Expiry date</label>
            <input
              type="date"
              className="np-input"
              value={expiry}
              onChange={(e) => setExpiry(e.target.value)}
            />
            <div className="pp-form-hint">
              {expiry ? `${previewTotalDays} days from today` : ''}
            </div>
          </div>
          <div className="qa-field">
            <label>Contracts</label>
            <input
              type="number"
              step="1"
              min="1"
              className="np-input"
              value={contracts}
              onChange={(e) => setContracts(e.target.value)}
              placeholder="e.g. 3"
            />
            <div className="pp-form-hint">each contract = 100 shares</div>
          </div>
          <div className="qa-field">
            <label>Strike price (USD)</label>
            <input
              type="number"
              step="0.50"
              className="np-input"
              value={strike}
              onChange={(e) => setStrike(e.target.value)}
              placeholder="e.g. 480"
            />
            <div className="pp-form-hint">per-share strike</div>
          </div>
        </div>
        {previewTotal > 0 && previewTotalDays > 0 && (
          <div className="pp-form-preview">
            <span className="k">cost / day</span>
            <span className="v">{fmtUSD2(previewPerDay)}</span>
            <span className="sep">·</span>
            <span className="k">{previewTotalDays}</span>
            <span className="k-lbl">days</span>
          </div>
        )}
        {pendingSave && (
          <div className="pp-confirm">
            <span className="pp-confirm-q">
              Add put protection for <b>{ticker}</b> · {fmtUSD(pendingSave.total_cost)}
              {pendingSave.contracts != null && pendingSave.strike != null && (
                <span> · {pendingSave.contracts}× ${pendingSave.strike} strike</span>
              )}
              ?
            </span>
            <div className="pp-confirm-actions">
              <button className="np-btn ghost" onClick={() => setPendingSave(null)}>
                ✗ cancel
              </button>
              <button
                className="np-btn neon"
                onClick={() => {
                  onSave(pendingSave);
                  setPendingSave(null);
                }}
              >
                ✓ confirm save
              </button>
            </div>
          </div>
        )}
        <div className="pp-actions">
          {calc.has && (
            <button className="np-btn ghost pp-clear" onClick={onClear}>
              Clear protection
            </button>
          )}
          <div style={{ flex: 1 }} />
          <button className="np-btn ghost" onClick={onEditCancel}>Cancel</button>
          <button
            className="np-btn neon"
            onClick={() => {
              const n = parseFloat(totalCost);
              if (!expiry || isNaN(n) || n < 0) return;
              const c = contracts.trim() ? parseInt(contracts, 10) : NaN;
              const s = strike.trim() ? parseFloat(strike) : NaN;
              setPendingSave({
                total_cost: n,
                expiry,
                purchase_date: todayIso(),
                contracts: !isNaN(c) && c > 0 ? c : null,
                strike: !isNaN(s) && s > 0 ? s : null,
              });
            }}
            disabled={!expiry || !totalCost || isNaN(parseFloat(totalCost)) || parseFloat(totalCost) < 0 || pendingSave !== null}
          >
            ✓ Save protection
          </button>
        </div>
      </div>
    );
  }

  if (!calc.has) {
    return (
      <div className="pp-panel pp-empty">
        <div className="pp-hd">
          <span className="pp-hd-label">Put protection</span>
          <span className="pp-hd-sub">no protective put on this position</span>
        </div>
        <button className="np-btn add-gain" onClick={onEditStart}>
          + Add put protection
        </button>
      </div>
    );
  }

  const days = calc.days_to_expiry;
  return (
    <div
      className={
        'pp-panel pp-active' +
        (calc.expired ? ' pp-expired' : days <= 14 ? ' pp-warn' : '')
      }
    >
      <div className="pp-hd">
        <span className="pp-hd-label">Put protection</span>
        {calc.expired ? (
          <span className="pp-hd-status down">expired</span>
        ) : days <= 14 ? (
          <span className="pp-hd-status warn">expiring soon</span>
        ) : (
          <span className="pp-hd-status">active</span>
        )}
      </div>
      <div className="pp-stats">
        <div className="pp-stat">
          <div className="pp-stat-l">Cost paid</div>
          <div className="pp-stat-v down">−{fmtUSD(calc.total_cost)}</div>
          {calc.contracts != null && calc.strike != null ? (
            <div className="pp-stat-sub-line">
              {calc.contracts}× ${fmtUSD2(calc.strike).replace('$', '')} strike
            </div>
          ) : (
            <div className="pp-stat-sub-line">total premium</div>
          )}
        </div>
        <div className="pp-stat">
          <div className="pp-stat-l">Current value</div>
          {calc.current_value != null ? (
            <>
              <div className={'pp-stat-v ' + ((calc.mark_to_market_pl ?? 0) < 0 ? 'down' : 'up')}>
                −{fmtUSD(calc.current_value)}
              </div>
              <div className="pp-stat-sub-line">
                {(calc.mark_to_market_pl ?? 0) >= 0 ? '+' : '−'}{fmtUSD(Math.abs(calc.mark_to_market_pl ?? 0))} vs cost
              </div>
            </>
          ) : (
            <>
              <div className="pp-stat-v"><span className="muted">—</span></div>
              <div className="pp-stat-sub-line">
                {calc.contracts && calc.strike ? 'awaiting quote' : 'set contracts + strike'}
              </div>
            </>
          )}
        </div>
        <div className="pp-stat">
          <div className="pp-stat-l">Expiry</div>
          <div className="pp-stat-v">{fmtExpiry(calc.expiry)}</div>
          <div className="pp-stat-sub-line">{calc.total_days} day tenor</div>
        </div>
        <div className="pp-stat">
          <div className="pp-stat-l">Days remaining</div>
          <div className={'pp-stat-v ' + (calc.expired ? 'down' : days <= 14 ? 'warn' : '')}>
            {calc.expired ? '0' : days}
            <span className="pp-stat-unit">d</span>
          </div>
          <div className="pp-stat-sub-line">of {calc.total_days}</div>
        </div>
        <div className="pp-stat">
          <div className="pp-stat-l">Cost / day</div>
          <div className="pp-stat-v">{fmtUSD2(calc.cost_per_day)}</div>
          <div className="pp-stat-sub-line">derived</div>
        </div>
      </div>
      <div className="pp-progress">
        <div className="pp-progress-bar">
          <div
            className="pp-progress-fill"
            style={{
              width:
                calc.total_cost > 0
                  ? `${(calc.cost_incurred / calc.total_cost) * 100}%`
                  : '0%',
            }}
          />
        </div>
        <div className="pp-progress-l">
          <span>
            <span className="k">incurred</span> {fmtUSD(calc.cost_incurred)}
          </span>
          <span>
            <span className="k">remaining</span> {fmtUSD(calc.cost_remaining)}
          </span>
        </div>
      </div>
      <div className="pp-actions">
        <button className="np-btn ghost" onClick={onEditStart}>Edit</button>
        <button className="np-btn ghost pp-clear" onClick={onClear}>Clear</button>
      </div>
    </div>
  );
}
