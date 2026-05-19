import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { toast } from 'sonner';
import { useEarnings } from './useEarnings';
import {
  BEAT_LABEL,
  SENTIMENT_LABEL,
  type BeatStatus,
  type EarningsEvent,
  type Sentiment,
} from './types';

const BEATS: BeatStatus[] = ['beat', 'met', 'missed'];
const SENTS: Sentiment[] = ['bullish', 'cautious', 'bearish'];

export function EventDetail() {
  const { ticker: rawTicker, date } = useParams<{ ticker: string; date: string }>();
  const ticker = (rawTicker ?? '').toUpperCase();
  const nav = useNavigate();
  const { eventsByTicker, upsertEvent, deleteEvent } = useEarnings();

  const event = useMemo(() => {
    const list = eventsByTicker.get(ticker) ?? [];
    return list.find((e) => e.earnings_date === date) ?? null;
  }, [eventsByTicker, ticker, date]);

  // Last quarter's summary (the next-most-recent event before this one) —
  // surfaces inline at the bottom so the user can write with prior context.
  const previous = useMemo(() => {
    if (!event) return null;
    const list = eventsByTicker.get(ticker) ?? [];
    return list
      .filter((e) => e.earnings_date < event.earnings_date)
      .sort((a, b) => b.earnings_date.localeCompare(a.earnings_date))[0] ?? null;
  }, [eventsByTicker, ticker, event]);

  // Local form state; sync when the event row arrives or the route changes.
  const [period, setPeriod] = useState('');
  const [summary, setSummary] = useState('');
  const [beat, setBeat] = useState<BeatStatus | null>(null);
  const [sentiment, setSentiment] = useState<Sentiment | null>(null);
  const [rev, setRev] = useState('');
  const [eps, setEps] = useState('');
  const [guidance, setGuidance] = useState('');
  const [source, setSource] = useState('');
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (!event) return;
    setPeriod(event.fiscal_period ?? '');
    setSummary(event.summary ?? '');
    setBeat(event.beat_status);
    setSentiment(event.sentiment);
    setRev(event.rev_reported != null ? String(event.rev_reported) : '');
    setEps(event.eps_reported != null ? String(event.eps_reported) : '');
    setGuidance(event.guidance_note ?? '');
    setSource(event.source_url ?? '');
    setDirty(false);
  }, [event?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!event) {
    return (
      <div className="er-stage">
        <div className="er-hub-hd">
          <Link to={`/earnings/${ticker}`} className="er-back">← back to {ticker}</Link>
        </div>
        <div className="np-empty">
          <p>No event found for {ticker} on {date}.</p>
        </div>
      </div>
    );
  }

  const save = () => {
    upsertEvent.mutate(
      {
        id: event.id,
        ticker,
        earnings_date: event.earnings_date,
        fiscal_period: period || null,
        summary: summary || null,
        beat_status: beat,
        sentiment,
        rev_reported: rev ? parseFloat(rev) : null,
        eps_reported: eps ? parseFloat(eps) : null,
        guidance_note: guidance || null,
        source_url: source || null,
      },
      {
        onSuccess: () => { toast.success('Saved'); setDirty(false); },
        onError: (e) => toast.error((e as Error).message),
      },
    );
  };

  const remove = () => {
    if (!window.confirm(`Delete the ${event.earnings_date} event for ${ticker}? Summary will be lost.`)) return;
    deleteEvent.mutate(event.id, {
      onSuccess: () => { toast.success('Deleted'); nav(`/earnings/${ticker}`); },
      onError: (e) => toast.error((e as Error).message),
    });
  };

  return (
    <div className="er-stage">
      <div className="er-hub-hd">
        <Link to={`/earnings/${ticker}`} className="er-back">← back to {ticker}</Link>
        <h1 className="er-hub-title">
          {ticker} <span className="er-evt-date-inline">{event.earnings_date}</span>
        </h1>
      </div>

      {/* Tag row */}
      <div className="er-evt-tagrow">
        <div className="er-tag-group">
          <label>Result</label>
          {BEATS.map((b) => (
            <button
              key={b}
              type="button"
              className={'er-tag-pick beat ' + b + (beat === b ? ' on' : '')}
              onClick={() => { setBeat(beat === b ? null : b); setDirty(true); }}
            >
              {BEAT_LABEL[b]}
            </button>
          ))}
        </div>
        <div className="er-tag-group">
          <label>Sentiment</label>
          {SENTS.map((s) => (
            <button
              key={s}
              type="button"
              className={'er-tag-pick sent ' + s + (sentiment === s ? ' on' : '')}
              onClick={() => { setSentiment(sentiment === s ? null : s); setDirty(true); }}
            >
              {SENTIMENT_LABEL[s]}
            </button>
          ))}
        </div>
        <div className="er-tag-group">
          <label>Fiscal period</label>
          <input
            className="np-input"
            placeholder="Q4 25"
            value={period}
            onChange={(e) => { setPeriod(e.target.value); setDirty(true); }}
            style={{ width: 100 }}
          />
        </div>
      </div>

      {/* Summary */}
      <section className="er-evt-section">
        <label className="er-evt-l">Summary / takeaways</label>
        <textarea
          className="er-textarea"
          rows={10}
          placeholder="Key points from the call. Revenue beat, guide direction, themes mentioned, your read…"
          value={summary}
          onChange={(e) => { setSummary(e.target.value); setDirty(true); }}
        />
      </section>

      {/* Structured fields */}
      <section className="er-evt-section">
        <div className="er-evt-grid">
          <div className="qa-field">
            <label>Revenue reported</label>
            <input
              className="np-input"
              type="number"
              step="0.01"
              value={rev}
              onChange={(e) => { setRev(e.target.value); setDirty(true); }}
              placeholder="in $M"
            />
          </div>
          <div className="qa-field">
            <label>EPS reported</label>
            <input
              className="np-input"
              type="number"
              step="0.01"
              value={eps}
              onChange={(e) => { setEps(e.target.value); setDirty(true); }}
              placeholder="$"
            />
          </div>
          <div className="qa-field">
            <label>Guidance note</label>
            <input
              className="np-input"
              value={guidance}
              onChange={(e) => { setGuidance(e.target.value); setDirty(true); }}
              placeholder="raised / lowered / in-line / withdrew"
            />
          </div>
          <div className="qa-field">
            <label>Source URL</label>
            <input
              className="np-input"
              type="url"
              value={source}
              onChange={(e) => { setSource(e.target.value); setDirty(true); }}
              placeholder="https://…"
            />
          </div>
        </div>
      </section>

      {/* Actions */}
      <div className="er-evt-actions">
        <button className="np-btn ghost" onClick={remove}>Delete event</button>
        <div style={{ flex: 1 }} />
        <button className="np-btn neon" onClick={save} disabled={!dirty}>
          {dirty ? '✓ Save' : 'Saved'}
        </button>
      </div>

      {/* Previous quarter — read-only context */}
      {previous && (
        <section className="er-evt-prev">
          <h2 className="er-bucket-hd">
            Last event · {previous.earnings_date}
            {previous.fiscal_period && <span className="er-card-fp"> · {previous.fiscal_period}</span>}
          </h2>
          <div className="er-evt-tags">
            {previous.beat_status && (
              <span className={'er-tag beat ' + previous.beat_status}>{BEAT_LABEL[previous.beat_status]}</span>
            )}
            {previous.sentiment && (
              <span className={'er-tag sent ' + previous.sentiment}>{SENTIMENT_LABEL[previous.sentiment]}</span>
            )}
          </div>
          <p className="er-evt-prev-summary">
            {previous.summary || <span className="muted">no summary on the prior event</span>}
          </p>
        </section>
      )}
    </div>
  );
}
