import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { toast } from 'sonner';
import { useEarnings } from './useEarnings';
import {
  BEAT_LABEL,
  daysUntil,
  SENTIMENT_LABEL,
  type EarningsEvent,
} from './types';

export function TickerHub() {
  const { ticker: rawTicker } = useParams<{ ticker: string }>();
  const ticker = (rawTicker ?? '').toUpperCase();
  const nav = useNavigate();
  const { eventsByTicker, peersByTicker, addPeer, removePeer, upsertEvent } = useEarnings();

  const events = eventsByTicker.get(ticker) ?? [];
  const peers = peersByTicker.get(ticker) ?? [];

  const upcoming = events.filter((e) => daysUntil(e.earnings_date) >= 0);
  const history = events.filter((e) => daysUntil(e.earnings_date) < 0);

  const [newDate, setNewDate] = useState('');
  const [newPeriod, setNewPeriod] = useState('');

  // After creating an event, jump straight into its editor so the user
  // lands on the summary textarea — saves a click and makes the "add
  // event = write summary" intent obvious.
  const addEvent = () => {
    if (!newDate) return;
    upsertEvent.mutate(
      { ticker, earnings_date: newDate, fiscal_period: newPeriod || null },
      {
        onSuccess: () => {
          toast.success(`Created · ${ticker} ${newDate}`);
          const target = `/earnings/${ticker}/${newDate}`;
          setNewDate(''); setNewPeriod('');
          nav(target);
        },
        onError: (e) => toast.error((e as Error).message),
      },
    );
  };

  return (
    <div className="er-stage">
      <div className="er-hub-hd">
        <Link to="/earnings" className="er-back">← back to feed</Link>
        <h1 className="er-hub-title">{ticker}</h1>
      </div>

      {/* Add event — works for past OR upcoming dates. Picking a date
          past today logs a historical earnings; picking a future date
          logs an upcoming one. Either way, saving jumps to the editor. */}
      <section className="er-hub-section">
        <h2 className="er-bucket-hd">+ Log earnings event</h2>
        <p className="er-hint">
          Pick a date — past or upcoming. You'll be taken to the editor to write the summary.
        </p>
        <div className="er-add-event">
          <input
            type="date"
            className="np-input"
            value={newDate}
            onChange={(e) => setNewDate(e.target.value)}
          />
          <input
            className="np-input"
            placeholder="Fiscal period (e.g. Q1 26)"
            value={newPeriod}
            onChange={(e) => setNewPeriod(e.target.value)}
          />
          <button className="np-btn neon" onClick={addEvent} disabled={!newDate}>
            + Add &amp; write summary
          </button>
        </div>
      </section>

      {/* Upcoming */}
      {upcoming.length > 0 && (
        <section className="er-hub-section">
          <h2 className="er-bucket-hd">
            Upcoming <span className="er-bucket-ct">· {upcoming.length}</span>
          </h2>
          <div className="er-cards">
            {upcoming.map((e) => <EventRow key={e.id} ticker={ticker} event={e} />)}
          </div>
        </section>
      )}

      {/* History */}
      <section className="er-hub-section">
        <h2 className="er-bucket-hd">
          History {history.length > 0 && <span className="er-bucket-ct">· {history.length}</span>}
        </h2>
        {history.length === 0 ? (
          <p className="er-empty-l">No past earnings logged for {ticker} yet.</p>
        ) : (
          <div className="er-history">
            {history.map((e) => <EventRow key={e.id} ticker={ticker} event={e} />)}
          </div>
        )}
      </section>

      {/* Peers */}
      <PeerEditor
        ticker={ticker}
        peers={peers}
        onAdd={(peer) =>
          addPeer.mutate(
            { ticker, peer },
            { onError: (e) => toast.error((e as Error).message) },
          )
        }
        onRemove={(peer) =>
          removePeer.mutate(
            { ticker, peer },
            { onError: (e) => toast.error((e as Error).message) },
          )
        }
      />
    </div>
  );
}

function EventRow({ ticker, event }: { ticker: string; event: EarningsEvent }) {
  const days = daysUntil(event.earnings_date);
  return (
    <Link
      to={`/earnings/${ticker}/${event.earnings_date}`}
      className="er-evt-row"
    >
      <div className="er-evt-date">
        <span className="d">{event.earnings_date}</span>
        {event.fiscal_period && <span className="fp">{event.fiscal_period}</span>}
        <span className="ago">
          {days < 0 ? `${-days}d ago` : days === 0 ? 'today' : `in ${days}d`}
        </span>
      </div>
      <div className="er-evt-tags">
        {event.beat_status && (
          <span className={'er-tag beat ' + event.beat_status}>{BEAT_LABEL[event.beat_status]}</span>
        )}
        {event.sentiment && (
          <span className={'er-tag sent ' + event.sentiment}>{SENTIMENT_LABEL[event.sentiment]}</span>
        )}
        {!event.summary && days < 0 && (
          <span className="er-tag warn">no summary</span>
        )}
      </div>
      <div className="er-evt-preview">
        {event.summary
          ? event.summary.length > 180
            ? event.summary.slice(0, 180) + '…'
            : event.summary
          : <span className="muted">tap to add summary</span>}
      </div>
    </Link>
  );
}

function PeerEditor({
  ticker, peers, onAdd, onRemove,
}: {
  ticker: string;
  peers: string[];
  onAdd: (peer: string) => void;
  onRemove: (peer: string) => void;
}) {
  const [val, setVal] = useState('');
  const submit = () => {
    const v = val.trim().toUpperCase();
    if (!v || v === ticker) return;
    onAdd(v);
    setVal('');
  };
  return (
    <section className="er-hub-section">
      <h2 className="er-bucket-hd">Peers</h2>
      <div className="er-peers">
        {peers.length === 0 && (
          <span className="muted" style={{ fontSize: 12 }}>No peers added yet</span>
        )}
        {peers.map((p) => (
          <span key={p} className="er-peer-chip">
            <Link to={`/earnings/${p}`}>{p}</Link>
            <button
              className="er-peer-x"
              onClick={() => onRemove(p)}
              title={`Remove ${p} as peer`}
            >
              ×
            </button>
          </span>
        ))}
        <span className="er-peer-add">
          <input
            className="np-input"
            placeholder="add peer (e.g. ADBE)"
            value={val}
            onChange={(e) => setVal(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && submit()}
            style={{ width: 160 }}
          />
          <button className="np-btn ghost" onClick={submit} disabled={!val.trim()}>
            + add
          </button>
        </span>
      </div>
    </section>
  );
}
