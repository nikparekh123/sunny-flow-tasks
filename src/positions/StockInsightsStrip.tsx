import { useMemo, useState } from 'react';
import {
  chipsForSignals,
  daysUntil,
  fmtCompact,
  fmtUSD,
  fmtUSD2,
  type LiveOption,
  type PositionComputed,
  type SignalChip,
  type TickerSignals,
} from './types';
import type { StrategyBucket } from './usePositions';

/**
 * Stock Insights strip — horizontally-scrolling row of compact per-ticker
 * cards. Replaces the old KPI tiles / strategy summary at the top of the
 * positions page.
 *
 * Card structure:
 *   compact  ~168×150 — ticker · price · day move · top-2 signals
 *   expanded ~336×280 — adds full signal breakdown + position + options
 *
 * Multi-select filter chips above the strip narrow the visible cards;
 * default sort is most-actionable-first (signal-count rank).
 */

interface Props {
  rows: PositionComputed[];
  signalsByTicker: Map<string, TickerSignals>;
  liveByTicker: Map<string, LiveOption[]>;
  overlayByTicker: Map<string, StrategyBucket>;
}

type FilterId =
  | 'below-200d'
  | 'above-200d'
  | 'stretched'
  | 'pullback'
  | 'oversold'
  | 'overbought'
  | 'down-5d'
  | 'up-5d'
  | 'down-21d'
  | 'up-21d'
  | 'big-mover'
  | 'earnings-7d'
  | 'earnings-30d'
  | 'has-live'
  | 'no-live'
  | 'above-cost'
  | 'below-cost'
  | `sector:${string}`;

interface CardModel {
  row: PositionComputed;
  signals?: TickerSignals;
  live: LiveOption[];
  chips: SignalChip[];
  dayPct: number | null;
  earningsDays: number | null;
  bucket?: StrategyBucket;
}

function dayChange(row: PositionComputed): number | null {
  if (row.current_price == null || row.prev_close == null || row.prev_close <= 0) return null;
  return ((row.current_price - row.prev_close) / row.prev_close) * 100;
}

const FILTER_GROUPS: Array<{
  label: string;
  filters: Array<{ id: FilterId; label: string }>;
}> = [
  {
    label: 'Trend',
    filters: [
      { id: 'below-200d', label: '↓ 200d' },
      { id: 'above-200d', label: '↑ 200d' },
      { id: 'stretched', label: 'Stretched' },
      { id: 'pullback', label: 'Pullback' },
    ],
  },
  {
    label: 'Momentum',
    filters: [
      { id: 'oversold', label: 'Oversold' },
      { id: 'overbought', label: 'Overbought' },
    ],
  },
  {
    label: 'Moves',
    filters: [
      { id: 'down-5d', label: 'Down 5d' },
      { id: 'up-5d', label: 'Up 5d' },
      { id: 'down-21d', label: 'Down 21d' },
      { id: 'up-21d', label: 'Up 21d' },
      { id: 'big-mover', label: 'Big mover' },
    ],
  },
  {
    label: 'Events',
    filters: [
      { id: 'earnings-7d', label: '📅 ≤7d' },
      { id: 'earnings-30d', label: '📅 ≤30d' },
    ],
  },
  {
    label: 'Position',
    filters: [
      { id: 'has-live', label: 'Has live opts' },
      { id: 'no-live', label: 'No live opts' },
      { id: 'above-cost', label: 'Above avg cost' },
      { id: 'below-cost', label: 'Below avg cost' },
    ],
  },
];

function predicate(card: CardModel, id: FilterId): boolean {
  const s = card.signals;
  const row = card.row;
  if (id.startsWith('sector:')) return row.sector === id.slice(7);
  switch (id) {
    case 'below-200d':
      return !!s && s.price != null && s.ma200 != null && s.ma200 > 0 && s.price < s.ma200;
    case 'above-200d':
      return !!s && s.price != null && s.ma200 != null && s.ma200 > 0 && s.price >= s.ma200;
    case 'stretched':
      return !!s && s.price != null && s.ma50 != null && s.ma50 > 0 &&
        ((s.price - s.ma50) / s.ma50) * 100 >= 10;
    case 'pullback':
      return !!s && s.price != null && s.ma50 != null && s.ma50 > 0 &&
        ((s.price - s.ma50) / s.ma50) * 100 <= -7;
    case 'oversold':
      return !!s && s.rsi14 != null && s.rsi14 <= 30;
    case 'overbought':
      return !!s && s.rsi14 != null && s.rsi14 >= 70;
    case 'down-5d':
      return !!s && s.chg_5d_pct != null && s.chg_5d_pct <= -5;
    case 'up-5d':
      return !!s && s.chg_5d_pct != null && s.chg_5d_pct >= 5;
    case 'down-21d':
      return !!s && s.chg_21d_pct != null && s.chg_21d_pct <= -10;
    case 'up-21d':
      return !!s && s.chg_21d_pct != null && s.chg_21d_pct >= 10;
    case 'big-mover':
      return card.dayPct != null && Math.abs(card.dayPct) >= 2;
    case 'earnings-7d':
      return card.earningsDays != null && card.earningsDays >= 0 && card.earningsDays <= 7;
    case 'earnings-30d':
      return card.earningsDays != null && card.earningsDays >= 0 && card.earningsDays <= 30;
    case 'has-live':
      return card.live.length > 0;
    case 'no-live':
      return card.live.length === 0;
    case 'above-cost':
      return row.current_price != null && row.current_price > row.avg_cost;
    case 'below-cost':
      return row.current_price != null && row.current_price < row.avg_cost;
  }
}

export function StockInsightsStrip({
  rows,
  signalsByTicker,
  liveByTicker,
  overlayByTicker,
}: Props) {
  const [active, setActive] = useState<Set<FilterId>>(new Set());
  const [expanded, setExpanded] = useState<string | null>(null);

  // Build per-ticker card models once.
  const allCards = useMemo<CardModel[]>(
    () =>
      rows.map((r) => {
        const s = signalsByTicker.get(r.ticker);
        const live = liveByTicker.get(r.ticker) ?? [];
        const chips = s ? chipsForSignals(s) : [];
        return {
          row: r,
          signals: s,
          live,
          chips,
          dayPct: dayChange(r),
          earningsDays: r.earnings_date ? daysUntil(r.earnings_date) : null,
          bucket: overlayByTicker.get(r.ticker),
        };
      }),
    [rows, signalsByTicker, liveByTicker, overlayByTicker],
  );

  // Dynamic sector chips — only sectors actually owned.
  const sectorFilters = useMemo(() => {
    const set = new Set<string>();
    for (const c of allCards) set.add(c.row.sector);
    return Array.from(set)
      .sort()
      .map((sec) => ({ id: `sector:${sec}` as FilterId, label: sec }));
  }, [allCards]);

  // Active-filter predicate (AND of all active).
  const matchesAll = (card: CardModel, filters: Set<FilterId>) => {
    for (const id of filters) if (!predicate(card, id)) return false;
    return true;
  };

  const visible = useMemo(() => {
    const matched = allCards.filter((c) => matchesAll(c, active));
    // Sort: most actionable first (chip count desc), then |21d move|.
    matched.sort((a, b) => {
      const ca = a.chips.length;
      const cb = b.chips.length;
      if (ca !== cb) return cb - ca;
      const am = Math.abs(a.signals?.chg_21d_pct ?? 0);
      const bm = Math.abs(b.signals?.chg_21d_pct ?? 0);
      return bm - am;
    });
    return matched;
  }, [allCards, active]);

  // Count = matches if we add THIS chip to the current filter set.
  const countFor = (id: FilterId): number => {
    if (active.has(id)) return visible.length;
    const test = new Set(active);
    test.add(id);
    return allCards.filter((c) => matchesAll(c, test)).length;
  };

  const toggle = (id: FilterId) => {
    setActive((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const clearAll = () => setActive(new Set());

  return (
    <div className="si-wrap">
      <div className="si-hd">
        <div className="si-title">Stock insights</div>
        <div className="si-count">
          {visible.length}/{allCards.length}
          {active.size > 0 && (
            <button className="si-clear" onClick={clearAll}>
              Clear ({active.size})
            </button>
          )}
        </div>
      </div>

      <div className="si-filters">
        {FILTER_GROUPS.map((g) => (
          <div key={g.label} className="si-fgroup">
            <span className="si-fgroup-k">{g.label}</span>
            {g.filters.map((f) => {
              const isOn = active.has(f.id);
              const count = countFor(f.id);
              const dim = !isOn && count === 0;
              return (
                <button
                  key={f.id}
                  className={'si-chip' + (isOn ? ' on' : '') + (dim ? ' dim' : '')}
                  onClick={() => toggle(f.id)}
                  disabled={dim}
                >
                  {f.label}
                  <span className="si-chip-ct">{count}</span>
                </button>
              );
            })}
          </div>
        ))}
        {sectorFilters.length > 0 && (
          <div className="si-fgroup">
            <span className="si-fgroup-k">Sector</span>
            {sectorFilters.map((f) => {
              const isOn = active.has(f.id);
              const count = countFor(f.id);
              const dim = !isOn && count === 0;
              return (
                <button
                  key={f.id}
                  className={'si-chip' + (isOn ? ' on' : '') + (dim ? ' dim' : '')}
                  onClick={() => toggle(f.id)}
                  disabled={dim}
                >
                  {f.label}
                  <span className="si-chip-ct">{count}</span>
                </button>
              );
            })}
          </div>
        )}
      </div>

      <div className="si-scroll">
        <div className="si-row">
          {visible.length === 0 ? (
            <div className="si-empty">No tickers match the active filters.</div>
          ) : (
            visible.map((c) => (
              <Card
                key={c.row.ticker}
                card={c}
                isExpanded={expanded === c.row.ticker}
                onToggle={() =>
                  setExpanded((cur) =>
                    cur === c.row.ticker ? null : c.row.ticker,
                  )
                }
              />
            ))
          )}
        </div>
      </div>
    </div>
  );
}

function Card({
  card,
  isExpanded,
  onToggle,
}: {
  card: CardModel;
  isExpanded: boolean;
  onToggle: () => void;
}) {
  const { row, signals, live, chips, dayPct, earningsDays, bucket } = card;

  return (
    <div
      className={'si-card' + (isExpanded ? ' expanded' : '')}
      onClick={onToggle}
      role="button"
      tabIndex={0}
    >
      {/* Top row */}
      <div className="si-card-top">
        <span className="si-card-tk">{row.ticker}</span>
        {earningsDays != null && earningsDays >= 0 && earningsDays <= 14 && (
          <span
            className={
              'si-card-earn ' + (earningsDays <= 7 ? 'urgent' : 'soon')
            }
            title={`Earnings ${row.earnings_date}`}
          >
            📅 {earningsDays === 0 ? 'today' : earningsDays + 'd'}
          </span>
        )}
      </div>

      {/* Price + day move */}
      <div className="si-card-price">
        {row.current_price != null ? fmtUSD2(row.current_price) : '—'}
      </div>
      {dayPct != null && (
        <div
          className={
            'si-card-day ' +
            (dayPct > 0 ? 'up' : dayPct < 0 ? 'down' : 'flat')
          }
        >
          {dayPct > 0 ? '▲' : dayPct < 0 ? '▼' : '—'}
          {Math.abs(dayPct).toFixed(2)}%
        </div>
      )}

      <div className="si-card-sep" />

      {/* Signal chips (top 2 in compact, all in expanded) */}
      <div className="si-card-chips">
        {(isExpanded ? chips : chips.slice(0, 2)).map((c, i) => (
          <span key={i} className={`si-card-chip ${c.tone}`}>
            {c.label}
          </span>
        ))}
        {!isExpanded && chips.length === 0 && (
          <span className="si-card-chip quiet">no signal</span>
        )}
      </div>

      {/* Expanded extras */}
      {isExpanded && (
        <div className="si-card-detail">
          <div className="si-detail-row">
            <span className="k">Position</span>
            <span className="v">
              {row.quantity.toLocaleString()} sh · {fmtUSD2(row.avg_cost)} avg
            </span>
          </div>
          <div className="si-detail-row">
            <span className="k">Mkt val</span>
            <span className="v">
              {fmtUSD(row.market_value)}
              <span
                className={
                  ' si-detail-pl ' +
                  (row.pnl_dollar < 0 ? 'down' : row.pnl_dollar > 0 ? 'up' : '')
                }
              >
                {row.pnl_dollar >= 0
                  ? '+' + fmtUSD(row.pnl_dollar)
                  : '−' + fmtUSD(Math.abs(row.pnl_dollar))}
              </span>
            </span>
          </div>
          <div className="si-detail-row">
            <span className="k">Net cost</span>
            <span className="v">{fmtUSD2(row.effective_cost)}</span>
          </div>
          {signals && (
            <>
              {signals.rsi14 != null && (
                <div className="si-detail-row">
                  <span className="k">RSI</span>
                  <span className="v">{signals.rsi14.toFixed(1)}</span>
                </div>
              )}
              {signals.ma50 != null &&
                signals.ma200 != null && (
                  <div className="si-detail-row">
                    <span className="k">MA</span>
                    <span className="v">
                      50d {fmtUSD2(signals.ma50)} · 200d {fmtUSD2(signals.ma200)}
                    </span>
                  </div>
                )}
              {(signals.chg_5d_pct != null || signals.chg_21d_pct != null) && (
                <div className="si-detail-row">
                  <span className="k">Δ</span>
                  <span className="v">
                    {signals.chg_5d_pct != null && (
                      <>5d {signals.chg_5d_pct.toFixed(1)}%</>
                    )}
                    {signals.chg_5d_pct != null && signals.chg_21d_pct != null && ' · '}
                    {signals.chg_21d_pct != null && (
                      <>21d {signals.chg_21d_pct.toFixed(1)}%</>
                    )}
                  </span>
                </div>
              )}
            </>
          )}
          {live.length > 0 && (
            <div className="si-detail-row">
              <span className="k">Options</span>
              <span className="v">
                {live.length} live
                {(() => {
                  const calls = live.filter((l) => l.open.option_type === 'call').length;
                  const puts = live.filter((l) => l.open.option_type === 'put').length;
                  return ` (${calls}C / ${puts}P)`;
                })()}
              </span>
            </div>
          )}
          <div className="si-detail-row">
            <span className="k">Sector</span>
            <span className="v">
              {row.sector}
              {bucket && (
                <span className={'si-detail-bucket st-' + bucket}>
                  {' · '}
                  {bucket}
                </span>
              )}
            </span>
          </div>
          {row.earnings_date && earningsDays != null && earningsDays >= 0 && (
            <div className="si-detail-row">
              <span className="k">Earnings</span>
              <span className="v">
                {row.earnings_date}{' '}
                <span className="si-detail-faint">
                  ({earningsDays === 0 ? 'today' : earningsDays + 'd'})
                </span>
              </span>
            </div>
          )}
          <div className="si-detail-row">
            <span className="k">% portfolio</span>
            <span className="v">{fmtCompact(row.pct_portfolio)}%</span>
          </div>
        </div>
      )}
    </div>
  );
}
