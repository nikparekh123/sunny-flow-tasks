import { Fragment, useMemo, useState } from 'react';
import { fmtCompact, type OptionTrade, type PositionComputed } from './types';

/**
 * Expiry timeline — tickers fixed on the left, time on the right.
 *
 * For each ticker we draw two horizontal lanes:
 *   • Put lane  — red rule, markers for every put open in range
 *   • Call lane — green rule, markers for every call open in range
 *
 * Markers are placed by expiry date along a continuous calendar axis
 * (today line in neon). Short = filled, Long = outlined; fully-closed
 * opens render muted. Click a marker or a ticker → insight modal.
 *
 * This is event-driven by design: each option is an event on a ticker's
 * lane, not the other way around.
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const RANGE_OPTIONS = [30, 60, 90, 180] as const;
type Range = typeof RANGE_OPTIONS[number];
const LS_RANGE = 'np:calRange';

function startOfDayUTC(d: Date): Date {
  const x = new Date(d);
  x.setUTCHours(0, 0, 0, 0);
  return x;
}
function mondayOf(d: Date): Date {
  const x = startOfDayUTC(d);
  const day = (x.getUTCDay() + 6) % 7;
  x.setUTCDate(x.getUTCDate() - day);
  return x;
}
function addDays(d: Date, n: number): Date {
  const x = new Date(d);
  x.setUTCDate(x.getUTCDate() + n);
  return x;
}
function isoDay(d: Date): string {
  return d.toISOString().slice(0, 10);
}
function readRangeLS(): Range {
  if (typeof window === 'undefined') return 90;
  const v = parseInt(window.localStorage.getItem(LS_RANGE) ?? '', 10);
  return (RANGE_OPTIONS as readonly number[]).includes(v) ? (v as Range) : 90;
}

interface Props {
  rows: PositionComputed[];
  tradesByTicker: Map<string, OptionTrade[]>;
  onTickerClick: (ticker: string) => void;
}

export function ExpiryCalendar({ rows, tradesByTicker, onTickerClick }: Props) {
  const [range, setRangeState] = useState<Range>(() => readRangeLS());
  const setRange = (r: Range) => {
    setRangeState(r);
    try { window.localStorage.setItem(LS_RANGE, String(r)); } catch { /* private */ }
  };

  const today = useMemo(() => startOfDayUTC(new Date()), []);
  // Show one extra week of history on the left so just-expired markers
  // are still visible.
  const start = useMemo(() => addDays(mondayOf(today), -7), [today]);
  const end = useMemo(() => addDays(start, range + 7), [start, range]);
  const totalDays = useMemo(
    () => Math.round((end.getTime() - start.getTime()) / DAY_MS),
    [start, end],
  );
  const startIso = useMemo(() => isoDay(start), [start]);
  const endIso = useMemo(() => isoDay(end), [end]);

  // Close index — open id → fully closed?
  const closedSet = useMemo(() => {
    const closedQty = new Map<string, number>();
    const openQty = new Map<string, number>();
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (t.action === 'open') openQty.set(t.id, t.contracts);
        if (t.action === 'close' && t.closes_trade_id) {
          closedQty.set(
            t.closes_trade_id,
            (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts,
          );
        }
      }
    }
    const s = new Set<string>();
    for (const [id, q] of closedQty) {
      if (q >= (openQty.get(id) ?? Infinity)) s.add(id);
    }
    return s;
  }, [tradesByTicker]);

  // Per-ticker P/C bucketing, filtered to the visible range.
  const tickerData = useMemo(() => {
    const out: Array<{
      ticker: string;
      sector: string;
      puts: OptionTrade[];
      calls: OptionTrade[];
    }> = [];
    for (const r of rows) {
      const list = tradesByTicker.get(r.ticker) ?? [];
      const puts: OptionTrade[] = [];
      const calls: OptionTrade[] = [];
      for (const t of list) {
        if (t.action !== 'open') continue;
        if (t.expiry < startIso || t.expiry >= endIso) continue;
        (t.option_type === 'put' ? puts : calls).push(t);
      }
      if (puts.length === 0 && calls.length === 0) continue;
      out.push({ ticker: r.ticker, sector: r.sector, puts, calls });
    }
    out.sort(
      (a, b) =>
        b.puts.length + b.calls.length - (a.puts.length + a.calls.length),
    );
    return out;
  }, [rows, tradesByTicker, startIso, endIso]);

  // Week ticks + month labels.
  const weekTicks = useMemo(() => {
    const ticks: Array<{ pct: number; monthLabel?: string }> = [];
    let cursor = mondayOf(start);
    let lastMonth = -1;
    while (cursor < end) {
      const pct =
        ((cursor.getTime() - start.getTime()) / (totalDays * DAY_MS)) * 100;
      const m = cursor.getUTCMonth();
      const monthLabel =
        m !== lastMonth
          ? cursor.toLocaleDateString('en-US', { month: 'short', timeZone: 'UTC' })
          : undefined;
      lastMonth = m;
      ticks.push({ pct, monthLabel });
      cursor = addDays(cursor, 7);
    }
    return ticks;
  }, [start, end, totalDays]);

  const todayPct = useMemo(
    () => ((today.getTime() - start.getTime()) / (totalDays * DAY_MS)) * 100,
    [today, start, totalDays],
  );

  function pctFor(iso: string): number {
    const d = new Date(iso + 'T00:00:00Z');
    return ((d.getTime() - start.getTime()) / (totalDays * DAY_MS)) * 100;
  }

  return (
    <div className="exp-wrap">
      <div className="exp-toolbar">
        <div className="exp-range">
          {RANGE_OPTIONS.map((d) => (
            <button
              key={d}
              className={range === d ? 'on' : ''}
              onClick={() => setRange(d)}
              title={`Show next ${d} days`}
            >
              {d}d
            </button>
          ))}
        </div>
        <div className="exp-legend">
          <span className="exp-legend-item">
            <i className="exp-leg put short" /> short put
          </span>
          <span className="exp-legend-item">
            <i className="exp-leg put long" /> long put
          </span>
          <span className="exp-legend-item">
            <i className="exp-leg call short" /> short call
          </span>
          <span className="exp-legend-item">
            <i className="exp-leg call long" /> long call
          </span>
        </div>
      </div>

      {tickerData.length === 0 ? (
        <div className="exp-empty">
          No option expiries in the next {range} days.
        </div>
      ) : (
        <div className="exp-grid">
          <div className="exp-hd-ticker" />
          <div className="exp-hd-axis">
            {weekTicks.map((t, i) => (
              <div key={i} className="exp-week" style={{ left: `${t.pct}%` }}>
                {t.monthLabel && <span className="exp-month">{t.monthLabel}</span>}
                <span className="exp-week-tick" />
              </div>
            ))}
            {todayPct >= 0 && todayPct <= 100 && (
              <div className="exp-today-line hd" style={{ left: `${todayPct}%` }}>
                <span className="exp-today-label">Today</span>
              </div>
            )}
          </div>

          {tickerData.map(({ ticker, sector, puts, calls }) => (
            <Fragment key={ticker}>
              <div className="exp-ticker">
                <button
                  className="exp-ticker-name"
                  onClick={() => onTickerClick(ticker)}
                  title={`Open ${ticker} insight`}
                >
                  {ticker}
                </button>
                <div className="exp-ticker-sub">
                  {sector}
                  <span className="exp-ticker-counts">
                    {puts.length > 0 && <span className="put">{puts.length}P</span>}
                    {calls.length > 0 && <span className="call">{calls.length}C</span>}
                  </span>
                </div>
              </div>
              <div className="exp-lanes">
                <Lane
                  kind="put"
                  trades={puts}
                  pctFor={pctFor}
                  closedSet={closedSet}
                  onClick={() => onTickerClick(ticker)}
                />
                <Lane
                  kind="call"
                  trades={calls}
                  pctFor={pctFor}
                  closedSet={closedSet}
                  onClick={() => onTickerClick(ticker)}
                />
                {todayPct >= 0 && todayPct <= 100 && (
                  <div
                    className="exp-today-line body"
                    style={{ left: `${todayPct}%` }}
                  />
                )}
              </div>
            </Fragment>
          ))}
        </div>
      )}
    </div>
  );
}

function Lane({
  kind,
  trades,
  pctFor,
  closedSet,
  onClick,
}: {
  kind: 'put' | 'call';
  trades: OptionTrade[];
  pctFor: (iso: string) => number;
  closedSet: Set<string>;
  onClick: () => void;
}) {
  return (
    <div className={`exp-lane ${kind}`}>
      <span className={`exp-lane-tag ${kind}`}>{kind === 'put' ? 'P' : 'C'}</span>
      <div className={`exp-rule ${kind}`} />
      {trades.map((t) => {
        const expiryPct = pctFor(t.expiry);
        const tradePct = pctFor(t.trade_date);
        // Clamp left edge to 0 — if the trade opened before the visible
        // range, the bar starts at the left wall (with a "·····" cap to
        // indicate it extends off-screen).
        const clampedLeft = Math.max(0, tradePct);
        const width = Math.max(2, expiryPct - clampedLeft);
        const extendsLeft = tradePct < 0;
        return (
          <Bar
            key={t.id}
            t={t}
            left={clampedLeft}
            width={width}
            extendsLeft={extendsLeft}
            closed={closedSet.has(t.id)}
            onClick={onClick}
          />
        );
      })}
    </div>
  );
}

function Bar({
  t,
  left,
  width,
  extendsLeft,
  closed,
  onClick,
}: {
  t: OptionTrade;
  left: number;
  width: number;
  extendsLeft: boolean;
  closed: boolean;
  onClick: () => void;
}) {
  const isShort = t.direction === 'short';
  const cls =
    'exp-bar ' +
    t.option_type +
    ' ' +
    (isShort ? 'short' : 'long') +
    (closed ? ' closed' : '') +
    (extendsLeft ? ' extends' : '');
  const expiryD = new Date(t.expiry + 'T00:00:00Z');
  const expiryLabel = expiryD.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });
  const notional = t.contracts * 100 * t.premium;
  const title =
    `${t.ticker} · ${t.direction} ${t.option_type} ${t.contracts}× $${t.strike} · ` +
    `opened ${t.trade_date} · expires ${expiryLabel} · ` +
    `${fmtCompact(notional)} premium` +
    (closed ? ' · closed' : '');
  return (
    <button
      type="button"
      className={cls}
      style={{ left: `${left}%`, width: `${width}%` }}
      title={title}
      onClick={onClick}
    >
      <span className="exp-bar-label">
        <span className="exp-bar-strike">${t.strike}</span>
        {t.contracts > 1 && <span className="exp-bar-x">×{t.contracts}</span>}
      </span>
    </button>
  );
}
