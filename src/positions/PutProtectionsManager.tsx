import { useMemo } from 'react';
import { computePutProtection, fmtUSD, type PutProtectionRow } from './types';

interface Props {
  putProtectionByTicker: Map<string, PutProtectionRow>;
  onTickerClick: (ticker: string) => void;
  onClear: (ticker: string) => void;
}

/**
 * Small panel that lists every position currently carrying a put-protection
 * contract. Gives the user a single place to spot a stray entry (e.g. one
 * accidentally added against the wrong ticker) and clear it without leaving
 * the page.
 *
 * Renders nothing when there are zero protections — keeps the page calm.
 */
export function PutProtectionsManager({ putProtectionByTicker, onTickerClick, onClear }: Props) {
  const rows = useMemo(() => {
    const out: Array<{ ticker: string; total_cost: number; expiry: string | null; expired: boolean; days_to_expiry: number }> = [];
    putProtectionByTicker.forEach((pp, ticker) => {
      const calc = computePutProtection(pp);
      out.push({
        ticker,
        total_cost: calc.total_cost,
        expiry: calc.expiry,
        expired: calc.expired,
        days_to_expiry: calc.days_to_expiry,
      });
    });
    return out.sort((a, b) => b.total_cost - a.total_cost);
  }, [putProtectionByTicker]);

  if (rows.length === 0) return null;

  const total = rows.reduce((s, r) => s + r.total_cost, 0);

  return (
    <div className="pp-manager">
      <div className="pp-manager-hd">
        <span className="pp-manager-l">Put protections</span>
        <span className="pp-manager-ct">
          {rows.length} active · −{fmtUSD(total)} total
        </span>
      </div>
      <div className="pp-manager-list">
        {rows.map((r) => (
          <div key={r.ticker} className={'pp-manager-row' + (r.expired ? ' expired' : '')}>
            <span
              className="ticker clickable"
              onClick={() => onTickerClick(r.ticker)}
              title="Open position detail"
            >
              {r.ticker}
            </span>
            <span className="pp-manager-cost down">−{fmtUSD(r.total_cost)}</span>
            <span className="pp-manager-exp">
              {r.expired
                ? 'expired'
                : r.expiry
                  ? `exp ${r.expiry} · ${r.days_to_expiry}d`
                  : '—'}
            </span>
            <button
              className="np-btn ghost pp-manager-clear"
              onClick={() => onClear(r.ticker)}
              title={`Remove put protection on ${r.ticker}`}
            >
              ✕ clear
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
