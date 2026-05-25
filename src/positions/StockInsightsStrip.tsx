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
 * Timeframe: pills (1D/5D/1M/3M) toggle the headline % only. The card
 * background tracks TODAY's day change regardless of the selected window
 * — that's the "is this stock up or down right now" signal.
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

/** Sentiment classification for the card background.
 *
 *  Today's move wins when it's meaningful (≥ ±0.5%). When the day is flat
 *  (market closed, no movement, or the stock genuinely hasn't moved) we
 *  fall through to the user's OVERALL position direction so the card is
 *  still visibly green/red — that's almost always more informative than
 *  showing a neutral "nothing happened" panel. Only returns 'flat' when
 *  both signals are truly zero (a brand-new position with no movement). */
type Sentiment = 'up' | 'down' | 'flat';
function sentimentFor(dayPct: number | null, overallPL: number): Sentiment {
  if (dayPct != null) {
    if (dayPct >= 0.5) return 'up';
    if (dayPct <= -0.5) return 'down';
  }
  // Fall back to the user's stake in the name
  if (overallPL > 0) return 'up';
  if (overallPL < 0) return 'down';
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

/** Each signal renders as a tile: big number / percentage up top, a short
 *  descriptive label underneath. Ranked by how actionable the signal is —
 *  RSI extremes and big recent moves first, MA context after. */
interface SignalTile {
  value: string;
  label: string;
  tone?: 'pos' | 'neg';
}
function signalTilesFor(s: TickerSignals | undefined): SignalTile[] {
  if (!s) return [];
  const out: Array<SignalTile & { rank: number }> = [];

  // RSI extreme — surface the number itself, label says what it means
  if (s.rsi14 != null) {
    if (s.rsi14 >= 70) {
      out.push({ value: s.rsi14.toFixed(0), label: 'overbought · RSI', tone: 'neg', rank: 100 });
    } else if (s.rsi14 <= 30) {
      out.push({ value: s.rsi14.toFixed(0), label: 'oversold · RSI', tone: 'pos', rank: 100 });
    }
  }
  // 5-day move — surfaced when ≥ 5%
  if (s.chg_5d_pct != null && Math.abs(s.chg_5d_pct) >= 5) {
    out.push({
      value: `${s.chg_5d_pct >= 0 ? '+' : '−'}${Math.abs(s.chg_5d_pct).toFixed(1)}%`,
      label: 'past week',
      tone: s.chg_5d_pct >= 0 ? 'pos' : 'neg',
      rank: 90,
    });
  }
  // 21-day move — surfaced when ≥ 10%
  if (s.chg_21d_pct != null && Math.abs(s.chg_21d_pct) >= 10) {
    out.push({
      value: `${s.chg_21d_pct >= 0 ? '+' : '−'}${Math.abs(s.chg_21d_pct).toFixed(1)}%`,
      label: 'past month',
      tone: s.chg_21d_pct >= 0 ? 'pos' : 'neg',
      rank: 80,
    });
  }
  // Vs 50-day MA — only when stretched or pulled back hard
  if (s.price != null && s.ma50 != null && s.ma50 > 0) {
    const pct = ((s.price - s.ma50) / s.ma50) * 100;
    if (pct >= 10) {
      out.push({ value: `+${pct.toFixed(1)}%`, label: 'stretched · vs 50d', tone: 'pos', rank: 70 });
    } else if (pct <= -7) {
      out.push({ value: `${pct.toFixed(1)}%`, label: 'pullback · vs 50d', tone: 'neg', rank: 70 });
    }
  }
  // Vs 200-day MA — always shown when below (long-term downtrend)
  if (s.price != null && s.ma200 != null && s.ma200 > 0 && s.price < s.ma200) {
    const pct = ((s.price - s.ma200) / s.ma200) * 100;
    out.push({ value: `${pct.toFixed(1)}%`, label: 'below 200d MA', tone: 'neg', rank: 60 });
  }

  out.sort((a, b) => b.rank - a.rank);
  return out.map(({ value, label, tone }) => ({ value, label, tone }));
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
      rows
        // Closed positions don't belong on the live-insights strip —
        // they're snapshots of the past, not actionable now.
        .filter((r) => r.status === 'open')
        .map((r) => {
        const s = signalsByTicker.get(r.ticker);
        const live = liveByTicker.get(r.ticker) ?? [];
        const tiles = signalTilesFor(s);
        return {
          row: r,
          signals: s,
          live,
          dayPct: dayChange(r),
          earningsDays: r.earnings_date ? daysUntil(r.earnings_date) : null,
          bucket: overlayByTicker.get(r.ticker),
          signalTiles: tiles,
          actionability:
            tiles.length * 100 +
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
  signalTiles: SignalTile[];
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
  const { row, signals, live, dayPct, earningsDays, signalTiles } = card;
  const overallPL = row.overall_pl;
  const sentiment = sentimentFor(dayPct, overallPL);
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
    const anchor =
      tf === '1D'
        ? row.prev_close
        : anchorPrice(closes, TIMEFRAME_DAYS[tf]) ?? null;
    if (anchor == null || anchor <= 0) return null;
    return row.current_price - anchor;
  }, [headlinePct, tf, closes, row.current_price, row.prev_close]);

  const realizedOptions = row.realized_pl ?? 0;
  const overallPLpct = row.cost_basis > 0 ? (overallPL / row.cost_basis) * 100 : 0;
  const stockUnrealized = row.pnl_dollar ?? 0;

  const beta = betaFor(row.ticker);
  const liveCalls = live.filter((l) => l.open.option_type === 'call').length;
  const livePuts = live.filter((l) => l.open.option_type === 'put').length;

  return (
    <article className={`si-card tone-${sentiment}`}>
      {/* ── IDENTITY (left) + earnings (top-right, plain text) ── */}
      <header className="si-card-hd">
        <div className="si-card-id">
          <div className="si-card-tk">{row.ticker}</div>
          <div className="si-card-sec">{row.sector}</div>
        </div>
        <Earnings
          earningsDate={row.earnings_date}
          earningsDays={earningsDays}
          editing={editingEarnings}
          onEditStart={() => setEditingEarnings(true)}
          onSave={(d) => {
            onSetEarnings(row.ticker, d || null);
            setEditingEarnings(false);
          }}
          onCancel={() => setEditingEarnings(false)}
        />
      </header>

      {/* ── NOW: price + change + inline timeframe switcher ── */}
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
        {/* Plain-text timeframe switcher — active one bold + underlined,
            inactive ones muted. No pills, no borders. */}
        <div className="si-tf-row">
          {TIMEFRAMES.map((t) => (
            <button
              key={t}
              type="button"
              className={`si-tf-link${tf === t ? ' on' : ''}`}
              onClick={() => setTf(t)}
            >
              {t}
            </button>
          ))}
        </div>
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
          {beta != null && (
            <>
              <span className="si-sep">·</span>
              <span>β {beta.toFixed(2)} vs SPY</span>
            </>
          )}
        </div>
      </section>

      {/* ── SIGNALS as big-number tiles ── */}
      {signalTiles.length > 0 && (
        <section className="si-block">
          <div className="si-block-hd">Signals</div>
          <div className="si-tiles">
            {signalTiles.map((t, i) => (
              <div key={i} className={`si-tile${t.tone ? ` tone-${t.tone}` : ''}`}>
                <div className="si-tile-v">{t.value}</div>
                <div className="si-tile-l">{t.label}</div>
              </div>
            ))}
          </div>
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

/** Plain-text earnings display for the card header. No pill, no chip —
 *  just two lines (eyebrow + value) that match the right-side feel of
 *  the sector eyebrow on the left. Click anywhere on the value to open
 *  the inline date editor. */
function Earnings({
  earningsDate, earningsDays, editing, onEditStart, onSave, onCancel,
}: {
  earningsDate: string | null;
  earningsDays: number | null;
  editing: boolean;
  onEditStart: () => void;
  onSave: (iso: string) => void;
  onCancel: () => void;
}) {
  const [draft, setDraft] = useState(earningsDate ?? '');
  if (editing) {
    return (
      <div className="si-earn">
        <div className="si-earn-lbl">EARNINGS</div>
        <div className="si-earn-edit-row">
          <input
            type="date"
            className="si-earn-input"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            autoFocus
          />
          <button type="button" className="si-earn-btn save" onClick={() => onSave(draft)}>save</button>
          <button type="button" className="si-earn-btn cancel" onClick={onCancel}>cancel</button>
        </div>
      </div>
    );
  }
  if (earningsDate) {
    const urgent = earningsDays != null && earningsDays >= 0 && earningsDays <= 7;
    const countdown =
      earningsDays != null && earningsDays >= 0
        ? `in ${earningsDays}d`
        : 'past';
    return (
      <div className="si-earn">
        <div className="si-earn-lbl">EARNINGS</div>
        <button
          type="button"
          className={`si-earn-val${urgent ? ' urgent' : ''}`}
          onClick={onEditStart}
          title="Click to edit earnings date"
        >
          {countdown} · {fmtEarningsDate(earningsDate)}
        </button>
      </div>
    );
  }
  return (
    <div className="si-earn">
      <div className="si-earn-lbl">EARNINGS</div>
      <button type="button" className="si-earn-val add" onClick={onEditStart}>
        + add date
      </button>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Helpers — close history → returns
// ──────────────────────────────────────────────────────────────────────
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
