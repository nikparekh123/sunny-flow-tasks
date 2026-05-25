import { useEffect, useMemo, useRef, useState } from 'react';
import {
  daysUntil,
  fmtCompact,
  fmtUSD,
  fmtUSD2,
  type DailyClose,
  type LiveOption,
  type PositionComputed,
  type TickerSignals,
} from './types';
import type { StrategyBucket } from './usePositions';

/**
 * Stock Insights strip — vibrant per-ticker cards in a snap carousel.
 *
 * Each card is large (~600px) with a colored background driven by the
 * stock's TODAY day change — solid green when up, solid red when down,
 * dark when flat. Text is dark on color, light on dark.
 *
 * Sections (top → bottom):
 *   1. IDENTITY — ticker + sector, timeframe pills (1D/5D/1M/3M)
 *   2. NOW       — price, today's $ + %, sparkline over selected window
 *   3. YOUR POSITION — shares, basis, unrealized, realized options, % of book
 *   4. COMING UP — earnings (date or +add chip), beta vs SPY
 *   5. SIGNALS  — RSI / MA / move lines from ticker_signals
 *
 * Footer: prev / next carousel buttons + the existing "Updated 2m ago" line.
 *
 * Earnings: when the row has no earnings_date, the COMING UP block shows
 * a chip that flips into an inline <input type="date"> on click. Save
 * calls onSetEarnings, which the page wires to the existing mutation.
 *
 * Sparkline: reads from daily_closes (already cached by the parent hook).
 * The selected timeframe (1D/5D/1M/3M) controls both the headline % and
 * the sparkline window. Falls back to a flat baseline when no history.
 *
 * Beta + IV: small hardcoded subset of the 1y-baseline values from the
 * ScenarioStress / IvC tables. Top names only; sector default beyond.
 */

interface Props {
  rows: PositionComputed[];
  signalsByTicker: Map<string, TickerSignals>;
  liveByTicker: Map<string, LiveOption[]>;
  overlayByTicker: Map<string, StrategyBucket>;
  dailyCloses: DailyClose[];
  onSetEarnings: (ticker: string, dateIso: string | null) => void;
}

type Filter = 'all' | 'below-200d' | 'rsi-extreme' | 'big-move' | 'earnings';
const FILTERS: Array<{ id: Filter; label: string }> = [
  { id: 'all', label: 'All' },
  { id: 'below-200d', label: 'Below 200d' },
  { id: 'rsi-extreme', label: 'RSI extreme' },
  { id: 'big-move', label: 'Big move' },
  { id: 'earnings', label: 'Earnings' },
];

type Timeframe = '1D' | '5D' | '1M' | '3M';
const TIMEFRAMES: Timeframe[] = ['1D', '5D', '1M', '3M'];
const TIMEFRAME_DAYS: Record<Timeframe, number> = {
  '1D': 1,
  '5D': 5,
  '1M': 21,
  '3M': 63,
};

/** Day change % vs prev close. Drives the card background color. */
function dayChange(row: PositionComputed): number | null {
  if (row.current_price == null || row.prev_close == null || row.prev_close <= 0) return null;
  return ((row.current_price - row.prev_close) / row.prev_close) * 100;
}

/** Sentiment classification for the card background. ±0.5% is "flat". */
type Sentiment = 'up' | 'down' | 'flat';
function sentimentFor(dayPct: number | null): Sentiment {
  if (dayPct == null) return 'flat';
  if (dayPct >= 0.5) return 'up';
  if (dayPct <= -0.5) return 'down';
  return 'flat';
}

/** Small subset of beta values for the most-traded tickers. Same numbers
 *  we use in the Scenario & Stress calc; kept inline here to avoid a
 *  cross-module import from src/sunnyfi → src/positions. */
const BETA_HINTS: Record<string, number> = {
  SPY: 1.0, QQQ: 1.0, AAPL: 1.25, MSFT: 0.93, NVDA: 1.7, GOOGL: 1.05,
  AMZN: 1.16, META: 1.21, AVGO: 1.4, TSLA: 2.3, AMD: 1.85, TSM: 1.4,
  INTC: 1.0, NFLX: 1.1, CRM: 1.3, ADBE: 1.25, INTU: 1.15, WDAY: 1.3,
  SHOP: 2.5, COIN: 3.0, PLTR: 2.5, PYPL: 1.4, JPM: 1.1, BAC: 1.2,
  JNJ: 0.55, UNH: 0.65, XOM: 0.9, NKE: 1.0, WMT: 0.55, HD: 1.0, BBY: 1.2,
  HOOD: 2.5, MORN: 0.9, IT: 1.0, FIG: 1.5,
};
const betaFor = (ticker: string): number | null => BETA_HINTS[ticker.toUpperCase()] ?? null;

/** Plain-text signal lines, ranked by actionability. */
function signalLinesFor(s: TickerSignals | undefined): string[] {
  if (!s) return [];
  const out: Array<{ text: string; rank: number }> = [];

  if (s.rsi14 != null) {
    if (s.rsi14 >= 70) out.push({ text: `Overbought · RSI ${s.rsi14.toFixed(0)}`, rank: 100 });
    else if (s.rsi14 <= 30) out.push({ text: `Oversold · RSI ${s.rsi14.toFixed(0)}`, rank: 100 });
  }
  if (s.price != null && s.ma200 != null && s.ma200 > 0 && s.price < s.ma200) {
    const pct = ((s.price - s.ma200) / s.ma200) * 100;
    out.push({ text: `Below 200d MA · ${pct.toFixed(1)}%`, rank: 60 });
  }
  if (s.price != null && s.ma50 != null && s.ma50 > 0) {
    const pct = ((s.price - s.ma50) / s.ma50) * 100;
    if (pct >= 10) out.push({ text: `Stretched · +${pct.toFixed(1)}% vs 50d`, rank: 70 });
    else if (pct <= -7) out.push({ text: `Pullback · ${pct.toFixed(1)}% vs 50d`, rank: 70 });
  }
  if (s.chg_21d_pct != null && Math.abs(s.chg_21d_pct) >= 10) {
    const dir = s.chg_21d_pct >= 0 ? 'Up' : 'Down';
    out.push({ text: `${dir} ${Math.abs(s.chg_21d_pct).toFixed(1)}% past month`, rank: 80 });
  }
  if (s.chg_5d_pct != null && Math.abs(s.chg_5d_pct) >= 5) {
    const dir = s.chg_5d_pct >= 0 ? 'Up' : 'Down';
    out.push({ text: `${dir} ${Math.abs(s.chg_5d_pct).toFixed(1)}% past week`, rank: 90 });
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

/** Day-formatted timestamp for earnings UI. */
function fmtEarningsDate(iso: string): string {
  const d = new Date(iso + 'T00:00:00Z');
  return d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' });
}

// ──────────────────────────────────────────────────────────────────────
// Strip
// ──────────────────────────────────────────────────────────────────────
export function StockInsightsStrip({
  rows,
  signalsByTicker,
  liveByTicker,
  overlayByTicker,
  dailyCloses,
  onSetEarnings,
}: Props) {
  const [filter, setFilter] = useState<Filter>('all');
  const [sector, setSector] = useState<string>('__all__');

  // closes_by_ticker — sorted ascending by date once, used by each card's
  // sparkline. Single pass over the rows pays for every card render.
  const closesByTicker = useMemo(() => {
    const m = new Map<string, DailyClose[]>();
    for (const c of dailyCloses) {
      const arr = m.get(c.ticker) ?? [];
      arr.push(c);
      m.set(c.ticker, arr);
    }
    for (const arr of m.values()) arr.sort((a, b) => a.date.localeCompare(b.date));
    return m;
  }, [dailyCloses]);

  const cards = useMemo(
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

  const passesToggle = (c: typeof cards[number]): boolean => {
    const s = c.signals;
    switch (filter) {
      case 'all': return true;
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cards, filter, sector]);

  const countFor = (f: Filter): number => {
    return cards.filter((c) => {
      if (sector !== '__all__' && c.row.sector !== sector) return false;
      const s = c.signals;
      switch (f) {
        case 'all': return true;
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
    }).length;
  };

  // ── Carousel nav ──
  const scrollRef = useRef<HTMLDivElement>(null);
  const scrollBy = (dir: 1 | -1) => {
    const el = scrollRef.current;
    if (!el) return;
    // One card + gap ≈ card width + 16px. Use first child's width as ground truth.
    const card = el.querySelector<HTMLElement>('.si-card');
    const step = card ? card.offsetWidth + 16 : 600;
    el.scrollBy({ left: dir * step, behavior: 'smooth' });
  };
  // Keyboard arrow nav when the strip has focus
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const onKey = (e: KeyboardEvent) => {
      if (document.activeElement !== el) return;
      if (e.key === 'ArrowRight') { e.preventDefault(); scrollBy(1); }
      if (e.key === 'ArrowLeft')  { e.preventDefault(); scrollBy(-1); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

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
                {f.id !== 'all' && <span className="si-toggle-ct"> {countFor(f.id)}</span>}
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
              <option key={s} value={s}>{s}</option>
            ))}
          </select>
        </div>
      </div>

      <div className="si-scroll" ref={scrollRef} tabIndex={0}>
        <div className="si-row">
          {visible.length === 0 ? (
            <div className="si-empty">No tickers match the active filter.</div>
          ) : (
            visible.map((c, i) => (
              <Card
                key={c.row.ticker}
                card={c}
                index={i}
                total={visible.length}
                closes={closesByTicker.get(c.row.ticker) ?? []}
                onPrev={() => scrollBy(-1)}
                onNext={() => scrollBy(1)}
                onSetEarnings={onSetEarnings}
              />
            ))
          )}
        </div>
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Card — five sections, vibrant background, dark text on color
// ──────────────────────────────────────────────────────────────────────
interface CardData {
  row: PositionComputed;
  signals?: TickerSignals;
  live: LiveOption[];
  dayPct: number | null;
  earningsDays: number | null;
  bucket?: StrategyBucket;
  signalLines: string[];
  actionability: number;
}

function Card({
  card, index, total, closes, onPrev, onNext, onSetEarnings,
}: {
  card: CardData;
  index: number;
  total: number;
  closes: DailyClose[];
  onPrev: () => void;
  onNext: () => void;
  onSetEarnings: (ticker: string, dateIso: string | null) => void;
}) {
  const { row, signals, live, dayPct, earningsDays, signalLines } = card;
  const sentiment = sentimentFor(dayPct);
  const [tf, setTf] = useState<Timeframe>('1D');
  const [editingEarnings, setEditingEarnings] = useState(false);

  // Headline % depends on selected timeframe. 1D is dayPct; longer windows
  // pull from ticker_signals (chg_5d_pct, chg_21d_pct) or compute from the
  // close history for 3M (since signals only goes back 21d).
  const headlinePct: number | null = useMemo(() => {
    if (tf === '1D') return dayPct;
    if (tf === '5D') return signals?.chg_5d_pct ?? pctFromCloses(closes, 5, row.current_price);
    if (tf === '1M') return signals?.chg_21d_pct ?? pctFromCloses(closes, 21, row.current_price);
    if (tf === '3M') return pctFromCloses(closes, 63, row.current_price);
    return null;
  }, [tf, dayPct, signals, closes, row.current_price]);

  const headlineDollar = useMemo(() => {
    if (headlinePct == null || row.current_price == null) return null;
    // Anchor price for the delta: prev_close for 1D, else closes[lookback] approx.
    const anchor =
      tf === '1D'
        ? row.prev_close
        : anchorPrice(closes, TIMEFRAME_DAYS[tf]) ?? null;
    if (anchor == null || anchor <= 0) return null;
    return row.current_price - anchor;
  }, [headlinePct, tf, closes, row.current_price, row.prev_close]);

  // Realized options P&L on this position — for the position story.
  const realizedOptions = row.realized_pl ?? 0;
  const overallPL = row.overall_pl;
  const overallPLpct = row.cost_basis > 0 ? (overallPL / row.cost_basis) * 100 : 0;
  const stockUnrealized = row.pnl_dollar ?? 0;

  const beta = betaFor(row.ticker);
  const liveCalls = live.filter((l) => l.open.option_type === 'call').length;
  const livePuts = live.filter((l) => l.open.option_type === 'put').length;

  return (
    <article className={`si-card tone-${sentiment}`}>
      {/* ── IDENTITY + timeframe pills ── */}
      <header className="si-card-hd">
        <div className="si-card-id">
          <div className="si-card-tk">{row.ticker}</div>
          <div className="si-card-sec">{row.sector}</div>
        </div>
        <div className="si-tf">
          {TIMEFRAMES.map((t) => (
            <button
              key={t}
              type="button"
              className={`si-tf-pill${tf === t ? ' on' : ''}`}
              onClick={() => setTf(t)}
            >
              {t}
            </button>
          ))}
        </div>
      </header>

      {/* ── NOW: price + change + sparkline ── */}
      <section className="si-now">
        <div className="si-price">
          {row.current_price != null ? fmtUSD2(row.current_price) : '—'}
        </div>
        {headlinePct != null && (
          <div className={`si-change tone-${headlinePct >= 0 ? 'pos' : 'neg'}`}>
            {headlineDollar != null && (
              <span className="si-change-dollar">
                {headlineDollar >= 0 ? '+' : '−'}
                {fmtUSD2(Math.abs(headlineDollar))}
              </span>
            )}
            <span className="si-change-pct">
              {headlinePct >= 0 ? '+' : ''}{headlinePct.toFixed(2)}%
            </span>
            <span className="si-change-window">over {tf}</span>
          </div>
        )}
        <Sparkline closes={closes} window={TIMEFRAME_DAYS[tf]} sentiment={sentiment} />
      </section>

      {/* ── YOUR POSITION ── */}
      <section className="si-block">
        <div className="si-block-hd">Your position</div>
        <div className="si-block-row">
          <span className="si-k">{row.quantity.toLocaleString()} sh</span>
          <span className="si-sep">·</span>
          <span className="si-k">cost basis {fmtUSD2(row.avg_cost)}</span>
        </div>
        <div className="si-block-row">
          <span className={`si-v ${stockUnrealized >= 0 ? 'pos' : 'neg'}`}>
            {stockUnrealized >= 0 ? '+' : '−'}{fmtUSD(Math.abs(stockUnrealized))}
            <span className="si-v-pct">
              {' '}({overallPLpct >= 0 ? '+' : ''}{overallPLpct.toFixed(1)}%)
            </span>
          </span>
          <span className="si-k"> unrealized</span>
        </div>
        {realizedOptions !== 0 && (
          <div className="si-block-row">
            <span className={`si-v ${realizedOptions >= 0 ? 'pos' : 'neg'}`}>
              {realizedOptions >= 0 ? '+' : '−'}{fmtUSD(Math.abs(realizedOptions))}
            </span>
            <span className="si-k"> realized from options</span>
          </div>
        )}
        <div className="si-block-row muted">
          <span>{fmtCompact(row.pct_portfolio)}% of book</span>
          {(liveCalls > 0 || livePuts > 0) && (
            <>
              <span className="si-sep">·</span>
              <span>{liveCalls} live calls · {livePuts} live puts</span>
            </>
          )}
        </div>
      </section>

      {/* ── COMING UP ── */}
      <section className="si-block">
        <div className="si-block-hd">Coming up</div>
        {row.earnings_date && !editingEarnings ? (
          <div className="si-block-row">
            {earningsDays != null && earningsDays >= 0 ? (
              <span className={'si-earn ' + (earningsDays <= 7 ? 'urgent' : 'soon')}>
                📅 Earnings in {earningsDays} day{earningsDays === 1 ? '' : 's'}
                <span className="si-k"> · {fmtEarningsDate(row.earnings_date)}</span>
              </span>
            ) : (
              <span className="si-earn">
                📅 Last earnings · {fmtEarningsDate(row.earnings_date)}
              </span>
            )}
            <button
              type="button"
              className="si-earn-edit"
              onClick={() => setEditingEarnings(true)}
              aria-label="Edit earnings date"
            >
              edit
            </button>
          </div>
        ) : editingEarnings ? (
          <EarningsEditor
            initial={row.earnings_date ?? ''}
            onSave={(d) => {
              onSetEarnings(row.ticker, d || null);
              setEditingEarnings(false);
            }}
            onCancel={() => setEditingEarnings(false)}
          />
        ) : (
          <button
            type="button"
            className="si-earn-add"
            onClick={() => setEditingEarnings(true)}
          >
            📅 Add earnings date
          </button>
        )}
        {beta != null && (
          <div className="si-block-row muted">
            <span>β {beta.toFixed(2)} vs SPY</span>
            {beta >= 1.5 && <span className="si-sep">·</span>}
            {beta >= 1.5 && <span>high-beta · stress-sensitive</span>}
            {beta <= 0.6 && <span className="si-sep">·</span>}
            {beta <= 0.6 && <span>low-beta · defensive</span>}
          </div>
        )}
      </section>

      {/* ── SIGNALS ── */}
      {signalLines.length > 0 && (
        <section className="si-block">
          <div className="si-block-hd">Signals</div>
          <ul className="si-signals">
            {signalLines.map((line, i) => (
              <li key={i}>{line}</li>
            ))}
          </ul>
        </section>
      )}

      {/* ── FOOTER ── */}
      <footer className="si-card-ft">
        <span className="si-updated">Updated {fmtRelative(row.last_price_update)}</span>
        <span className="si-nav">
          <button type="button" className="si-nav-btn" onClick={onPrev} aria-label="Previous">◀</button>
          <span className="si-nav-pos">{index + 1} of {total}</span>
          <button type="button" className="si-nav-btn" onClick={onNext} aria-label="Next">▶</button>
        </span>
      </footer>
    </article>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Sparkline — mini polyline drawn from daily_closes
// ──────────────────────────────────────────────────────────────────────
function Sparkline({
  closes, window: windowDays, sentiment,
}: {
  closes: DailyClose[];
  window: number;
  sentiment: Sentiment;
}) {
  const slice = useMemo(() => {
    if (closes.length === 0) return [];
    // For windowDays=1, just last 2 points (yesterday + a stub for today).
    const n = Math.max(2, windowDays + 1);
    return closes.slice(-n);
  }, [closes, windowDays]);

  if (slice.length < 2) {
    return <div className="si-spark-empty">— no chart data —</div>;
  }
  const W = 560, H = 60, P = 4;
  const values = slice.map((c) => c.close_price);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = Math.max(0.0001, max - min);
  const xFor = (i: number) => P + (i / (values.length - 1)) * (W - 2 * P);
  const yFor = (v: number) => H - P - ((v - min) / range) * (H - 2 * P);

  const points = values.map((v, i) => `${xFor(i).toFixed(2)},${yFor(v).toFixed(2)}`).join(' ');
  const stroke = sentiment === 'flat' ? '#a8c4c0' : '#0a2828';

  return (
    <svg className="si-spark" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
      <polyline points={points} fill="none" stroke={stroke} strokeWidth="1.8" strokeLinejoin="round" strokeLinecap="round" />
      {/* Endpoint dot */}
      <circle
        cx={xFor(values.length - 1)}
        cy={yFor(values[values.length - 1])}
        r="2.5"
        fill={stroke}
      />
    </svg>
  );
}

/** % change from N trading-days ago to today's price. Falls back to null
 *  if the close history doesn't reach back that far. */
function pctFromCloses(closes: DailyClose[], days: number, todayPrice: number | null): number | null {
  if (closes.length === 0 || todayPrice == null) return null;
  const idx = Math.max(0, closes.length - 1 - days);
  const anchor = closes[idx]?.close_price;
  if (!anchor || anchor <= 0) return null;
  return ((todayPrice - anchor) / anchor) * 100;
}
function anchorPrice(closes: DailyClose[], days: number): number | null {
  if (closes.length === 0) return null;
  const idx = Math.max(0, closes.length - 1 - days);
  return closes[idx]?.close_price ?? null;
}

// ──────────────────────────────────────────────────────────────────────
// Inline earnings-date editor
// ──────────────────────────────────────────────────────────────────────
function EarningsEditor({
  initial, onSave, onCancel,
}: {
  initial: string;
  onSave: (iso: string) => void;
  onCancel: () => void;
}) {
  const [v, setV] = useState(initial);
  return (
    <div className="si-earn-edit-row">
      <input
        type="date"
        className="si-earn-input"
        value={v}
        onChange={(e) => setV(e.target.value)}
        autoFocus
      />
      <button type="button" className="si-earn-btn save" onClick={() => onSave(v)}>save</button>
      <button type="button" className="si-earn-btn cancel" onClick={onCancel}>cancel</button>
    </div>
  );
}
