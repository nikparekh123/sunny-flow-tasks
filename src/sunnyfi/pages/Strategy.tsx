/**
 * Strategy — bucket overlays + weekly journal on top of canonical positions.
 *
 * positions is the source of truth (owned by /positions). This page only
 * writes to strategy_overlay + gain_entries.
 *
 * NOTE: Drag-and-drop, full Edit/Sell/Move modals, treemap layout, and the
 * dedicated /strategy/gains page are not yet ported from the SWM handoff
 * bundle. The page assigns + logs gains via two inline modals; bucket
 * moves use a per-card dropdown.
 */
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { useStrategy } from '../strategy/useStrategy';
import {
  calcBucket,
  calcPortfolio,
  calcPosition,
  fmt$,
  fmtK,
  fmtPct,
  fmtPx,
  fmtSigned,
  mondayOf,
} from '../strategy/calc';
import {
  type Bucket,
  type StrategyPosition,
  type PutFrequency,
  BUCKET_META,
  PUT_FREQUENCIES,
  FREQ_LABEL,
} from '../strategy/types';
import '@/sunnyfi/research.css';
import '@/sunnyfi/strategy.css';

const DASHBOARD_URL = 'https://www.sunnyfi.co/dashboard';
const BUCKETS: Bucket[] = ['income', 'invest', 'yield'];

type ModalState =
  | { kind: 'assign'; ticker: string }
  | { kind: 'log-gain'; ticker: string }
  | null;

export default function Strategy() {
  const s = useStrategy();
  const [modal, setModal] = useState<ModalState>(null);

  const bucketCalcs = useMemo(
    () => ({
      income: calcBucket(s.assigned.income, 'income'),
      invest: calcBucket(s.assigned.invest, 'invest'),
      yield:  calcBucket(s.assigned.yield,  'yield'),
    }),
    [s.assigned],
  );

  const portfolio = useMemo(() => calcPortfolio(bucketCalcs), [bucketCalcs]);

  if (s.isLoading) {
    return <div className="strat-page">…</div>;
  }

  return (
    <div className="strat-page">
      <div className="np-top">
        <div className="np-crumbs">
          <a href={DASHBOARD_URL} className="np-crumb">
            SUNNYFI
          </a>
          <span className="np-crumb-sep">/</span>
          <span className="np-crumb">STRATEGY</span>
        </div>
        <div className="np-actions">
          <Link to="/snowball" className="np-btn ghost">
            Snowball
          </Link>
          <a
            href="https://positions.sunnyfi.co"
            className="np-btn ghost"
          >
            Positions ↗
          </a>
        </div>
      </div>

      {/* Banner */}
      <div className="strat-banner">
        <div className="hero">
          <div className="hero-label">Total profit · this quarter</div>
          <div className="hero-num">{fmtK(portfolio.total)}</div>
          <div className="hero-sub">
            {portfolio.verdict === 'ahead'
              ? 'Ahead of pace'
              : portfolio.verdict === 'on-track'
                ? 'On track'
                : 'Behind pace'}{' '}
            · {fmtPct(portfolio.onTrack * 100, 0)} of expected
          </div>
        </div>
        <div>
          <div className="stat-label">Premium collected</div>
          <div className="stat-num pos">{fmtK(portfolio.collected)}</div>
        </div>
        <div>
          <div className="stat-label">Share P&amp;L</div>
          <div
            className={
              'stat-num ' + (portfolio.sharePL >= 0 ? 'pos' : 'neg')
            }
          >
            {fmtSigned(portfolio.sharePL)}
          </div>
        </div>
      </div>

      {/* Allocation strip */}
      <div className="strat-alloc">
        <div className="income" />
        <div className="invest" />
        <div className="yield" />
      </div>

      {/* Unassigned positions */}
      {s.unassigned.length > 0 && (
        <div className="strat-unassigned">
          <div className="strat-unassigned-hd">
            <span>Unassigned · {s.unassigned.length}</span>
            <span>click a card to set its strategy</span>
          </div>
          <div className="strat-unassigned-strip">
            {s.unassigned.map((p) => (
              <button
                key={p.ticker}
                className="strat-unassigned-card"
                onClick={() => setModal({ kind: 'assign', ticker: p.ticker })}
              >
                <div className="ticker">{p.ticker}</div>
                <div className="name">{p.name ?? p.sector}</div>
                <div className="px">
                  {p.current_price != null ? fmtPx(p.current_price) : '—'}
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Three bucket columns */}
      <div className="strat-board">
        {BUCKETS.map((key) => {
          const b = bucketCalcs[key];
          const positions = s.assigned[key];
          return (
            <div key={key} className={'strat-bucket ' + key}>
              <div className="hd">
                <span className="name">
                  {BUCKET_META[key].name} · {b.count}
                </span>
                <span className="total">{fmtK(b.value)}</span>
              </div>
              <div className="strat-bucket-cards">
                {positions.length === 0 && (
                  <div className="strat-empty">no positions in {key}</div>
                )}
                {positions.map((p) => (
                  <PositionCard
                    key={p.ticker}
                    p={p}
                    onMove={(to) =>
                      s.moveBucket.mutate(
                        { ticker: p.ticker, to },
                        {
                          onSuccess: () =>
                            toast.success(
                              `${p.ticker} → ${BUCKET_META[to].name}`,
                            ),
                          onError: (e) => toast.error((e as Error).message),
                        },
                      )
                    }
                    onUnassign={() =>
                      s.unassign.mutate(p.ticker, {
                        onSuccess: () =>
                          toast.success(`${p.ticker} unassigned`),
                        onError: (e) => toast.error((e as Error).message),
                      })
                    }
                    onLogGain={() =>
                      setModal({ kind: 'log-gain', ticker: p.ticker })
                    }
                  />
                ))}
              </div>
            </div>
          );
        })}
      </div>

      {/* Closed */}
      {s.closed.length > 0 && (
        <div className="strat-closed">
          <div className="strat-closed-hd">Closed · {s.closed.length}</div>
          {s.closed.map((p) => {
            const c = calcPosition(p);
            return (
              <div key={p.ticker} className="strat-closed-row">
                <span style={{ fontFamily: 'var(--navi-font-mono)' }}>
                  {p.ticker}
                </span>
                <span>{BUCKET_META[p.overlay!.bucket].name}</span>
                <span>{fmtK(c.collected)} prem</span>
                <span>{p.overlay!.days_held}d held</span>
              </div>
            );
          })}
        </div>
      )}

      {/* Modals */}
      {modal?.kind === 'assign' && (
        <AssignModal
          ticker={modal.ticker}
          onClose={() => setModal(null)}
          onConfirm={(payload) => {
            s.setStrategy.mutate(payload, {
              onSuccess: () => {
                toast.success(`${payload.ticker} → ${BUCKET_META[payload.bucket].name}`);
                setModal(null);
              },
              onError: (e) => toast.error((e as Error).message),
            });
          }}
        />
      )}
      {modal?.kind === 'log-gain' && (
        <LogGainModal
          ticker={modal.ticker}
          onClose={() => setModal(null)}
          onConfirm={(payload) => {
            s.logGain.mutate(payload, {
              onSuccess: () => {
                toast.success(`+${fmtK(payload.options + payload.stock)} on ${payload.ticker}`);
                setModal(null);
              },
              onError: (e) => toast.error((e as Error).message),
            });
          }}
        />
      )}
    </div>
  );
}

// ── Position card ────────────────────────────────────────────────────
function PositionCard({
  p,
  onMove,
  onUnassign,
  onLogGain,
}: {
  p: StrategyPosition;
  onMove: (to: Bucket) => void;
  onUnassign: () => void;
  onLogGain: () => void;
}) {
  const c = calcPosition(p);
  return (
    <div className="strat-card">
      <div className="row">
        <span className="ticker">{p.ticker}</span>
        <span className="px">
          {p.current_price != null ? fmtPx(p.current_price) : '—'}
        </span>
      </div>
      <div className="meta">
        <span>{p.quantity?.toLocaleString('en-US')} sh</span>
        <span className={'pnl ' + (c.sharePL >= 0 ? 'pos' : 'neg')}>
          {fmtSigned(c.sharePL)}
        </span>
        <span>premium {fmtK(c.collected)}</span>
      </div>
      <div className="meta">
        <span>
          target {fmt$(p.overlay?.put_cost ?? 0)}/
          {FREQ_LABEL[p.overlay?.put_frequency ?? 'quarterly']}
        </span>
        <span>{fmtPct(c.onTrack * 100, 0)} of pace</span>
      </div>
      <div className="strat-card-actions">
        <button onClick={onLogGain}>+ log</button>
        <BucketMoveBtn current={p.overlay!.bucket} onMove={onMove} />
        <button onClick={onUnassign}>unassign</button>
      </div>
    </div>
  );
}

function BucketMoveBtn({
  current,
  onMove,
}: {
  current: Bucket;
  onMove: (to: Bucket) => void;
}) {
  const [open, setOpen] = useState(false);
  const others = BUCKETS.filter((b) => b !== current);
  if (!open) {
    return <button onClick={() => setOpen(true)}>move ↗</button>;
  }
  return (
    <>
      {others.map((to) => (
        <button key={to} onClick={() => { onMove(to); setOpen(false); }}>
          → {BUCKET_META[to].name}
        </button>
      ))}
      <button onClick={() => setOpen(false)}>×</button>
    </>
  );
}

// ── Assign modal ─────────────────────────────────────────────────────
function AssignModal({
  ticker,
  onClose,
  onConfirm,
}: {
  ticker: string;
  onClose: () => void;
  onConfirm: (p: {
    ticker: string;
    bucket: Bucket;
    put_cost: number;
    put_frequency: PutFrequency;
  }) => void;
}) {
  const [bucket, setBucket] = useState<Bucket>('income');
  const [putCost, setPutCost] = useState('10000');
  const [freq, setFreq] = useState<PutFrequency>('quarterly');

  return (
    <div className="strat-modal-backdrop" onClick={onClose}>
      <div className="strat-modal" onClick={(e) => e.stopPropagation()}>
        <h2>Set strategy · {ticker}</h2>
        <div className="strat-field">
          <label>Bucket</label>
          <div className="strat-bucket-picker">
            {BUCKETS.map((b) => (
              <button
                key={b}
                className={(bucket === b ? 'on ' : '') + b}
                onClick={() => setBucket(b)}
              >
                {BUCKET_META[b].name}
              </button>
            ))}
          </div>
        </div>
        <div className="strat-field">
          <label>Put cost ($ per period)</label>
          <input
            type="number"
            min="0"
            step="100"
            value={putCost}
            onChange={(e) => setPutCost(e.target.value)}
          />
        </div>
        <div className="strat-field">
          <label>Frequency</label>
          <select
            value={freq}
            onChange={(e) => setFreq(e.target.value as PutFrequency)}
          >
            {PUT_FREQUENCIES.map((f) => (
              <option key={f} value={f}>
                {f}
              </option>
            ))}
          </select>
        </div>
        <div className="strat-modal-actions">
          <button className="np-btn ghost" onClick={onClose}>
            cancel
          </button>
          <button
            className="np-btn primary"
            onClick={() =>
              onConfirm({
                ticker,
                bucket,
                put_cost: Number(putCost) || 0,
                put_frequency: freq,
              })
            }
          >
            assign
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Log-gain modal ───────────────────────────────────────────────────
function LogGainModal({
  ticker,
  onClose,
  onConfirm,
}: {
  ticker: string;
  onClose: () => void;
  onConfirm: (p: {
    ticker: string;
    week_start_date: string;
    options: number;
    stock: number;
    notes?: string;
  }) => void;
}) {
  const [options, setOptions] = useState('');
  const [stock, setStock] = useState('');
  const [notes, setNotes] = useState('');
  const week = mondayOf();

  return (
    <div className="strat-modal-backdrop" onClick={onClose}>
      <div className="strat-modal" onClick={(e) => e.stopPropagation()}>
        <h2>Log gain · {ticker}</h2>
        <div className="strat-field">
          <label>Week starting (Mon)</label>
          <input value={week} disabled />
        </div>
        <div className="strat-field">
          <label>Options premium ($)</label>
          <input
            type="number"
            min="0"
            step="1"
            value={options}
            onChange={(e) => setOptions(e.target.value)}
          />
        </div>
        <div className="strat-field">
          <label>Stock / dividend ($)</label>
          <input
            type="number"
            min="0"
            step="1"
            value={stock}
            onChange={(e) => setStock(e.target.value)}
          />
        </div>
        <div className="strat-field">
          <label>Notes</label>
          <input
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="qtr dividend, expired itm, etc."
          />
        </div>
        <div className="strat-modal-actions">
          <button className="np-btn ghost" onClick={onClose}>
            cancel
          </button>
          <button
            className="np-btn primary"
            onClick={() =>
              onConfirm({
                ticker,
                week_start_date: week,
                options: Number(options) || 0,
                stock: Number(stock) || 0,
                notes: notes || undefined,
              })
            }
          >
            save
          </button>
        </div>
      </div>
    </div>
  );
}
