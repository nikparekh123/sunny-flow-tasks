import { useEffect, useMemo, useState } from 'react';
import {
  fmtUSD,
  fmtUSD2,
  fmtQty,
  daysUntil,
  type ExpenseEntry,
  type GainEntry,
  type GainSource,
  type PositionComputed,
  type PutProtectionRow,
} from './types';

/**
 * Position insight (read) modal — Tesla-style P&L dashboard for one ticker.
 *
 * Header carries the earnings-date strip. A bidirectional weekly bar chart
 * shows gains stacked upward and expenses stacked downward, source-coded.
 * Breakdown chips + a chronological activity list sit below. The two
 * actions at the bottom ("+ Log gain" / "+ Log expense") open the write
 * modal (PositionDetailModal).
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

const SOURCE_LABEL: Record<GainSource, string> = {
  stock: 'Stock', call: 'Call', put: 'Put',
};

const SOURCE_GLYPH: Record<GainSource, string> = {
  stock: 'S', call: 'C', put: 'P',
};

interface Props {
  position: PositionComputed;
  entries: GainEntry[];
  expenseEntries: ExpenseEntry[];
  putProtection: PutProtectionRow | undefined;
  bucket?: Bucket;
  onClose: () => void;
  onSetEarningsDate: (p: { ticker: string; earnings_date: string | null }) => void;
  onSetStatus: (p: { ticker: string; status: 'open' | 'closed' }) => void;
  onAddGain: () => void;        // opens the write modal in gain mode
  onAddExpense: () => void;     // opens the write modal in expense mode
}

export function PositionInsightModal({
  position,
  entries,
  expenseEntries,
  putProtection,
  bucket,
  onClose,
  onSetEarningsDate,
  onSetStatus,
  onAddGain,
  onAddExpense,
}: Props) {
  const [editingEarnings, setEditingEarnings] = useState(false);
  const [draftEarnings, setDraftEarnings] = useState(position.earnings_date ?? '');

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

  // Aggregate weekly: gains stacked upward, expenses stacked downward.
  // Each bin holds amounts per source for both directions.
  type Bin = {
    gains:    { stock: number; call: number; put: number };
    expenses: { stock: number; call: number; put: number };
  };
  const bins: Bin[] = useMemo(() => {
    const arr: Bin[] = Array.from({ length: WEEK_COUNT }, () => ({
      gains:    { stock: 0, call: 0, put: 0 },
      expenses: { stock: 0, call: 0, put: 0 },
    }));
    for (const e of entries) {
      const w = weekIdxOf(e.gain_date, todayWeek);
      if (w >= 0 && w < WEEK_COUNT) arr[w].gains[e.source] += e.amount;
    }
    for (const e of expenseEntries) {
      const w = weekIdxOf(e.expense_date, todayWeek);
      if (w >= 0 && w < WEEK_COUNT) arr[w].expenses[e.source] += Math.abs(e.amount);
    }
    // Synthetic put-protection expense on its purchase week, so the chart
    // tells the full story without forcing a separate ledger row.
    if (putProtection && putProtection.total_cost > 0 && putProtection.purchase_date) {
      const w = weekIdxOf(putProtection.purchase_date, todayWeek);
      if (w >= 0 && w < WEEK_COUNT) arr[w].expenses.put += putProtection.total_cost;
    }
    return arr;
  }, [entries, expenseEntries, putProtection, todayWeek]);

  const totals = useMemo(() => {
    let gain = { stock: 0, call: 0, put: 0, total: 0 };
    let exp  = { stock: 0, call: 0, put: 0, total: 0 };
    for (const b of bins) {
      (Object.keys(b.gains) as GainSource[]).forEach((k) => {
        gain[k] += b.gains[k];
        gain.total += b.gains[k];
        exp[k] += b.expenses[k];
        exp.total += b.expenses[k];
      });
    }
    return { gain, exp, net: gain.total - exp.total };
  }, [bins]);

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

  // Merge all entries into a single chronological feed for the activity list.
  type FeedRow = {
    id: string;
    date: string;
    source: GainSource;
    amount: number;  // signed: gains positive, expenses negative
    label: string;
    kind: 'gain' | 'expense' | 'protection';
  };
  const feed: FeedRow[] = useMemo(() => {
    const out: FeedRow[] = [];
    for (const e of entries) {
      out.push({
        id: e.id, date: e.gain_date, source: e.source,
        amount: e.amount, label: e.note || `${SOURCE_LABEL[e.source]} gain`,
        kind: 'gain',
      });
    }
    for (const e of expenseEntries) {
      out.push({
        id: e.id, date: e.expense_date, source: e.source,
        amount: -Math.abs(e.amount), label: e.note || `${SOURCE_LABEL[e.source]} expense`,
        kind: 'expense',
      });
    }
    if (putProtection && putProtection.total_cost > 0) {
      out.push({
        id: `pp:${putProtection.id}`,
        date: putProtection.purchase_date,
        source: 'put',
        amount: -putProtection.total_cost,
        label: 'put protection',
        kind: 'protection',
      });
    }
    return out.sort((a, b) => b.date.localeCompare(a.date)).slice(0, 12);
  }, [entries, expenseEntries, putProtection]);

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

        {/* Two big stat numbers */}
        <div className="pi-stats">
          <div className="pi-stat">
            <div className="pi-stat-l">↑ Gains · 52wk</div>
            <div className="pi-stat-v pos">{fmtUSD(totals.gain.total)}</div>
            <div className="pi-stat-sub">{entries.length} {entries.length === 1 ? 'entry' : 'entries'}</div>
          </div>
          <div className="pi-stat">
            <div className="pi-stat-l">↓ Expenses · 52wk</div>
            <div className="pi-stat-v neg">−{fmtUSD(totals.exp.total)}</div>
            <div className="pi-stat-sub">
              {expenseEntries.length + (putProtection ? 1 : 0)} items
            </div>
          </div>
          <div className="pi-stat">
            <div className="pi-stat-l">Net realized</div>
            <div className={'pi-stat-v ' + (totals.net < 0 ? 'neg' : totals.net > 0 ? 'pos' : '')}>
              {totals.net >= 0 ? fmtUSD(totals.net) : '−' + fmtUSD(Math.abs(totals.net))}
            </div>
            <div className="pi-stat-sub">last 52 weeks</div>
          </div>
        </div>

        {/* Bidirectional chart */}
        <ChartBidirectional bins={bins} earningsWeekIdx={
          position.earnings_date ? weekIdxOf(position.earnings_date, todayWeek) : null
        } />

        {/* Source breakdown */}
        <div className="pi-breakdown">
          <SourceBreakdown title="↑ Gains by source" totals={totals.gain} kind="gain" />
          <SourceBreakdown title="↓ Expenses by source" totals={totals.exp} kind="expense" />
        </div>

        {/* Recent activity */}
        <div className="pi-activity">
          <div className="pi-section-l">Recent activity</div>
          {feed.length === 0 ? (
            <div className="pi-activity-empty">No entries yet — log a gain or expense to start.</div>
          ) : (
            <div className="pi-activity-list">
              {feed.map((row) => (
                <div key={row.id} className="pi-activity-row">
                  <span className={'pi-mini-glyph ' + (row.kind === 'gain' ? 'pos' : 'neg')}>
                    {SOURCE_GLYPH[row.source]}
                  </span>
                  <span className="pi-activity-date">{row.date}</span>
                  <span className={'pi-activity-amt ' + (row.amount < 0 ? 'neg' : 'pos')}>
                    {row.amount < 0 ? '−' : ''}{fmtUSD(Math.abs(row.amount))}
                  </span>
                  <span className="pi-activity-label">{row.label}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Footer actions */}
        <div className="pi-foot">
          <button
            className="pi-link danger"
            onClick={() => onSetStatus({ ticker: position.ticker, status: isClosed ? 'open' : 'closed' })}
          >
            {isClosed ? '↻ Reopen position' : '✕ Mark position closed'}
          </button>
          <div className="pi-foot-end">
            <button className="pp-btn pp-btn-text" onClick={onAddExpense}>+ Log expense</button>
            <button className="pp-btn pp-btn-neon" onClick={onAddGain}>+ Log gain</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/** Bidirectional bar chart — gains stack upward, expenses stack downward.
 *  All sources color-coded; each week is a single composite bar. */
function ChartBidirectional({
  bins, earningsWeekIdx,
}: {
  bins: Array<{ gains: Record<GainSource, number>; expenses: Record<GainSource, number> }>;
  earningsWeekIdx: number | null;
}) {
  const SOURCES: GainSource[] = ['stock', 'call', 'put'];

  // Find the max absolute value for scaling. Y axis is symmetric around zero.
  const maxAbs = Math.max(
    1,
    ...bins.flatMap((b) => [
      SOURCES.reduce((s, k) => s + b.gains[k], 0),
      SOURCES.reduce((s, k) => s + b.expenses[k], 0),
    ]),
  );

  const W = 100;        // logical width (per cent)
  const H = 220;        // total height in px
  const midY = H / 2;
  const half = midY - 8; // px usable on each side of zero
  const colCount = bins.length;
  const colW = W / colCount;
  const barW = colW * 0.55;

  const gainColor: Record<GainSource, string> = {
    stock: 'var(--navi-fg2)',     // muted teal
    call:  'var(--navi-neon)',    // hero color
    put:   'var(--navi-positive)', // light green
  };
  const expColor: Record<GainSource, string> = {
    stock: 'var(--navi-warning)',  // amber
    call:  'rgba(232,112,96,.6)',  // softer red
    put:   'var(--navi-negative)', // coral — the dominant expense in this app
  };

  return (
    <div className="pi-chart">
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="pi-chart-svg">
        {/* Grid */}
        <line x1="0" y1={midY} x2={W} y2={midY} stroke="rgba(30,90,80,0.5)" strokeWidth="0.2" />
        <line x1="0" y1={midY - half} x2={W} y2={midY - half} stroke="rgba(30,90,80,0.2)" strokeWidth="0.15" strokeDasharray="0.5,0.5" />
        <line x1="0" y1={midY + half} x2={W} y2={midY + half} stroke="rgba(30,90,80,0.2)" strokeWidth="0.15" strokeDasharray="0.5,0.5" />

        {/* Earnings vertical marker */}
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

        {/* Bars — newest week on the right, like Tesla */}
        {bins.map((b, i) => {
          const x = (colCount - i - 1) * colW + (colW - barW) / 2;
          const gainTotal = SOURCES.reduce((s, k) => s + b.gains[k], 0);
          const expTotal = SOURCES.reduce((s, k) => s + b.expenses[k], 0);
          const gainPx = (gainTotal / maxAbs) * half;
          const expPx  = (expTotal  / maxAbs) * half;

          // Stack gains upward (Stock at base, Call on top, Put on top of that)
          let yCursor = midY;
          const gainSegs = SOURCES.map((k) => {
            const seg = (b.gains[k] / maxAbs) * half;
            const segY = yCursor - seg;
            const out = { k, y: segY, h: seg, fill: gainColor[k] };
            yCursor -= seg;
            return out;
          });
          // Stack expenses downward
          yCursor = midY;
          const expSegs = SOURCES.map((k) => {
            const seg = (b.expenses[k] / maxAbs) * half;
            const out = { k, y: yCursor, h: seg, fill: expColor[k] };
            yCursor += seg;
            return out;
          });
          void gainPx; void expPx; // available for tooltip later
          return (
            <g key={i}>
              {gainSegs.map((s) => s.h > 0 && (
                <rect key={'g'+s.k} x={x} y={s.y} width={barW} height={s.h} fill={s.fill} rx="0.2" />
              ))}
              {expSegs.map((s) => s.h > 0 && (
                <rect key={'e'+s.k} x={x} y={s.y} width={barW} height={s.h} fill={s.fill} rx="0.2" />
              ))}
            </g>
          );
        })}
      </svg>
      {/* X axis labels — just a sparse tick set */}
      <div className="pi-chart-xaxis">
        <span>−12mo</span>
        <span>−9mo</span>
        <span>−6mo</span>
        <span>−3mo</span>
        <span>now</span>
      </div>
      <div className="pi-chart-legend">
        <span className="pi-chart-legend-dot" style={{ background: 'var(--navi-fg2)' }} />Stock
        <span className="pi-chart-legend-dot" style={{ background: 'var(--navi-neon)' }} />Call
        <span className="pi-chart-legend-dot" style={{ background: 'var(--navi-positive)' }} />Put gain
        <span className="pi-chart-legend-sep">·</span>
        <span className="pi-chart-legend-dot" style={{ background: 'var(--navi-negative)' }} />Put expense
        <span className="pi-chart-legend-dot" style={{ background: 'var(--navi-warning)' }} />Stock exp
      </div>
    </div>
  );
}

function SourceBreakdown({
  title, totals, kind,
}: {
  title: string;
  totals: { stock: number; call: number; put: number; total: number };
  kind: 'gain' | 'expense';
}) {
  if (totals.total === 0) {
    return (
      <div className="pi-bd-card">
        <div className="pi-section-l">{title}</div>
        <div className="pi-bd-empty">—</div>
      </div>
    );
  }
  const rows: Array<{ k: GainSource; pct: number; amt: number }> = [
    { k: 'stock', pct: (totals.stock / totals.total) * 100, amt: totals.stock },
    { k: 'call',  pct: (totals.call  / totals.total) * 100, amt: totals.call },
    { k: 'put',   pct: (totals.put   / totals.total) * 100, amt: totals.put },
  ].filter((r) => r.amt > 0).sort((a, b) => b.amt - a.amt);
  return (
    <div className="pi-bd-card">
      <div className="pi-section-l">{title}</div>
      <div className="pi-bd-rows">
        {rows.map((r) => (
          <div key={r.k} className="pi-bd-row">
            <span className={'pi-mini-glyph ' + (kind === 'gain' ? 'pos' : 'neg')}>{SOURCE_GLYPH[r.k]}</span>
            <span className="pi-bd-pct">{r.pct.toFixed(0)}%</span>
            <span className="pi-bd-label">{SOURCE_LABEL[r.k]}</span>
            <span className={'pi-bd-amt ' + (kind === 'gain' ? 'pos' : 'neg')}>
              {kind === 'expense' ? '−' : ''}{fmtUSD(r.amt)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
