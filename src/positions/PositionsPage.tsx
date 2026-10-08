import { useEffect, useMemo, useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import Auth from '@/pages/Auth';
import { usePositions } from './usePositions';
import { CsvUploadModal } from './CsvUploadModal';
import { PositionDetailModal } from './PositionDetailModal';
import { PositionInsightModal } from './PositionInsightModal';
import { PositionsV2Body } from './PositionsV2Body';
import { useLiveLegs } from './metrics/useLiveLegs';
import { useMasterQuotes } from './metrics/useEnrichedRows';
import { toast } from 'sonner';
import './positions.css';

const DASHBOARD_URL = 'https://www.sunnyfi.co/dashboard';

export default function PositionsPage() {
  const { user, loading } = useAuth();
  const {
    portfolio: rawPortfolio,
    isLoading,
    overlayByTicker,
    tradesByTicker,
    liveByTicker,
    realizedByTicker,
    signalsByTicker,
    shareSellsByTicker,
    replacePositions,
    refreshPrices,
    addTrade,
    updateTrade,
    buyShares,
    sellShares,
    resolveExpired,
    closePriceAt,
    dailyCloses,
    setPositionStatus,
    setEarningsDate,
    deletePosition,
  } = usePositions();
  // HC-3: decorate the legacy portfolio rows with master spot from
  // ticker_quotes so every downstream consumer (ledger, modals,
  // insights strip, scenario calc) reads the same price as /portfolio
  // and /dashboard. The override happens at the source — no JSX
  // changes anywhere downstream.
  const { decorate } = useMasterQuotes();
  const portfolio = useMemo(
    () => ({ ...rawPortfolio, rows: decorate(rawPortfolio.rows) }),
    [rawPortfolio, decorate],
  );
  const [showUpload, setShowUpload] = useState(false);
  // Two-layer modal: ticker click opens insight (read), insight's action
  // buttons promote to the write modal in either 'open' or 'close' tab.
  const [insightTicker, setInsightTicker] = useState<string | null>(null);
  const [detail, setDetail] = useState<
    | {
        ticker: string;
        tab: 'open' | 'close' | 'edit' | 'shares' | 'resolve';
        // For 'resolve' tab: the expired option being resolved.
        resolveTrade?: import('./types').OptionTrade;
      }
    | null
  >(null);

  // ?ticker=… deep-link
  useEffect(() => {
    if (isLoading) return;
    const params = new URLSearchParams(window.location.search);
    const t = params.get('ticker');
    if (!t) return;
    const id = window.setTimeout(() => {
      const row = document.querySelector<HTMLElement>(
        `tr[data-ticker="${t.toUpperCase()}"]`,
      );
      if (!row) return;
      const rect = row.getBoundingClientRect();
      const target = window.scrollY + rect.top - 100;
      window.scrollTo({ top: target, behavior: 'smooth' });
      row.classList.add('highlight');
      window.setTimeout(() => row.classList.remove('highlight'), 1500);
    }, 200);
    return () => window.clearTimeout(id);
  }, [isLoading, portfolio.rows.length]);

  if (loading) {
    return (
      <div className="np-app" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <p style={{ color: 'var(--navi-fg3)', fontSize: 13 }}>Loading…</p>
      </div>
    );
  }
  if (!user) return <Auth />;

  const handleRefresh = async () => {
    try {
      const result = await refreshPrices.mutateAsync();
      const missing = result?.missing?.length ?? 0;
      toast.success(
        missing > 0
          ? `Updated ${result.updated}/${result.total} prices (${missing} skipped)`
          : `Updated ${result.updated}/${result.total} prices`,
      );
    } catch (e) {
      toast.error(`Refresh failed: ${(e as Error).message}`);
    }
  };

  // SOT: per-ticker live-leg count via useLiveLegs (A11) — used by
  // the V2 body to decide whether the detail modal opens
  // on the Close tab vs the Open tab.
  const { byTicker: liveCountByTicker } = useLiveLegs();

  return (
    <div className="np-app">
      {/* The modal stack stays shared inside .np-app; the V2 body renders
          its own .dash shell nested within. */}
      <PositionsV2Body
        portfolio={portfolio}
        liveByTicker={liveByTicker}
        overlayByTicker={overlayByTicker}
        signalsByTicker={signalsByTicker}
        realizedByTicker={realizedByTicker}
        tradesByTicker={tradesByTicker}
        shareSellsByTicker={shareSellsByTicker}
        dailyCloses={dailyCloses}
        onUpload={() => setShowUpload(true)}
        onRefresh={handleRefresh}
        refreshing={refreshPrices.isPending}
        onTickerClick={(t) => setInsightTicker(t)}
        onSharesCellClick={(t) => setDetail({ ticker: t, tab: 'shares' })}
        onOpenSlotClick={(t, mode) => {
          const hasLive = (liveCountByTicker.get(t) ?? 0) > 0;
          // An explicit "+" add-slot always opens the Open tab; clicking an
          // existing live leg defaults to Close (edit/close that leg).
          setDetail({ ticker: t, tab: mode ?? (hasLive ? 'close' : 'open') });
        }}
        onResolveCellClick={(t, open) => setDetail({ ticker: t, tab: 'resolve', resolveTrade: open })}
        onDashboard={() => { window.location.href = DASHBOARD_URL; }}
        onStrategy={() => { window.location.href = 'https://www.sunnyfi.co/new-strategy'; }}
      />

      <CsvUploadModal
        open={showUpload}
        onClose={() => setShowUpload(false)}
        onConfirm={async (rows) => {
          const res = await replacePositions.mutateAsync(rows);
          if (res.inserted > 0 && res.skipped === 0) {
            toast.success(`Added ${res.inserted} new ticker${res.inserted === 1 ? '' : 's'}`);
          } else if (res.inserted > 0 && res.skipped > 0) {
            toast.success(
              `Added ${res.inserted} new · skipped ${res.skipped} existing (use Shares tab to change qty)`,
            );
          } else if (res.skipped > 0) {
            toast.info(
              `All ${res.skipped} ticker${res.skipped === 1 ? '' : 's'} already existed — CSV is for new tickers only`,
            );
          }
          refreshPrices.mutate();
        }}
      />

      {insightTicker && (() => {
        const pos = portfolio.rows.find((r) => r.ticker === insightTicker);
        if (!pos) return null;
        const trades = tradesByTicker.get(insightTicker) ?? [];
        const live = liveByTicker.get(insightTicker) ?? [];
        // Realized = closed-option pairs + realized stock P&L (sells/assignments),
        // so the modal's "Realized P&L" matches the full per-ticker realized.
        const realized = (realizedByTicker.get(insightTicker) ?? 0) + (pos.realized_stock_pl ?? 0);
        return (
          <PositionInsightModal
            position={pos}
            trades={trades}
            liveOpens={live}
            realizedTotal={realized}
            bucket={overlayByTicker.get(insightTicker)}
            onClose={() => setInsightTicker(null)}
            onSetStatus={(p) =>
              setPositionStatus.mutate(p, {
                onSuccess: () => toast.success(`${p.ticker} marked ${p.status}`),
                onError: (e) => toast.error((e as Error).message),
              })
            }
            onSetEarningsDate={(p) =>
              setEarningsDate.mutate(p, {
                onSuccess: () =>
                  toast.success(
                    p.earnings_date
                      ? `Earnings ${p.earnings_date} · ${p.ticker}`
                      : `Cleared earnings · ${p.ticker}`,
                  ),
                onError: (e) => toast.error((e as Error).message),
              })
            }
            onOpenTrade={() => {
              setDetail({ ticker: insightTicker, tab: 'open' });
              setInsightTicker(null);
            }}
            onCloseTrade={() => {
              setDetail({ ticker: insightTicker, tab: 'close' });
              setInsightTicker(null);
            }}
            onDeletePosition={(t) =>
              deletePosition.mutate(t, {
                onSuccess: () => {
                  toast.success(`Deleted ${t} and all linked trades`);
                  setInsightTicker(null);
                },
                onError: (e) => toast.error((e as Error).message),
              })
            }
          />
        );
      })()}

      {detail && (() => {
        const pos = portfolio.rows.find((r) => r.ticker === detail.ticker);
        if (!pos) return null;
        const live = liveByTicker.get(detail.ticker) ?? [];
        return (
          <PositionDetailModal
            position={pos}
            liveOpens={live}
            bucket={overlayByTicker.get(detail.ticker)}
            initialTab={detail.tab}
            resolveTrade={detail.resolveTrade}
            resolveExpiryClose={
              detail.resolveTrade
                ? closePriceAt(detail.resolveTrade.ticker, detail.resolveTrade.expiry)
                : null
            }
            onClose={() => setDetail(null)}
            onAddTrade={(p) =>
              addTrade.mutate(p, {
                onSuccess: () => toast.success(`${p.action === 'open' ? 'Opened' : 'Closed'} · ${p.ticker}`),
                onError: (e) => toast.error((e as Error).message),
              })
            }
            onUpdateTrade={(p) =>
              updateTrade.mutate(p, {
                onSuccess: () => toast.success(`Updated · ${detail.ticker}`),
                onError: (e) => toast.error((e as Error).message),
              })
            }
            onBuyShares={(p) =>
              buyShares.mutate(p, {
                onSuccess: (res) =>
                  toast.success(
                    `Bought ${p.quantity} ${p.ticker} · new avg \$${res.newAvg.toFixed(2)}`,
                  ),
                onError: (e) => toast.error((e as Error).message),
              })
            }
            onSellShares={(p) =>
              sellShares.mutate(p, {
                onSuccess: (res) => toast.success(`Sold ${p.quantity} ${p.ticker} · realized ${res.realized >= 0 ? '+' : '−'}\$${Math.abs(res.realized).toFixed(0)}`),
                onError: (e) => toast.error((e as Error).message),
              })
            }
            onResolveExpired={(p) =>
              resolveExpired.mutate(p, {
                onSuccess: (res) => {
                  const msg =
                    res.kind === 'expired' ? 'Marked expired worthless'
                      : res.kind === 'rolled' ? 'Rolled'
                      : res.kind === 'assigned' ? `Assigned · realized ${res.sharePnl >= 0 ? '+' : '−'}\$${Math.abs(res.sharePnl).toFixed(0)}`
                      : 'Resolved';
                  toast.success(`${msg} · ${detail.ticker}`);
                },
                onError: (e) => toast.error((e as Error).message),
              })
            }
            onSetStatus={(p) =>
              setPositionStatus.mutate(p, {
                onSuccess: () => toast.success(`${p.ticker} marked ${p.status}`),
                onError: (e) => toast.error((e as Error).message),
              })
            }
          />
        );
      })()}
    </div>
  );
}
