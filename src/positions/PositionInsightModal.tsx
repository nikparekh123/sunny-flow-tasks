import { useEffect, useMemo, useState } from 'react';
import {
  closeRealizedPL,
  daysUntil,
  fmtUSD,
  fmtUSD2,
  fmtQty,
  type LiveOption,
  type OptionTrade,
  type PositionComputed,
} from './types';

/**
 * Position insight (read) modal — Tesla-style P&L dashboard for one ticker.
 *
 * Header → earnings strip → three big stats → 52-week bidirectional chart
 *   (premium collected vs paid) → live positions list → recent trade
 *   activity.
 *
 * Replaces the previous gain/expense view with a unified trade ledger.
 */

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const WEEK_COUNT = 52;

function mondayOf(d: Date): Date {
  const x = new Date(d);
  const day = (x.getUTCDay() + 6) % 7;
  x.setUTCDate(x.getUTCDate() - day);
  x.setUTCHours(0, 0, 0, 0);
  return x;
}
function weekIdxOf(iso: string, todayWeek: Date): number {
  const d = new Date(iso + 'T12:00:00Z');
  return Math.round((todayWeek.getTime() - mondayOf(d).getTime()) / WEEK_MS);
}

type Bucket = 'income' | 'invest' | 'yield';
const BUCKET_LABEL: Record<Bucket, string> = {
  income: 'Income',
  invest: 'Investment',
  yield: 'Yield',
};

interface Props {
  position: PositionComputed;
  trades: OptionTrade[];          // all option_trades for this ticker
  liveOpens: LiveOption[];
  realizedTotal: number;          // realized P&L on this ticker
  bucket?: Bucket;
  onClose: () => void;
  onSetEarningsDate: (p: { ticker: string; earnings_date: string | null }) => void;
  onSetStatus: (p: { ticker: string; status: 'open' | 'closed' }) => void;
  onOpenTrade: () => void;        // opens write modal in 'open' tab
  onCloseTrade: () => void;       // opens write modal in 'close' tab
  onDeletePosition: (ticker: string) => void;
}

export function PositionInsightModal({
  position,
  trades,
  liveOpens,
  realizedTotal,
  bucket,
  onClose,
  onSetEarningsDate,
  onSetStatus,
  onOpenTrade,
  onCloseTrade,
  onDeletePosition,
}: Props) {
  const [editingEarnings, setEditingEarnings] = useState(false);
  const [draftEarnings, setDraftEarnings] = useState(position.earnings_date ?? '');
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
    };
  }, [onClose]);

  const isClosed = position.status === 'closed';
  const todayWeek = useMemo(() => mondayOf(new Date()), []);

  // Per-week realized P&L from closed pairs. Each close row contributes
  // its signed P&L to the week the close happened. Open trades and
  // unmatched closes don't appear here — only the actual exit P&L.
  const realizedBins = useMemo(() => {
    const arr = Array.from({ length: WEEK_COUNT }, () => 0);
    const byId = new Map<string, OptionTrade>();
    for (const t of trades) byId.set(t.id, t);
    for (const t of trades) {
      if (t.action !== 'close' || !t.closes_trade_id) continue;
      const open = byId.get(t.closes_trade_id);
      if (!open) continue;
      const w = weekIdxOf(t.trade_date, todayWeek);
      if (w < 0 || w >= WEEK_COUNT) continue;
      arr[w] += closeRealizedPL(t, open);
    }
    return arr;
  }, [trades, todayWeek]);

  // Keep the "totals" object for the stat cards — still computed from
  // collected/paid flow, because the stat cards show premium volume.
  const totals = useMemo(() => {
    let collected = 0, paid = 0, callC = 0, callP = 0, putC = 0, putP = 0;
    const byId = new Map<string, OptionTrade>();
    for (const t of trades) byId.set(t.id, t);
    for (const t of trades) {
      const notional = t.contracts * 100 * t.premium;
      const isCashIn =
        (t.action === 'open' && t.direction === 'short') ||
        (t.action === 'close' && t.direction === 'long');
      if (isCashIn) {
        collected += notional;
        if (t.option_type === 'call') callC += notional; else putC += notional;
      } else {
        paid += notional;
        if (t.option_type === 'call') callP += notional; else putP += notional;
      }
    }
    return { collected, paid, callC, callP, putC, putP };
  }, [trades]);

  const earnDays = position.earnings_date ? daysUntil(position.earnings_date) : null;
  const earnUrgency: 'urgent' | 'soon' | 'queued' | null =
    earnDays == null || earnDays < 0 ? null
    : earnDays <= 2 ? 'urgent'
    : earnDays <= 7 ? 'soon'
    : earnDays <= 30 ? 'queued'
    : null;

  const saveEarnings = () => {
    onSetEarningsDate({
      ticker: position.ticker,
      earnings_date: draftEarnings || null,
    });
    setEditingEarnings(false);
  };

  // Recent activity feed — trades sorted desc with realized P&L on closes.
  const feed = useMemo(() => {
    const byId = new Map<string, OptionTrade>();
    for (const t of trades) byId.set(t.id, t);
    return [...trades]
      .sort((a, b) => b.trade_date.localeCompare(a.trade_date))
      .slice(0, 14)
      .map((t) => {
        const realized = t.action === 'close' && t.closes_trade_id
          ? closeRealizedPL(t, byId.get(t.closes_trade_id)!)
          : 0;
        const cashFlow = t.contracts * 100 * t.premium *
          ((t.action === 'open' && t.direction === 'short') ||
           (t.action === 'close' && t.direction === 'long') ? 1 : -1);
        return { t, realized, cashFlow };
      });
  }, [trades]);

  return (
    <div className="pi-stage" onClick={onClose}>
      <div className="pi-modal" role="dialog" onClick={(e) => e.stopPropagation()}>
        {/* Header */}
        <div className="pi-head">
          <div className="pi-head-left">
            <h2 className="pi-ticker">{position.ticker}</h2>
            <div className="pi-sub">
              {bucket && <span>{BUCKET_LABEL[bucket]}</span>}
              {bucket && <span className="dot">·</span>}
              <span>{position.sector}</span>
              {!isClosed && (
                <>
                  <span className="dot">·</span>
                  <span>{fmtQty(position.quantity)} sh @ {fmtUSD2(position.avg_cost)}</span>
                </>
              )}
              {isClosed && <span className="pi-pill-closed">closed</span>}
            </div>
          </div>
          <button className="pi-icon-btn" onClick={onClose}>✕ Close</button>
        </div>

        {/* Earnings strip */}
        <div className="pi-earn-strip">
          {editingEarnings ? (
            <div className="pi-earn-edit">
              <input
                type="date"
                className="pp-input mono"
                value={draftEarnings}
                onChange={(e) => setDraftEarnings(e.target.value)}
                autoFocus
              />
              <button className="pi-link" onClick={saveEarnings}>save</button>
              <button className="pi-link muted" onClick={() => { setDraftEarnings(position.earnings_date ?? ''); setEditingEarnings(false); }}>
                cancel
              </button>
              {position.earnings_date && (
                <button
                  className="pi-link danger"
                  onClick={() => { setDraftEarnings(''); onSetEarningsDate({ ticker: position.ticker, earnings_date: null }); setEditingEarnings(false); }}
                >
                  clear
                </button>
              )}
            </div>
          ) : position.earnings_date ? (
            <div className={'pi-earn ' + (earnUrgency ?? '')}>
              <span className="pi-earn-icon">📅</span>
              <span className="pi-earn-main">
                Earnings{' '}
                {earnDays === 0 ? <b>today</b>
                  : earnDays === 1 ? <b>tomorrow</b>
                  : earnDays != null && earnDays > 0 ? <>in <b>{earnDays} days</b></>
                  : <>{Math.abs(earnDays ?? 0)} days ago</>}
              </span>
              <span className="pi-earn-date">· {position.earnings_date}</span>
              <button className="pi-link" onClick={() => setEditingEarnings(true)}>edit</button>
            </div>
          ) : (
            <button className="pi-link pi-add-earn" onClick={() => setEditingEarnings(true)}>
              + Add earnings date
            </button>
          )}
        </div>

        {/* Three big stat numbers */}
        <div className="pi-stats">
          <div className="pi-stat">
            <div className="pi-stat-l">↑ Premium collected · 52wk</div>
            <div className="pi-stat-v pos">{fmtUSD(totals.collected)}</div>
            <div className="pi-stat-sub">
              {totals.callC > 0 && `C ${fmtUSD(totals.callC)}`}
              {totals.callC > 0 && totals.putC > 0 && ' · '}
              {totals.putC > 0 && `P ${fmtUSD(totals.putC)}`}
              {totals.collected === 0 && '—'}
            </div>
          </div>
          <div className="pi-stat">
            <div className="pi-stat-l">↓ Premium paid · 52wk</div>
            <div className="pi-stat-v neg">−{fmtUSD(totals.paid)}</div>
            <div className="pi-stat-sub">
              {totals.callP > 0 && `C ${fmtUSD(totals.callP)}`}
              {totals.callP > 0 && totals.putP > 0 && ' · '}
              {totals.putP > 0 && `P ${fmtUSD(totals.putP)}`}
              {totals.paid === 0 && '—'}
            </div>
          </div>
          <div className="pi-stat">
            <div className="pi-stat-l">Realized P&amp;L</div>
            <div className={'pi-stat-v ' + (realizedTotal < 0 ? 'neg' : realizedTotal > 0 ? 'pos' : '')}>
              {realizedTotal >= 0 ? fmtUSD(realizedTotal) : '−' + fmtUSD(Math.abs(realizedTotal))}
            </div>
            <div className="pi-stat-sub">from closed pairs</div>
          </div>
        </div>

        {/* Realized P&L chart — one bar per week, signed */}
        <ChartRealized
          bins={realizedBins}
          earningsWeekIdx={position.earnings_date ? weekIdxOf(position.earnings_date, todayWeek) : null}
        />

        {/* Live positions list */}
        <div className="pi-activity">
          <div className="pi-section-l">Live positions · {liveOpens.length}</div>
          {liveOpens.length === 0 ? (
            <div className="pi-activity-empty">No live option positions on {position.ticker}.</div>
          ) : (
            <div className="pi-activity-list">
              {liveOpens.map((lo) => {
                const sign = lo.open.direction === 'short' ? '−' : '+';
                const cls = lo.open.direction === 'short' ? 'neg' : 'pos';
                return (
                  <div key={lo.open.id} className="pi-activity-row">
                    <span className={'pi-mini-glyph ' + cls}>
                      {lo.open.option_type === 'put' ? 'P' : 'C'}
                    </span>
                    <span className="pi-activity-date">{lo.open.trade_date}</span>
                    <span className={'pi-activity-amt ' + cls}>
                      {sign}{lo.remaining_contracts} @ ${lo.open.strike}
                    </span>
                    <span className="pi-activity-label">
                      exp {lo.open.expiry} · ${lo.open.premium}/sh
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Recent activity */}
        <div className="pi-activity">
          <div className="pi-section-l">Recent activity</div>
          {feed.length === 0 ? (
            <div className="pi-activity-empty">No trades yet — open a position to start.</div>
          ) : (
            <div className="pi-activity-list">
              {feed.map(({ t, realized, cashFlow }) => {
                const cls = cashFlow > 0 ? 'pos' : 'neg';
                return (
                  <div key={t.id} className="pi-activity-row">
                    <span className={'pi-mini-glyph ' + cls}>
                      {t.option_type === 'put' ? 'P' : 'C'}
                    </span>
                    <span className="pi-activity-date">{t.trade_date}</span>
                    <span className={'pi-activity-amt ' + cls}>
                      {cashFlow >= 0 ? fmtUSD(cashFlow) : '−' + fmtUSD(Math.abs(cashFlow))}
                    </span>
                    <span className="pi-activity-label">
                      {t.action} {t.direction} {t.option_type} {t.contracts}× ${t.strike}
                      {t.action === 'close' && realized !== 0 && (
                        <span className={'pi-realized ' + (realized > 0 ? 'pos' : 'neg')}>
                          {' '}· {realized >= 0 ? '+' : '−'}{fmtUSD(Math.abs(realized))} realized
                        </span>
                      )}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="pi-foot">
          <div className="pi-foot-start">
            <button
              className="pi-link danger"
              onClick={() => onSetStatus({ ticker: position.ticker, status: isClosed ? 'open' : 'closed' })}
            >
              {isClosed ? '↻ Reopen position' : '✕ Mark position closed'}
            </button>
            {!confirmingDelete && (
              <button
                className="pi-link danger pi-link-strong"
                onClick={() => setConfirmingDelete(true)}
              >
                🗑 Delete position
              </button>
            )}
            {confirmingDelete && (
              <div className="pi-confirm-chip">
                <span className="pi-confirm-q">
                  Delete <b>{position.ticker}</b> · {trades.length} trade{trades.length === 1 ? '' : 's'}?
                </span>
                <button
                  className="pi-link"
                  onClick={() => setConfirmingDelete(false)}
                >
                  ✗ cancel
                </button>
                <button
                  className="pi-link danger pi-link-strong"
                  onClick={() => {
                    onDeletePosition(position.ticker);
                    setConfirmingDelete(false);
                  }}
                >
                  ✓ confirm delete
                </button>
              </div>
            )}
          </div>
          <div className="pi-foot-end">
            <button
              className="pp-btn pp-btn-text"
              onClick={onCloseTrade}
              disabled={liveOpens.length === 0}
              title={liveOpens.length === 0 ? 'No live positions to close' : ''}
            >
              − Close position
            </button>
            <button className="pp-btn pp-btn-neon" onClick={onOpenTrade}>+ Open position</button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Chart ────────────────────────────────────────────────────────────

/**
 * Realized P&L chart — one signed bar per week. The bar represents the
 * sum of realized P&L from closes that happened in that week (each close
 * contributes `closeRealizedPL(close, matched_open)`).
 *
 *   - Up green bar  = profitable closing week
 *   - Down coral bar = lossy closing week
 *   - Empty weeks have no bar at all
 *
 * Open trades and unmatched closes don't appear — only the actual exit
 * P&L registered on closed pairs.
 */
function ChartRealized({
  bins, earningsWeekIdx,
}: {
  bins: number[];                     // signed realized P&L per week
  earningsWeekIdx: number | null;
}) {
  const maxAbs = Math.max(1, ...bins.map(Math.abs));
  const niceMax = roundUpNice(maxAbs);
  const total = bins.reduce((s, v) => s + v, 0);

  const W = 100;
  const H = 240;
  const midY = H / 2;
  const half = midY - 12;
  const colCount = bins.length;
  const colW = W / colCount;
  const barW = colW * 0.7;

  const hasData = bins.some((v) => v !== 0);

  return (
    <div className="pi-chart">
      <div className="pi-chart-canvas">
        <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="pi-chart-svg">
          {/* Zero baseline + amplitude guides */}
          <line x1="0" y1={midY} x2={W} y2={midY} stroke="rgba(30,90,80,0.7)" strokeWidth="0.18" />
          <line x1="0" y1={midY - half}     x2={W} y2={midY - half}     stroke="rgba(30,90,80,0.25)" strokeWidth="0.12" strokeDasharray="0.4,0.6" />
          <line x1="0" y1={midY - half / 2} x2={W} y2={midY - half / 2} stroke="rgba(30,90,80,0.15)" strokeWidth="0.1"  strokeDasharray="0.3,0.7" />
          <line x1="0" y1={midY + half / 2} x2={W} y2={midY + half / 2} stroke="rgba(30,90,80,0.15)" strokeWidth="0.1"  strokeDasharray="0.3,0.7" />
          <line x1="0" y1={midY + half}     x2={W} y2={midY + half}     stroke="rgba(30,90,80,0.25)" strokeWidth="0.12" strokeDasharray="0.4,0.6" />

          {/* Earnings vertical neon line */}
          {earningsWeekIdx != null && earningsWeekIdx >= 0 && earningsWeekIdx < colCount && (
            <line
              x1={(colCount - earningsWeekIdx - 0.5) * colW}
              y1="0"
              x2={(colCount - earningsWeekIdx - 0.5) * colW}
              y2={H}
              stroke="var(--navi-neon)"
              strokeWidth="0.3"
              strokeDasharray="1,1"
              opacity="0.7"
            />
          )}

          {/* Bars — newest on the right. Positive bars go up green; negative
              go down coral. Tiny weeks (<1% of niceMax) get a 0.3px stub
              so the user can still see "something happened" rather than
              nothing. */}
          {bins.map((v, i) => {
            if (v === 0) return null;
            const x = (colCount - i - 1) * colW + (colW - barW) / 2;
            const h = Math.max(0.4, (Math.abs(v) / niceMax) * half);
            if (v > 0) {
              return (
                <rect
                  key={i}
                  x={x}
                  y={midY - h}
                  width={barW}
                  height={h}
                  fill="var(--navi-positive)"
                  rx="0.3"
                />
              );
            }
            return (
              <rect
                key={i}
                x={x}
                y={midY}
                width={barW}
                height={h}
                fill="var(--navi-negative)"
                rx="0.3"
              />
            );
          })}
        </svg>

        {/* Right-side Y axis scale */}
        <div className="pi-chart-yaxis">
          <span className="pi-chart-y-top">+{fmtUSD(niceMax)}</span>
          <span className="pi-chart-y-mid">+{fmtUSD(niceMax / 2)}</span>
          <span className="pi-chart-y-zero">$0</span>
          <span className="pi-chart-y-mid">−{fmtUSD(niceMax / 2)}</span>
          <span className="pi-chart-y-bot">−{fmtUSD(niceMax)}</span>
        </div>
      </div>

      <div className="pi-chart-xaxis">
        <span>−12mo</span>
        <span>−9mo</span>
        <span>−6mo</span>
        <span>−3mo</span>
        <span>now</span>
      </div>

      <div className="pi-chart-legend">
        <span className="pi-chart-legend-dot" style={{ background: 'var(--navi-positive)' }} />Profitable close
        <span className="pi-chart-legend-sep">·</span>
        <span className="pi-chart-legend-dot" style={{ background: 'var(--navi-negative)' }} />Lossy close
        <span className="pi-chart-legend-sep">·</span>
        <span className="pi-chart-total">
          52w total <b className={total < 0 ? 'neg' : total > 0 ? 'pos' : ''}>
            {total >= 0 ? '+' : '−'}{fmtUSD(Math.abs(total))}
          </b>
        </span>
        {!hasData && <span className="pi-chart-total muted">no closes yet</span>}
      </div>
    </div>
  );
}

/** Round a value up to a "nice" round number for axis labels.
 *  e.g. 4321 → 5000, 87000 → 100000, 14 → 20. */
function roundUpNice(v: number): number {
  if (v <= 0) return 1;
  const exp = Math.floor(Math.log10(v));
  const base = Math.pow(10, exp);
  const norm = v / base;
  let nice: number;
  if (norm <= 1) nice = 1;
  else if (norm <= 2) nice = 2;
  else if (norm <= 5) nice = 5;
  else nice = 10;
  return nice * base;
}
