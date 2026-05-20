import { useEffect, useMemo, useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import Auth from '@/pages/Auth';
import { usePositions } from './usePositions';
import { AllocationTreemap, type AllocView } from './AllocationTreemap';
import { PositionsTable } from './PositionsTable';
import { CsvUploadModal } from './CsvUploadModal';
import { PositionDetailModal } from './PositionDetailModal';
import { PositionInsightModal } from './PositionInsightModal';
import { RealizedSummary } from './RealizedSummary';
import { fmtUSD, fmtPct } from './types';
import { toast } from 'sonner';
import './positions.css';

const DASHBOARD_URL = 'https://www.sunnyfi.co/dashboard';
const TREEMAP_HEIGHT = 600;
const COMPANION_MAX = 10;

const LS_ALLOC = 'np:allocView';
function readLS<T extends string>(key: string, allowed: readonly T[], fallback: T): T {
  if (typeof window === 'undefined') return fallback;
  const v = window.localStorage.getItem(key);
  return v && (allowed as readonly string[]).includes(v) ? (v as T) : fallback;
}

export default function PositionsPage() {
  const { user, loading } = useAuth();
  const {
    portfolio,
    isLoading,
    overlayByTicker,
    tradesByTicker,
    liveByTicker,
    realizedByTicker,
    replacePositions,
    refreshPrices,
    addTrade,
    setPositionStatus,
    setEarningsDate,
    deletePosition,
  } = usePositions();
  const [allocView, setAllocView] = useState<AllocView>(() =>
    readLS<AllocView>(LS_ALLOC, ['sector', 'stock', 'strategy', 'pnl'] as const, 'sector'),
  );
  useEffect(() => {
    try { window.localStorage.setItem(LS_ALLOC, allocView); } catch { /* private mode */ }
  }, [allocView]);
  const [showUpload, setShowUpload] = useState(false);
  // Two-layer modal: ticker click opens insight (read), insight's action
  // buttons promote to the write modal in either 'open' or 'close' tab.
  const [insightTicker, setInsightTicker] = useState<string | null>(null);
  const [detail, setDetail] = useState<{ ticker: string; tab: 'open' | 'close' } | null>(null);

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

  const isDown = portfolio.total_pnl < 0;

  return (
    <div className="np-app">
      {/* Top bar */}
      <header className="np-top">
        <div className="np-brand-row">
          <a className="np-brand" href={DASHBOARD_URL} title="Back to dashboard">
            Sunnyfi<span className="cursor" />
          </a>
          <span className="np-crumb-sep">/</span>
          <span className="np-crumb">POSITIONS</span>
        </div>
        <div className="np-actions">
          <button
            className="np-btn ghost"
            onClick={handleRefresh}
            disabled={refreshPrices.isPending}
          >
            ↻ {refreshPrices.isPending ? 'Refreshing…' : 'Refresh'}
          </button>
          <button className="np-btn neon" onClick={() => setShowUpload(true)}>
            ↑ Upload positions
          </button>
        </div>
      </header>

      <div className="np-stage">
        {/* Hero */}
        <div className="np-hero">
          <div className="np-hero-label">Total portfolio value</div>
          <div className="np-hero-value">
            {portfolio.rows.length === 0
              ? '$0'
              : fmtUSD(portfolio.total_market_value)}
          </div>
          {portfolio.rows.length > 0 && (
            <div className={'np-hero-pl' + (isDown ? '' : ' up')}>
              <div>
                <span className="np-hero-pl-amt">
                  {fmtUSD(portfolio.total_pnl)}
                </span>
                <span className="np-hero-pl-label" style={{ marginLeft: 10 }}>
                  unrealized
                </span>
              </div>
              <span className="np-hero-pl-pct">
                {fmtPct(portfolio.total_pnl_pct)}
              </span>
            </div>
          )}
        </div>

        {/* Allocation */}
        <div className="np-section">
          <div className="np-section-hd">
            <div className="np-section-title">Allocation</div>
            <div className="np-toggle">
              <button
                className={allocView === 'stock' ? 'on' : ''}
                onClick={() => setAllocView('stock')}
              >
                By stock
              </button>
              <button
                className={allocView === 'sector' ? 'on' : ''}
                onClick={() => setAllocView('sector')}
              >
                By sector
              </button>
              <button
                className={allocView === 'strategy' ? 'on' : ''}
                onClick={() => setAllocView('strategy')}
              >
                By strategy
              </button>
              <button
                className={allocView === 'pnl' ? 'on' : ''}
                onClick={() => setAllocView('pnl')}
              >
                P&amp;L by position
              </button>
            </div>
          </div>
          <AllocationTreemap
            rows={portfolio.rows}
            view={allocView}
            height={TREEMAP_HEIGHT}
            maxItems={COMPANION_MAX}
            overlayByTicker={overlayByTicker}
          />
        </div>

        {/* Positions */}
        <div className="np-section">
          {portfolio.rows.length > 0 && (
            <RealizedSummary
              portfolio={portfolio}
              overlayByTicker={overlayByTicker}
              realizedByTicker={realizedByTicker}
              liveByTicker={liveByTicker}
            />
          )}
          <div className="np-section-hd">
            <div className="np-section-title">Positions · {portfolio.rows.length}</div>
          </div>
          <PositionsTable
            rows={portfolio.rows}
            onUpload={() => setShowUpload(true)}
            loading={isLoading}
            overlayByTicker={overlayByTicker}
            onTickerClick={(t) => setInsightTicker(t)}
          />
        </div>
      </div>

      <CsvUploadModal
        open={showUpload}
        onClose={() => setShowUpload(false)}
        onConfirm={async (rows) => {
          await replacePositions.mutateAsync(rows);
          refreshPrices.mutate();
        }}
      />

      {insightTicker && (() => {
        const pos = portfolio.rows.find((r) => r.ticker === insightTicker);
        if (!pos) return null;
        const trades = tradesByTicker.get(insightTicker) ?? [];
        const live = liveByTicker.get(insightTicker) ?? [];
        const realized = realizedByTicker.get(insightTicker) ?? 0;
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
            onClose={() => setDetail(null)}
            onAddTrade={(p) =>
              addTrade.mutate(p, {
                onSuccess: () => toast.success(`${p.action === 'open' ? 'Opened' : 'Closed'} · ${p.ticker}`),
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
