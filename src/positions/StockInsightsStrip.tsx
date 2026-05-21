import { useMemo, useState } from 'react';
import {
  daysUntil,
  fmtCompact,
  fmtPct,
  fmtUSD,
  fmtUSD2,
  type LiveOption,
  type PositionComputed,
  type TickerSignals,
} from './types';
import type { StrategyBucket } from './usePositions';

/**
 * Stock Insights strip — horizontally-scrolling row of per-ticker cards.
 *
 * Cards are calmer than the previous chip-heavy version: plain text
 * lines, a letter avatar, sector + day move + position P&L. Click any
 * card to expand it in place; siblings slide aside.
 *
 * Filters:
 *   • Single-select segmented toggle (mirrors the Allocation/Positions
 *     toggles elsewhere on the page for visual consistency)
 *   • Sector dropdown (independent, ANDs with the toggle filter)
 */

interface Props {
  rows: PositionComputed[];
  signalsByTicker: Map<string, TickerSignals>;
  liveByTicker: Map<string, LiveOption[]>;
  overlayByTicker: Map<string, StrategyBucket>;
}

type Filter = 'all' | 'below-200d' | 'rsi-extreme' | 'big-move' | 'earnings';
const FILTERS: Array<{ id: Filter; label: string }> = [
  { id: 'all', label: 'All' },
  { id: 'below-200d', label: 'Below 200d' },
  { id: 'rsi-extreme', label: 'RSI extreme' },
  { id: 'big-move', label: 'Big move' },
  { id: 'earnings', label: 'Earnings' },
];

interface CardModel {
  row: PositionComputed;
  signals?: TickerSignals;
  live: LiveOption[];
  dayPct: number | null;
  earningsDays: number | null;
  bucket?: StrategyBucket;
  signalLines: string[]; // plain-text signal lines, ranked
  actionability: number; // sort score
}

function dayChange(row: PositionComputed): number | null {
  if (row.current_price == null || row.prev_close == null || row.prev_close <= 0) return null;
  return ((row.current_price - row.prev_close) / row.prev_close) * 100;
}

/** Deterministic colour from a ticker (used for the letter avatar). */
function avatarColor(ticker: string): { bg: string; fg: string } {
  // Stable hash → palette index.
  let h = 0;
  for (let i = 0; i < ticker.length; i++) h = (h * 31 + ticker.charCodeAt(i)) | 0;
  const palette: Array<{ bg: string; fg: string }> = [
    { bg: '#d2e632', fg: '#0a2828' }, // neon
    { bg: '#a8d4a0', fg: '#0a2828' }, // positive green
    { bg: '#6dd1c5', fg: '#0a2828' }, // cool teal
    { bg: '#a8c4c0', fg: '#0a2828' }, // pale teal
    { bg: '#e0c060', fg: '#0a2828' }, // warning amber
    { bg: '#326e64', fg: '#faf5f0' }, // border bright
    { bg: '#8ab4d4', fg: '#0a2828' }, // soft blue
  ];
  return palette[Math.abs(h) % palette.length];
}

/** Build plain-text signal lines, ranked by actionability. */
function signalLinesFor(s: TickerSignals | undefined): string[] {
  if (!s) return [];
  const out: Array<{ text: string; rank: number }> = [];

  // RSI extreme
  if (s.rsi14 != null) {
    if (s.rsi14 >= 70) out.push({ text: `Overbought · RSI ${s.rsi14.toFixed(0)}`, rank: 100 });
    else if (s.rsi14 <= 30) out.push({ text: `Oversold · RSI ${s.rsi14.toFixed(0)}`, rank: 100 });
  }

  // Below 200d
  if (s.price != null && s.ma200 != null && s.ma200 > 0 && s.price < s.ma200) {
    const pct = ((s.price - s.ma200) / s.ma200) * 100;
    out.push({ text: `Below 200d MA · ${pct.toFixed(1)}%`, rank: 60 });
  }

  // Stretched / pullback vs 50d
  if (s.price != null && s.ma50 != null && s.ma50 > 0) {
    const pct = ((s.price - s.ma50) / s.ma50) * 100;
    if (pct >= 10) out.push({ text: `Stretched · +${pct.toFixed(1)}% vs 50d`, rank: 70 });
    else if (pct <= -7) out.push({ text: `Pullback · ${pct.toFixed(1)}% vs 50d`, rank: 70 });
  }

  // 21d move (monthly)
  if (s.chg_21d_pct != null && Math.abs(s.chg_21d_pct) >= 10) {
    const dir = s.chg_21d_pct >= 0 ? 'Up' : 'Down';
    out.push({
      text: `${dir} ${Math.abs(s.chg_21d_pct).toFixed(1)}% past month`,
      rank: 80,
    });
  }

  // 5d move (weekly)
  if (s.chg_5d_pct != null && Math.abs(s.chg_5d_pct) >= 5) {
    const dir = s.chg_5d_pct >= 0 ? 'Up' : 'Down';
    out.push({
      text: `${dir} ${Math.abs(s.chg_5d_pct).toFixed(1)}% past week`,
      rank: 90,
    });
  }

  out.sort((a, b) => b.rank - a.rank);
  return out.map((x) => x.text);
}

/** Coarse "X ago" — uses ISO timestamp. */
function fmtRelative(iso: string | null | undefined): string {
  if (!iso) return '—';
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return '—';
  const diffMs = Date.now() - t;
  const s = Math.max(0, Math.floor(diffMs / 1000));
  if (s < 60) return 'just now';
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}

export function StockInsightsStrip({
  rows,
  signalsByTicker,
  liveByTicker,
  overlayByTicker,
}: Props) {
  const [filter, setFilter] = useState<Filter>('all');
  const [sector, setSector] = useState<string>('__all__');
  const [expanded, setExpanded] = useState<string | null>(null);

  const cards = useMemo<CardModel[]>(
    () =>
      rows.map((r) => {
        const s = signalsByTicker.get(r.ticker);
        const live = liveByTicker.get(r.ticker) ?? [];
        const lines = signalLinesFor(s);
        return {
          row: r,
          signals: s,
          live,
          dayPct: dayChange(r),
          earningsDays: r.earnings_date ? daysUntil(r.earnings_date) : null,
          bucket: overlayByTicker.get(r.ticker),
          signalLines: lines,
          actionability:
            lines.length * 100 +
            Math.abs(s?.chg_21d_pct ?? 0) +
            Math.abs(s?.chg_5d_pct ?? 0) / 10,
        };
      }),
    [rows, signalsByTicker, liveByTicker, overlayByTicker],
  );

  const sectors = useMemo(() => {
    const set = new Set<string>();
    for (const c of cards) set.add(c.row.sector);
    return Array.from(set).sort();
  }, [cards]);

  const passesToggle = (c: CardModel): boolean => {
    const s = c.signals;
    switch (filter) {
      case 'all':
        return true;
      case 'below-200d':
        return !!s && s.price != null && s.ma200 != null && s.ma200 > 0 && s.price < s.ma200;
      case 'rsi-extreme':
        return !!s && s.rsi14 != null && (s.rsi14 >= 70 || s.rsi14 <= 30);
      case 'big-move':
        return (
          (!!s && s.chg_5d_pct != null && Math.abs(s.chg_5d_pct) >= 5) ||
          (!!s && s.chg_21d_pct != null && Math.abs(s.chg_21d_pct) >= 10) ||
          (c.dayPct != null && Math.abs(c.dayPct) >= 2)
        );
      case 'earnings':
        return c.earningsDays != null && c.earningsDays >= 0 && c.earningsDays <= 30;
    }
  };

  const visible = useMemo(() => {
    const out = cards.filter((c) => {
      if (!passesToggle(c)) return false;
      if (sector !== '__all__' && c.row.sector !== sector) return false;
      return true;
    });
    out.sort((a, b) => b.actionability - a.actionability);
    return out;
  }, [cards, filter, sector]);

  // Per-filter counts for the toggle buttons.
  const countFor = (f: Filter): number => {
    const tmp = cards.filter((c) => {
      if (sector !== '__all__' && c.row.sector !== sector) return false;
      const saved = filter;
      // Inline duplicate of passesToggle to avoid hook deps.
      const s = c.signals;
      switch (f) {
        case 'all':
          return true;
        case 'below-200d':
          return !!s && s.price != null && s.ma200 != null && s.ma200 > 0 && s.price < s.ma200;
        case 'rsi-extreme':
          return !!s && s.rsi14 != null && (s.rsi14 >= 70 || s.rsi14 <= 30);
        case 'big-move':
          return (
            (!!s && s.chg_5d_pct != null && Math.abs(s.chg_5d_pct) >= 5) ||
            (!!s && s.chg_21d_pct != null && Math.abs(s.chg_21d_pct) >= 10) ||
            (c.dayPct != null && Math.abs(c.dayPct) >= 2)
          );
        case 'earnings':
          return c.earningsDays != null && c.earningsDays >= 0 && c.earningsDays <= 30;
      }
      void saved;
    });
    return tmp.length;
  };

  return (
    <div className="si-wrap">
      <div className="si-hd">
        <div className="si-title">Stock insights</div>
        <div className="si-controls">
          <div className="np-toggle si-toggle">
            {FILTERS.map((f) => (
              <button
                key={f.id}
                className={filter === f.id ? 'on' : ''}
                onClick={() => setFilter(f.id)}
              >
                {f.label}
                {f.id !== 'all' && (
                  <span className="si-toggle-ct"> {countFor(f.id)}</span>
                )}
              </button>
            ))}
          </div>
          <select
            className="si-sector"
            value={sector}
            onChange={(e) => setSector(e.target.value)}
          >
            <option value="__all__">All sectors</option>
            {sectors.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="si-scroll">
        <div className="si-row">
          {visible.length === 0 ? (
            <div className="si-empty">No tickers match the active filter.</div>
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
  const { row, signals, live, dayPct, earningsDays, bucket, signalLines } = card;
  const avatar = avatarColor(row.ticker);
  const overallPL = row.overall_pl;
  const overallPLpct =
    row.cost_basis > 0 ? (overallPL / row.cost_basis) * 100 : 0;

  return (
    <div
      className={'si-card' + (isExpanded ? ' expanded' : '')}
      onClick={onToggle}
      role="button"
      tabIndex={0}
    >
      {/* Top — avatar + ticker + sector */}
      <div className="si-card-top">
        <div
          className="si-card-avatar"
          style={{ background: avatar.bg, color: avatar.fg }}
        >
          {row.ticker[0]}
        </div>
        <div className="si-card-ident">
          <div className="si-card-tk">{row.ticker}</div>
          <div className="si-card-sec">{row.sector}</div>
        </div>
      </div>

      {/* Price + day change */}
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
          {dayPct > 0 ? '+' : ''}
          {dayPct.toFixed(2)}% today
        </div>
      )}

      {/* Overall position P&L */}
      <div className="si-card-pl-row">
        <span
          className={
            'si-card-pl ' +
            (overallPL > 0 ? 'up' : overallPL < 0 ? 'down' : 'flat')
          }
        >
          {overallPL >= 0
            ? '+' + fmtUSD(overallPL)
            : '−' + fmtUSD(Math.abs(overallPL))}
          {row.cost_basis > 0 && (
            <span className="si-card-pl-pct">
              {' '}
              {overallPLpct >= 0 ? '+' : ''}
              {overallPLpct.toFixed(2)}%
            </span>
          )}
        </span>
      </div>
      <div className="si-card-pos">
        {row.quantity.toLocaleString()} sh · {fmtUSD2(row.avg_cost)} avg
      </div>

      {/* Signal lines (plain text) */}
      {signalLines.length > 0 && (
        <div className="si-card-signals">
          {(isExpanded ? signalLines : signalLines.slice(0, 2)).map(
            (line, i) => (
              <div key={i} className="si-card-signal">
                {line}
              </div>
            ),
          )}
        </div>
      )}

      {/* Earnings line */}
      {earningsDays != null && earningsDays >= 0 && earningsDays <= 30 && (
        <div
          className={
            'si-card-earn ' + (earningsDays <= 7 ? 'urgent' : 'soon')
          }
        >
          {earningsDays === 0
            ? 'Earnings today'
            : earningsDays === 1
              ? 'Earnings tomorrow'
              : `Earnings in ${earningsDays} days`}
        </div>
      )}

      {/* Footer — updated */}
      <div className="si-card-footer">
        Updated {fmtRelative(row.last_price_update)}
      </div>

      {/* Expanded detail */}
      {isExpanded && (
        <div className="si-card-detail">
          <Detail k="Mkt value" v={fmtUSD(row.market_value)} />
          <Detail k="Net cost" v={fmtUSD2(row.effective_cost)} />
          <Detail k="% portfolio" v={`${fmtCompact(row.pct_portfolio)}%`} />
          {signals?.rsi14 != null && (
            <Detail k="RSI(14)" v={signals.rsi14.toFixed(1)} />
          )}
          {signals?.ma50 != null && (
            <Detail k="MA 50d" v={fmtUSD2(signals.ma50)} />
          )}
          {signals?.ma200 != null && (
            <Detail k="MA 200d" v={fmtUSD2(signals.ma200)} />
          )}
          {signals?.chg_5d_pct != null && (
            <Detail k="5d move" v={fmtPct(signals.chg_5d_pct)} />
          )}
          {signals?.chg_21d_pct != null && (
            <Detail k="21d move" v={fmtPct(signals.chg_21d_pct)} />
          )}
          {live.length > 0 && (
            <Detail
              k="Live options"
              v={`${live.length} (${live.filter((l) => l.open.option_type === 'call').length}C / ${live.filter((l) => l.open.option_type === 'put').length}P)`}
            />
          )}
          {bucket && <Detail k="Strategy" v={bucket} />}
        </div>
      )}
    </div>
  );
}

function Detail({ k, v }: { k: string; v: string }) {
  return (
    <div className="si-detail-row">
      <span className="k">{k}</span>
      <span className="v">{v}</span>
    </div>
  );
}
