import { useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Banner } from '../components/Banner';
import { AllocationStrip } from '../components/AllocationStrip';
import { UnassignedStrip } from '../components/UnassignedStrip';
import { WatchlistStrip } from '../components/WatchlistStrip';
import { BucketPanel } from '../components/BucketPanel';
import { PositionCard } from '../components/PositionCard';
import { ClosedRow } from '../components/ClosedRow';
import { weeklyPremium } from '../components/weeklyHistory';
import type { DragKind } from '../components/dragdrop';
import { BuyModal } from '../modals/BuyModal';
import { EditModal } from '../modals/EditModal';
import { SellModal } from '../modals/SellModal';
import { MoveModal, type AllocationImpact } from '../modals/MoveModal';
import { AddWatchModal } from '../modals/AddWatchModal';
import { LogGainModal } from '../modals/LogGainModal';
import { calcBucket, calcPortfolio, calcPosition, mondayOf, type Cadence } from '../calc';
import type { Bucket, StrategyPosition } from '../types';
import { useStrategy } from '../useStrategy';

const BUCKETS: Bucket[] = ['income', 'invest', 'yield'];

interface Props {
  cadence: Cadence;
}

type ModalState =
  | { kind: 'buy'; ticker: string; bucket: Bucket; currentPx: number; existing?: StrategyPosition }
  | { kind: 'edit'; position: StrategyPosition; bucket: Bucket }
  | { kind: 'sell'; position: StrategyPosition; bucket: Bucket }
  | { kind: 'move'; position: StrategyPosition; from: Bucket; to: Bucket; impact: AllocationImpact }
  | { kind: 'add-watch' }
  | { kind: 'log-gain'; position: StrategyPosition; bucket: Bucket }
  | null;

export default function StrategyDashboard({ cadence }: Props) {
  const s = useStrategy();
  const [modal, setModal] = useState<ModalState>(null);
  const [drag, setDrag] = useState<{ kind: DragKind; ticker: string; from?: Bucket } | null>(null);
  const [dropTarget, setDropTarget] = useState<Bucket | null>(null);
  const [watchDropActive, setWatchDropActive] = useState(false);

  const bucketCalcs = useMemo(
    () => ({
      income: calcBucket(s.assigned.income, 'income', cadence),
      invest: calcBucket(s.assigned.invest, 'invest', cadence),
      yield: calcBucket(s.assigned.yield, 'yield', cadence),
    }),
    [s.assigned, cadence],
  );

  const portfolio = useMemo(() => calcPortfolio(bucketCalcs), [bucketCalcs]);

  const allEntries = useMemo(() => {
    const out = [];
    for (const b of BUCKETS) for (const p of s.assigned[b]) out.push(...p.entries);
    for (const p of s.closed) out.push(...p.entries);
    return out;
  }, [s.assigned, s.closed]);

  const weeklyHistory = useMemo(() => weeklyPremium(allEntries), [allEntries]);

  // Track dragover globally to highlight drop targets, matching swm-app.jsx.
  useEffect(() => {
    if (!drag) return;
    const onOver = (e: DragEvent) => {
      const t = e.target as HTMLElement | null;
      const panel = t?.closest('.bucket-panel') as HTMLElement | null;
      const watch = t?.closest('.watch-strip') as HTMLElement | null;
      if (panel) {
        setDropTarget((panel.dataset.bucket as Bucket) ?? null);
        setWatchDropActive(false);
      } else if (watch && drag.kind === 'pos') {
        setWatchDropActive(true);
        setDropTarget(null);
      } else {
        setDropTarget(null);
        setWatchDropActive(false);
      }
    };
    window.addEventListener('dragover', onOver);
    return () => window.removeEventListener('dragover', onOver);
  }, [drag]);

  const onDragStart = (kind: DragKind, ticker: string, from?: Bucket) =>
    setDrag({ kind, ticker, from });
  const onDragEnd = () => {
    setDrag(null);
    setDropTarget(null);
    setWatchDropActive(false);
  };

  const handleDropOnBucket = (
    data: { kind: DragKind; ticker: string },
    bucket: Bucket,
  ) => {
    const { kind, ticker } = data;
    if (kind === 'watch') {
      const src = s.watching.find((w) => w.ticker === ticker);
      if (src) {
        setModal({
          kind: 'buy',
          ticker,
          bucket,
          currentPx: src.current_price ?? 0,
        });
      }
    } else if (kind === 'unassigned') {
      const src = s.unassigned.find((p) => p.ticker === ticker);
      if (src) {
        setModal({
          kind: 'buy',
          ticker,
          bucket,
          currentPx: src.current_price ?? src.avg_cost ?? 0,
          existing: src,
        });
      }
    } else if (kind === 'pos') {
      const from = BUCKETS.find((b) => s.assigned[b].some((p) => p.ticker === ticker));
      if (!from || from === bucket) return;
      const pos = s.assigned[from].find((p) => p.ticker === ticker);
      if (!pos) return;
      const impact = computeImpact(s.assigned, pos, from, bucket);
      setModal({ kind: 'move', position: pos, from, to: bucket, impact });
    }
  };

  const handleDropOnWatch = (ticker: string) => {
    const from = BUCKETS.find((b) => s.assigned[b].some((p) => p.ticker === ticker));
    if (!from) return;
    const pos = s.assigned[from].find((p) => p.ticker === ticker);
    if (pos) setModal({ kind: 'sell', position: pos, bucket: from });
  };

  const appClass =
    'swm-app' +
    (drag?.kind === 'watch' ? ' dragging-watch' : '') +
    (drag?.kind === 'pos' ? ' dragging-pos' : '');

  return (
    <div className={appClass}>
      <Banner portfolio={portfolio} cadence={cadence} weeklyHistory={weeklyHistory} />
      <AllocationStrip buckets={bucketCalcs} portfolio={portfolio} />

      <UnassignedStrip
        items={s.unassigned}
        onDragStart={onDragStart}
        onDragEnd={onDragEnd}
        onCardClick={(p) =>
          setModal({
            kind: 'buy',
            ticker: p.ticker,
            bucket: 'income',
            currentPx: p.current_price ?? p.avg_cost ?? 0,
            existing: p,
          })
        }
      />

      <WatchlistStrip
        items={s.watching}
        dropActive={watchDropActive}
        onDragStart={onDragStart}
        onDragEnd={onDragEnd}
        onDelete={(ticker) =>
          s.removeWatch.mutate(ticker, {
            onError: (e) => toast.error((e as Error).message),
          })
        }
        onAdd={() => setModal({ kind: 'add-watch' })}
        onDropFromBucket={handleDropOnWatch}
      />

      <div className="board three-col">
        {BUCKETS.map((key) => {
          const bucket = bucketCalcs[key];
          const positions = s.assigned[key];
          return (
            <BucketPanel
              key={key}
              bucket={bucket}
              variant="pipeline"
              dropActive={dropTarget === key}
              onDrop={handleDropOnBucket}
            >
              <div className="pipeline-cards">
                {positions.map((p) => {
                  const c = calcPosition(p, cadence);
                  return (
                    <PositionCard
                      key={p.ticker}
                      p={p}
                      c={c}
                      bucket={key}
                      onDragStart={onDragStart}
                      onDragEnd={onDragEnd}
                      onClick={(pos, b) => setModal({ kind: 'edit', position: pos, bucket: b })}
                      onLogGain={(pos, b) =>
                        setModal({ kind: 'log-gain', position: pos, bucket: b })
                      }
                    />
                  );
                })}
                {positions.length === 0 && (
                  <div
                    style={{
                      border: '1.5px dashed rgba(50,110,100,0.3)',
                      borderRadius: 'var(--navi-radius-md)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      color: 'var(--navi-fg3)',
                      fontSize: 11,
                      letterSpacing: 1.2,
                      textTransform: 'uppercase',
                      padding: 32,
                      flex: 1,
                    }}
                  >
                    drag a ticker here to deploy
                  </div>
                )}
              </div>
            </BucketPanel>
          );
        })}
      </div>

      {s.closed.length > 0 && <ClosedRow closed={s.closed} />}

      {/* ── Modals ── */}
      {modal?.kind === 'buy' && (
        <BuyModal
          ticker={modal.ticker}
          bucket={modal.bucket}
          currentPx={modal.currentPx}
          existingShares={modal.existing?.quantity ?? undefined}
          existingAvgCost={modal.existing?.avg_cost ?? undefined}
          deployedCost={portfolio.cost}
          onClose={() => setModal(null)}
          onConfirm={(p) => {
            s.setStrategy.mutate(
              {
                ticker: p.ticker,
                bucket: p.bucket,
                put_cost: p.putCost,
                put_frequency: p.putFrequency,
              },
              {
                onSuccess: () => {
                  // If this came from watchlist (not unassigned), drop the watch row.
                  if (!modal.existing) s.removeWatch.mutate(p.ticker);
                  toast.success(`${p.ticker} → ${p.bucket}`);
                  setModal(null);
                },
                onError: (e) => toast.error((e as Error).message),
              },
            );
          }}
        />
      )}

      {modal?.kind === 'edit' && (
        <EditModal
          position={modal.position}
          bucket={modal.bucket}
          cadence={cadence}
          onClose={() => setModal(null)}
          onSave={(updated) => {
            s.setStrategy.mutate(
              {
                ticker: updated.ticker,
                bucket: modal.bucket,
                put_cost: updated.put_cost,
                put_frequency: updated.put_frequency,
              },
              {
                onSuccess: () => {
                  toast.success(`${updated.ticker} updated`);
                  setModal(null);
                },
                onError: (e) => toast.error((e as Error).message),
              },
            );
          }}
          onSell={(p, b) => setModal({ kind: 'sell', position: p, bucket: b })}
          onMove={(p, from, to) => {
            const impact = computeImpact(s.assigned, p, from, to);
            setModal({ kind: 'move', position: p, from, to, impact });
          }}
        />
      )}

      {modal?.kind === 'sell' && (
        <SellModal
          position={modal.position}
          bucket={modal.bucket}
          onClose={() => setModal(null)}
          onConfirm={(p) => {
            // No sell_price column yet — for now, unassign + add to watchlist.
            // (Closed history is derived from overlays whose ticker is gone from positions.)
            s.unassign.mutate(p.ticker, {
              onSuccess: () => {
                s.addWatch.mutate({
                  ticker: p.ticker,
                  name: p.name ?? p.ticker,
                  sector: p.sector,
                  current_price: p.current_price ?? p.avg_cost ?? 0,
                });
                toast.success(`${p.ticker} returned to watchlist`);
                setModal(null);
              },
              onError: (e) => toast.error((e as Error).message),
            });
          }}
        />
      )}

      {modal?.kind === 'move' && (
        <MoveModal
          position={modal.position}
          from={modal.from}
          to={modal.to}
          allocationImpact={modal.impact}
          onClose={() => setModal(null)}
          onConfirm={(p, _from, to) => {
            s.moveBucket.mutate(
              { ticker: p.ticker, to },
              {
                onSuccess: () => {
                  toast.success(`${p.ticker} → ${to}`);
                  setModal(null);
                },
                onError: (e) => toast.error((e as Error).message),
              },
            );
          }}
        />
      )}

      {modal?.kind === 'add-watch' && (
        <AddWatchModal
          onClose={() => setModal(null)}
          onConfirm={(item) => {
            s.addWatch.mutate(item, {
              onSuccess: () => {
                toast.success(`${item.ticker} watching`);
                setModal(null);
              },
              onError: (e) => toast.error((e as Error).message),
            });
          }}
        />
      )}

      {modal?.kind === 'log-gain' && (
        <LogGainModal
          position={modal.position}
          bucket={modal.bucket}
          onClose={() => setModal(null)}
          onConfirm={({ ticker, kind, amount, notes }) => {
            // Additive: merge with this week's existing entry.
            const week = mondayOf();
            const existing = modal.position.entries.find((e) => e.week_start_date === week);
            const merged = {
              ticker,
              week_start_date: week,
              options: (existing?.options ?? 0) + (kind === 'options' ? amount : 0),
              stock: (existing?.stock ?? 0) + (kind === 'stock' ? amount : 0),
              notes: notes || existing?.notes || undefined,
            };
            s.logGain.mutate(merged, {
              onSuccess: () => {
                toast.success(`+${amount} ${kind} on ${ticker}`);
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

function computeImpact(
  assigned: Record<Bucket, StrategyPosition[]>,
  pos: StrategyPosition,
  from: Bucket,
  to: Bucket,
): AllocationImpact {
  const sumCost = (arr: StrategyPosition[]) =>
    arr.reduce((a, p) => a + (p.quantity ?? 0) * (p.avg_cost ?? 0), 0);
  const totalCost = BUCKETS.reduce((a, b) => a + sumCost(assigned[b]), 0) || 1;
  const fromCost = sumCost(assigned[from]);
  const toCost = sumCost(assigned[to]);
  const posCost = (pos.quantity ?? 0) * (pos.avg_cost ?? 0);
  return {
    fromBefore: (fromCost / totalCost) * 100,
    fromAfter: ((fromCost - posCost) / totalCost) * 100,
    toBefore: (toCost / totalCost) * 100,
    toAfter: ((toCost + posCost) / totalCost) * 100,
  };
}

