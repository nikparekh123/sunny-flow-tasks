import { useEffect, useRef, useState } from 'react';
import type { GainSource, PositionRow } from './types';
import { fmtUSD } from './types';

const SOURCE_META: Record<GainSource, { label: string; short: string }> = {
  stock: { label: 'Stock', short: 'S' },
  call:  { label: 'Call',  short: 'C' },
  put:   { label: 'Put',   short: 'P' },
};

interface Props {
  positions: PositionRow[];
  onClose: () => void;
  onSave: (p: {
    ticker: string;
    gain_date: string;
    source: GainSource;
    amount: number;
    note: string;
  }) => void;
  /** Optional preselected ticker (e.g. opened from a position card). */
  defaultTicker?: string;
}

const todayIso = () => new Date().toISOString().slice(0, 10);

export function QuickAddGainModal({ positions, onClose, onSave, defaultTicker }: Props) {
  const [ticker, setTicker] = useState(defaultTicker ?? positions[0]?.ticker ?? '');
  const [source, setSource] = useState<GainSource>('call');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [date, setDate] = useState(todayIso());
  const amountRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    amountRef.current?.focus();
  }, []);

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

  const submit = () => {
    const amt = parseFloat(amount);
    if (isNaN(amt) || amt === 0 || !ticker.trim() || !date) return;
    onSave({ ticker: ticker.trim().toUpperCase(), gain_date: date, source, amount: amt, note });
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && amount && ticker) submit();
  };

  return (
    <div className="np-modal-back" onClick={onClose} onKeyDown={onKeyDown}>
      <div className="np-modal qa-modal" onClick={(e) => e.stopPropagation()} onKeyDown={onKeyDown}>
        <div className="np-modal-hd">
          <div>
            <div className="np-modal-title">Log a gain</div>
            <div className="np-modal-sub">fast add · tab to advance · enter to save</div>
          </div>
          <button className="np-btn ghost" onClick={onClose}>✕ Close</button>
        </div>

        <div className="qa-grid">
          <div className="qa-field">
            <label>Ticker</label>
            <input
              className="np-input"
              list="qa-tickers"
              value={ticker}
              onChange={(e) => setTicker(e.target.value.toUpperCase())}
              placeholder="e.g. AAPL"
            />
            <datalist id="qa-tickers">
              {positions.map((p) => (
                <option key={p.ticker} value={p.ticker}>
                  {p.ticker} · {p.sector}
                </option>
              ))}
            </datalist>
          </div>

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
            <label>Amount (USD; − for losses)</label>
            <input
              ref={amountRef}
              className="np-input qa-amount"
              type="number"
              step="50"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0"
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

          <div className="qa-field full">
            <label>Note (optional)</label>
            <input
              className="np-input"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="strike, ex-div date, source, etc."
            />
          </div>
        </div>

        <div className="qa-foot">
          <div className="qa-preview">
            {amount && !isNaN(parseFloat(amount)) && ticker && (
              <>
                <span className={'rchip rk-' + source.charAt(0) + ' rchip-static'}>
                  {SOURCE_META[source].short}
                </span>
                <span style={{ fontFamily: 'var(--navi-font-mono)', color: 'var(--navi-fg1)' }}>
                  {ticker}
                </span>
                <span style={{ color: 'var(--navi-fg3)' }}>·</span>
                <span
                  style={{
                    fontFamily: 'var(--navi-font-mono)',
                    color: parseFloat(amount) < 0 ? 'var(--navi-negative)' : 'var(--navi-positive)',
                  }}
                >
                  {fmtUSD(parseFloat(amount))}
                </span>
                <span style={{ color: 'var(--navi-fg3)' }}>·</span>
                <span style={{ color: 'var(--navi-fg3)' }}>{date}</span>
              </>
            )}
          </div>
          <div className="qa-actions">
            <button className="np-btn ghost" onClick={onClose}>Cancel</button>
            <button
              className="np-btn neon"
              onClick={submit}
              disabled={!amount || !ticker || isNaN(parseFloat(amount))}
            >
              ✓ Save gain
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
