import { useMemo } from 'react';
import { Link } from 'react-router-dom';
import {
  BEAT_LABEL,
  BUCKET_LABEL,
  bucketFor,
  daysUntil,
  type FeedRow,
  type TimeBucket,
} from './types';

const fmtPct = (n: number) => `${n.toFixed(1)}%`;
const fmtUSDk = (n: number) =>
  n >= 1e6 ? `$${(n / 1e6).toFixed(2)}M` : n >= 1e3 ? `$${(n / 1e3).toFixed(0)}k` : `$${n.toFixed(0)}`;

const BUCKETS: TimeBucket[] = ['this-week', 'next-week', 'coming-up'];

interface Props {
  feed: FeedRow[];
  loading?: boolean;
}

export function EarningsFeed({ feed, loading }: Props) {
  // Group rows into buckets by days_to_earnings.
  const byBucket = useMemo(() => {
    const m: Record<TimeBucket, FeedRow[]> = {
      'this-week': [],
      'next-week': [],
      'coming-up': [],
      past: [],
    };
    for (const r of feed) {
      const b = r.days_to_earnings == null ? 'past' : bucketFor(r.days_to_earnings);
      // We only render the three forward buckets in the main feed. Rows
      // without a date or in the past land in a small "no upcoming date"
      // bucket below.
      if (b === 'past') m.past.push(r);
      else m[b].push(r);
    }
    return m;
  }, [feed]);

  // Hero candidate: nearest event for an owned ticker in the next 30 days.
  const hero = useMemo(() => {
    const owned = feed.filter(
      (r) =>
        r.origin === 'owned' &&
        r.days_to_earnings != null &&
        r.days_to_earnings >= 0 &&
        r.days_to_earnings <= 30,
    );
    return owned[0] ?? null;
  }, [feed]);

  if (loading && feed.length === 0) {
    return <div className="np-empty"><p>Loading earnings…</p></div>;
  }

  const visibleCount = BUCKETS.reduce((s, k) => s + byBucket[k].length, 0);

  return (
    <div className="er-stage">
      {hero && (
        <div className="er-hero">
          <div className="er-hero-l">Next event</div>
          <div className="er-hero-line">
            <Link to={`/earnings/${hero.ticker}`} className="er-hero-ticker">
              {hero.ticker}
            </Link>
            <span className="er-hero-when">
              {hero.days_to_earnings === 0
                ? 'today'
                : hero.days_to_earnings === 1
                  ? 'tomorrow'
                  : `in ${hero.days_to_earnings} days`}
            </span>
            {hero.portfolio_pct != null && (
              <span className="er-hero-chip">{fmtPct(hero.portfolio_pct)} of book</span>
            )}
            {hero.put_expiry && (
              <span className="er-hero-put">
                put expires {hero.put_expiry} ({daysUntil(hero.put_expiry)}d)
              </span>
            )}
          </div>
        </div>
      )}

      {visibleCount === 0 && (
        <div className="np-empty">
          <p>No upcoming earnings in the next 30 days.</p>
          <p style={{ marginTop: 8, color: 'var(--navi-fg4)' }}>
            Open a ticker hub below to add an event date or a peer.
          </p>
        </div>
      )}

      {BUCKETS.map((b) => {
        const rows = byBucket[b];
        if (rows.length === 0) return null;
        return (
          <section key={b} className="er-bucket">
            <h2 className="er-bucket-hd">
              {BUCKET_LABEL[b]} <span className="er-bucket-ct">· {rows.length}</span>
            </h2>
            <div className="er-cards">
              {rows.map((r) => <EarningsCard key={r.ticker} row={r} />)}
            </div>
          </section>
        );
      })}

      {byBucket.past.length > 0 && (
        <section className="er-bucket muted">
          <h2 className="er-bucket-hd">Other tickers</h2>
          <div className="er-cards">
            {byBucket.past.map((r) => <EarningsCard key={r.ticker} row={r} />)}
          </div>
        </section>
      )}
    </div>
  );
}

function EarningsCard({ row }: { row: FeedRow }) {
  const e = row.event;
  const isOwned = row.origin === 'owned';
  return (
    <Link
      to={`/earnings/${row.ticker}`}
      className={'er-card er-card-' + row.origin}
      title={`Open ${row.ticker} hub`}
    >
      <div className="er-card-hd">
        <span className="er-card-ticker">{row.ticker}</span>
        <span className={'er-origin-pill ' + row.origin}>
          {row.origin === 'peer' ? `peer of ${row.peer_of}` : row.origin}
        </span>
      </div>
      <div className="er-card-meta">
        {row.sector && <span>{row.sector}</span>}
        {isOwned && row.portfolio_pct != null && (
          <>
            <span className="dot">·</span>
            <span>{fmtPct(row.portfolio_pct)} book</span>
          </>
        )}
        {isOwned && row.market_value != null && (
          <>
            <span className="dot">·</span>
            <span>{fmtUSDk(row.market_value)}</span>
          </>
        )}
      </div>
      <div className="er-card-body">
        {e ? (
          <>
            <div className="er-card-date">
              {e.earnings_date}
              {e.fiscal_period && <span className="er-card-fp"> · {e.fiscal_period}</span>}
            </div>
            <div className="er-card-when">
              {row.days_to_earnings == null
                ? '—'
                : row.days_to_earnings < 0
                  ? `${-row.days_to_earnings}d ago`
                  : row.days_to_earnings === 0
                    ? 'today'
                    : `in ${row.days_to_earnings} days`}
            </div>
            {e.beat_status && (
              <span className={'er-tag beat ' + e.beat_status}>{BEAT_LABEL[e.beat_status]}</span>
            )}
            {e.sentiment && (
              <span className={'er-tag sent ' + e.sentiment}>{e.sentiment}</span>
            )}
            {!e.summary && row.days_to_earnings != null && row.days_to_earnings < 0 && (
              <span className="er-card-warn">no summary yet · add</span>
            )}
          </>
        ) : (
          <div className="er-card-empty">no event logged</div>
        )}
        {isOwned && row.put_expiry && row.days_to_earnings != null && (
          <div className="er-card-put">
            put expires {row.put_expiry} ({daysUntil(row.put_expiry)}d)
          </div>
        )}
      </div>
    </Link>
  );
}
