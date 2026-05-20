import { useMemo, useState } from 'react';
import { fmtCompact, type OptionTrade } from './types';

/**
 * Expiry calendar — one week at a time, days as columns.
 *
 * Each option OPEN is plotted on its expiry date. Multiple opens on the
 * same day stack inside the day cell. No hour grid — option expiry is a
 * date concern, not a time concern (US options expire 16:00 ET regardless).
 *
 * Color/state:
 *   - short open (cash collected) → green tint
 *   - long open  (cash paid)      → red tint   (protective puts mostly)
 *   - fully closed open           → muted/strikethrough (history)
 *
 * Clicking a card opens the position insight modal.
 */

interface Props {
  tradesByTicker: Map<string, OptionTrade[]>;
  onTickerClick: (ticker: string) => void;
}

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
function fmtMonthDay(d: Date): string {
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
}

export function ExpiryCalendar({ tradesByTicker, onTickerClick }: Props) {
  const todayMonday = useMemo(() => mondayOf(new Date()), []);
  const todayIso = useMemo(() => isoDay(startOfDayUTC(new Date())), []);
  const [weekOffset, setWeekOffset] = useState(0);

  const weekStart = useMemo(() => addDays(todayMonday, weekOffset * 7), [todayMonday, weekOffset]);
  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => addDays(weekStart, i)), [weekStart]);

  // Index expiry-date → list of {open, isClosed}, computed once.
  const expiryIndex = useMemo(() => {
    const closedQtyByOpen = new Map<string, number>();
    const openQtyById = new Map<string, number>();
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (t.action === 'open') openQtyById.set(t.id, t.contracts);
        if (t.action === 'close' && t.closes_trade_id) {
          closedQtyByOpen.set(
            t.closes_trade_id,
            (closedQtyByOpen.get(t.closes_trade_id) ?? 0) + t.contracts,
          );
        }
      }
    }
    const map = new Map<string, Array<{ open: OptionTrade; isClosed: boolean }>>();
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (t.action !== 'open') continue;
        const closed = (closedQtyByOpen.get(t.id) ?? 0) >= t.contracts;
        const arr = map.get(t.expiry) ?? [];
        arr.push({ open: t, isClosed: closed });
        map.set(t.expiry, arr);
      }
    }
    // Sort each day's stack: live first, then by ticker.
    for (const arr of map.values()) {
      arr.sort((a, b) => {
        if (a.isClosed !== b.isClosed) return a.isClosed ? 1 : -1;
        return a.open.ticker.localeCompare(b.open.ticker);
      });
    }
    return map;
  }, [tradesByTicker]);

  // Weekly totals across the visible days — count + collected/paid.
  const weekSummary = useMemo(() => {
    let count = 0;
    let collected = 0;
    let paid = 0;
    for (const d of days) {
      const items = expiryIndex.get(isoDay(d)) ?? [];
      for (const { open, isClosed } of items) {
        if (isClosed) continue;
        count += 1;
        const notional = open.contracts * 100 * open.premium;
        if (open.direction === 'short') collected += notional;
        else paid += notional;
      }
    }
    return { count, collected, paid };
  }, [days, expiryIndex]);

  const weekLabel = `${fmtMonthDay(days[0])} – ${fmtMonthDay(days[6])}`;
  const yearLabel = days[0].getUTCFullYear();

  return (
    <div className="cal-wrap">
      <div className="cal-toolbar">
        <div className="cal-nav">
          <button onClick={() => setWeekOffset((o) => o - 1)} title="Previous week">◀</button>
          <button
            className={weekOffset === 0 ? 'on' : ''}
            onClick={() => setWeekOffset(0)}
          >
            Today
          </button>
          <button onClick={() => setWeekOffset((o) => o + 1)} title="Next week">▶</button>
        </div>
        <div className="cal-range">
          <div className="cal-range-week">{weekLabel}</div>
          <div className="cal-range-year">{yearLabel}</div>
        </div>
        <div className="cal-summary">
          <span className="cal-sum-item">
            <span className="cal-sum-k">Expiring</span>
            <span className="cal-sum-v">{weekSummary.count}</span>
          </span>
          {weekSummary.collected > 0 && (
            <span className="cal-sum-item">
              <span className="cal-sum-k">Collected</span>
              <span className="cal-sum-v up">{fmtCompact(weekSummary.collected)}</span>
            </span>
          )}
          {weekSummary.paid > 0 && (
            <span className="cal-sum-item">
              <span className="cal-sum-k">Paid</span>
              <span className="cal-sum-v down">−{fmtCompact(weekSummary.paid)}</span>
            </span>
          )}
        </div>
      </div>

      <div className="cal-grid">
        {days.map((d, i) => {
          const iso = isoDay(d);
          const items = expiryIndex.get(iso) ?? [];
          const isToday = iso === todayIso;
          const isPast = iso < todayIso;
          const isWeekend = i >= 5;
          return (
            <div
              key={iso}
              className={
                'cal-day' +
                (isToday ? ' today' : '') +
                (isPast ? ' past' : '') +
                (isWeekend ? ' weekend' : '')
              }
            >
              <div className="cal-day-hd">
                <span className="cal-dow">
                  {d.toLocaleDateString('en-US', { weekday: 'short', timeZone: 'UTC' })}
                </span>
                <span className="cal-dom">{d.getUTCDate()}</span>
              </div>
              <div className="cal-day-body">
                {items.length === 0 ? (
                  <div className="cal-day-empty">—</div>
                ) : (
                  items.map(({ open, isClosed }) => {
                    const isShort = open.direction === 'short';
                    const sideClass = isClosed
                      ? 'closed'
                      : isShort
                        ? 'short'
                        : 'long';
                    const typeChar = open.option_type === 'put' ? 'P' : 'C';
                    const notional = open.contracts * 100 * open.premium;
                    const title =
                      `${open.ticker} · ${open.direction} ${open.option_type} ` +
                      `${open.contracts}× $${open.strike} @ $${open.premium} · ` +
                      `opened ${open.trade_date}${isClosed ? ' · closed' : ''}`;
                    return (
                      <button
                        key={open.id}
                        type="button"
                        className={`cal-card ${sideClass} type-${open.option_type}`}
                        title={title}
                        onClick={() => onTickerClick(open.ticker)}
                      >
                        <div className="cal-card-top">
                          <span className="cal-card-tk">{open.ticker}</span>
                          <span className="cal-card-side">
                            {isShort ? '−' : '+'}{typeChar}
                          </span>
                        </div>
                        <div className="cal-card-mid">
                          <span className="cal-card-strike">${open.strike}</span>
                          <span className="cal-card-qty">×{open.contracts}</span>
                        </div>
                        <div className="cal-card-prem">{fmtCompact(notional)}</div>
                      </button>
                    );
                  })
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
