import { useMemo, useState, Fragment } from 'react';
import { toast } from 'sonner';
import type { Bucket, StrategyPosition } from '../types';
import { BUCKET_META, FREQ_LABEL } from '../types';
import { fmt$, fmtK } from '../calc';
import { weekStartForIdx } from '../components/weeklyHistory';
import { useStrategy } from '../useStrategy';
import { EntryEditor } from '../modals/EntryEditor';

const WEEK_COUNT = 13;
const BUCKETS: Bucket[] = ['income', 'invest', 'yield'];

type FilterKey = 'all' | Bucket;

export default function GainsLog({
  assigned,
}: {
  assigned: Record<Bucket, StrategyPosition[]>;
}) {
  const s = useStrategy();
  const [editing, setEditing] = useState<{
    ticker: string;
    bucket: Bucket;
    weekIdx: number;
  } | null>(null);
  const [filter, setFilter] = useState<FilterKey>('all');

  // Pre-compute week_start_date for each idx (0..12)
  const weekStarts = useMemo(
    () => Array.from({ length: WEEK_COUNT }, (_, i) => weekStartForIdx(i)),
    [],
  );

  const weeklyTotals = useMemo(() => {
    const totals = Array.from({ length: WEEK_COUNT }, () => ({
      options: 0,
      stock: 0,
      n: 0,
    }));
    BUCKETS.forEach((b) => {
      assigned[b].forEach((p) => {
        p.entries.forEach((e) => {
          const idx = weekStarts.indexOf(e.week_start_date);
          if (idx >= 0) {
            totals[idx].options += e.options || 0;
            totals[idx].stock += e.stock || 0;
            totals[idx].n += 1;
          }
        });
      });
    });
    return totals;
  }, [assigned, weekStarts]);

  const grandOptions = weeklyTotals.reduce((s, t) => s + t.options, 0);
  const grandStock = weeklyTotals.reduce((s, t) => s + t.stock, 0);
  const grandTotal = grandOptions + grandStock;
  const grandEntries = BUCKETS.reduce(
    (s, b) => s + assigned[b].reduce((s2, p) => s2 + p.entries.length, 0),
    0,
  );

  const visibleBuckets: Bucket[] = filter === 'all' ? BUCKETS : [filter];

  const editingPos =
    editing && assigned[editing.bucket].find((p) => p.ticker === editing.ticker);

  return (
    <div className="gains-page">
      <div className="gains-head">
        <div>
          <div className="gains-title">Gains Log</div>
          <div className="gains-sub">
            weekly journal · options premium + stock gains · click any cell to add,
            change, or delete
          </div>
        </div>
        <div className="gains-toolbar">
          <div className="gains-filter">
            <span className="label">filter</span>
            <button
              className={'pill ' + (filter === 'all' ? 'on' : '')}
              onClick={() => setFilter('all')}
            >
              All
            </button>
            {BUCKETS.map((b) => (
              <button
                key={b}
                className={`pill b-${b} ` + (filter === b ? 'on' : '')}
                onClick={() => setFilter(b)}
              >
                {BUCKET_META[b].name}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="gains-summary">
        <div className="g-summary-cell">
          <div className="k">total options · 13 wks</div>
          <div className="v neon">{fmtK(grandOptions)}</div>
        </div>
        <div className="g-summary-cell">
          <div className="k">total stock gains</div>
          <div className="v pos">+{fmtK(grandStock)}</div>
        </div>
        <div className="g-summary-cell">
          <div className="k">grand total</div>
          <div className="v">{fmt$(grandTotal)}</div>
        </div>
        <div className="g-summary-cell">
          <div className="k">entries logged</div>
          <div className="v">{grandEntries}</div>
        </div>
        <div className="g-summary-cell">
          <div className="k">this week</div>
          <div className="v neon">
            {fmt$(weeklyTotals[0].options + weeklyTotals[0].stock)}
          </div>
        </div>
      </div>

      <div className="gains-table">
        <div className="gt-row gt-head">
          <div className="gt-cell-pos">Position</div>
          {Array.from({ length: WEEK_COUNT }, (_, i) => (
            <div key={i} className={'gt-cell-week ' + (i === 0 ? 'this' : '')}>
              {i === 0 ? 'This wk' : '−' + i}
            </div>
          ))}
          <div className="gt-cell-totals">Totals</div>
        </div>

        {visibleBuckets.map((b) => (
          <Fragment key={b}>
            <div className={'gt-bucket-divider b-' + b}>
              <span className="dot" />
              <span className="name">{BUCKET_META[b].name}</span>
              <span className="count">{assigned[b].length} positions</span>
            </div>
            {assigned[b].map((p) => {
              const byWeek = new Map<string, (typeof p.entries)[number]>();
              p.entries.forEach((e) => byWeek.set(e.week_start_date, e));
              const totalOpt = p.entries.reduce((s, e) => s + (e.options || 0), 0);
              const totalStk = p.entries.reduce((s, e) => s + (e.stock || 0), 0);
              const totalAll = totalOpt + totalStk;
              return (
                <div key={p.ticker} className={'gt-row b-' + b}>
                  <div className="gt-cell-pos">
                    <div className="tk">{p.ticker}</div>
                    <div className="meta">
                      {(p.quantity ?? 0).toLocaleString('en-US')} sh · put{' '}
                      {fmtK(p.overlay?.put_cost ?? 0)} /{' '}
                      {FREQ_LABEL[p.overlay?.put_frequency ?? 'quarterly']}
                    </div>
                  </div>
                  {Array.from({ length: WEEK_COUNT }, (_, i) => {
                    const e = byWeek.get(weekStarts[i]);
                    return (
                      <button
                        key={i}
                        className={
                          'gt-cell-week ' +
                          (i === 0 ? 'this ' : '') +
                          (e ? 'filled' : 'empty')
                        }
                        onClick={() =>
                          setEditing({ ticker: p.ticker, bucket: b, weekIdx: i })
                        }
                        title={
                          e
                            ? `${fmt$((e.options || 0) + (e.stock || 0))} · click to edit`
                            : 'click to add'
                        }
                      >
                        {e ? (
                          <>
                            {e.options > 0 && (
                              <span className="opt">{fmtK(e.options)}</span>
                            )}
                            {e.stock > 0 && (
                              <span className="stk">+{fmtK(e.stock)}</span>
                            )}
                          </>
                        ) : (
                          <span className="dash">+</span>
                        )}
                      </button>
                    );
                  })}
                  <div className="gt-cell-totals">
                    <span className="opt">{fmtK(totalOpt)}</span>
                    {totalStk > 0 && <span className="stk">+{fmtK(totalStk)}</span>}
                    <span className="all">{fmt$(totalAll)}</span>
                  </div>
                </div>
              );
            })}
          </Fragment>
        ))}

        <div className="gt-row gt-foot">
          <div className="gt-cell-pos">
            <b>Weekly total</b>
            <div className="meta">across all positions</div>
          </div>
          {weeklyTotals.map((t, i) => {
            const sum = t.options + t.stock;
            return (
              <div
                key={i}
                className={'gt-cell-week ' + (i === 0 ? 'this ' : '') + 'sum'}
              >
                {sum > 0 ? (
                  <>
                    <span className="opt">{fmtK(sum)}</span>
                    <span className="stk">
                      {t.n} {t.n === 1 ? 'entry' : 'entries'}
                    </span>
                  </>
                ) : (
                  <span className="dash">—</span>
                )}
              </div>
            );
          })}
          <div className="gt-cell-totals">
            <span className="opt">{fmtK(grandOptions)}</span>
            {grandStock > 0 && <span className="stk">+{fmtK(grandStock)}</span>}
            <span className="all">{fmt$(grandTotal)}</span>
          </div>
        </div>
      </div>

      {editing && editingPos && (
        <EntryEditor
          position={editingPos}
          bucket={editing.bucket}
          weekIdx={editing.weekIdx}
          onClose={() => setEditing(null)}
          onSave={(p) => {
            s.logGain.mutate(
              { ...p, notes: p.notes ?? undefined },
              {
                onSuccess: () => {
                  toast.success(`${p.ticker} · entry saved`);
                  setEditing(null);
                },
                onError: (err) => toast.error((err as Error).message),
              },
            );
          }}
          onDelete={(p) => {
            s.deleteGain.mutate(p, {
              onSuccess: () => {
                toast.success(`${p.ticker} · entry deleted`);
                setEditing(null);
              },
              onError: (err) => toast.error((err as Error).message),
            });
          }}
        />
      )}
    </div>
  );
}
