// Data shapes shared across the /earnings module.

export type BeatStatus = 'beat' | 'met' | 'missed';
export type Sentiment = 'bullish' | 'cautious' | 'bearish';

/** One row in the earnings_events table. Future events have summary=null. */
export interface EarningsEvent {
  id: string;
  ticker: string;
  earnings_date: string;          // ISO date 'YYYY-MM-DD'
  fiscal_period: string | null;   // e.g. 'Q4 25'
  summary: string | null;
  beat_status: BeatStatus | null;
  sentiment: Sentiment | null;
  rev_reported: number | null;
  eps_reported: number | null;
  guidance_note: string | null;
  source_url: string | null;
  created_at: string;
  updated_at: string;
}

export interface TickerPeer {
  ticker: string;
  peer: string;
  created_at: string;
}

/** A ticker that shows up in the upcoming feed, with its category. The three
 *  tiers are rendered with descending visual weight on the page. */
export type TickerOrigin = 'owned' | 'watching' | 'peer';

export interface FeedTicker {
  ticker: string;
  origin: TickerOrigin;
  sector: string | null;
  market_value?: number;          // only for 'owned'
  portfolio_pct?: number;         // only for 'owned'
  put_expiry?: string | null;     // ISO date, only for 'owned' with active protection
  /** When origin === 'peer', the owned/watching ticker that pulled this peer in. */
  peer_of?: string;
}

/** Aggregate row for the upcoming feed: a ticker + its next event. */
export interface FeedRow extends FeedTicker {
  event: EarningsEvent | null;    // null = we know about the ticker but no event row yet
  days_to_earnings: number | null;
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Days between today (UTC) and an ISO date string. Negative = in the past. */
export function daysUntil(iso: string): number {
  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);
  const target = new Date(iso + 'T00:00:00Z');
  return Math.round((target.getTime() - today.getTime()) / MS_PER_DAY);
}

/** Bucket label for the upcoming feed sections. */
export type TimeBucket = 'this-week' | 'next-week' | 'coming-up' | 'past';
export function bucketFor(daysOut: number): TimeBucket {
  if (daysOut < 0) return 'past';
  if (daysOut <= 7) return 'this-week';
  if (daysOut <= 14) return 'next-week';
  if (daysOut <= 30) return 'coming-up';
  return 'past'; // beyond 30 falls out of the feed; treat as past for grouping
}

export const BUCKET_LABEL: Record<TimeBucket, string> = {
  'this-week': 'This week',
  'next-week': 'Next week',
  'coming-up': 'Coming up',
  past: 'Later / past',
};

export const ORIGIN_LABEL: Record<TickerOrigin, string> = {
  owned: 'Owned',
  watching: 'Watching',
  peer: 'Peer',
};

export const BEAT_LABEL: Record<BeatStatus, string> = {
  beat: '▲ Beat',
  met: '— Met',
  missed: '▼ Missed',
};

export const SENTIMENT_LABEL: Record<Sentiment, string> = {
  bullish: 'Bullish',
  cautious: 'Cautious',
  bearish: 'Bearish',
};
