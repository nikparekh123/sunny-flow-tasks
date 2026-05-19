import { useEffect, useMemo, useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import Auth from '@/pages/Auth';
import { usePositions } from './usePositions';
import { AllocationTreemap, type AllocView } from './AllocationTreemap';
import { PositionsTable } from './PositionsTable';
import { CsvUploadModal } from './CsvUploadModal';
import { QuickAddGainModal } from './QuickAddGainModal';
import { PositionDetailModal } from './PositionDetailModal';
import { GainsLogMatrix } from './GainsLogMatrix';
import { RealizedSummary } from './RealizedSummary';
import { fmtUSD, fmtPct } from './types';
import { toast } from 'sonner';
import './positions.css';

const DASHBOARD_URL = 'https://www.sunnyfi.co/dashboard';
const TREEMAP_HEIGHT = 600;
const COMPANION_MAX = 10;

export default function PositionsPage() {
  const { user, loading } = useAuth();
  const {
    portfolio,
    isLoading,
    overlayByTicker,
    gainsByTicker,
    putProtectionByTicker,
    replacePositions,
    refreshPrices,
    addGain,
    deleteGain,
    setPutProtection,
    clearPutProtection,
    setPositionStatus,
  } = usePositions();
  const [allocView, setAllocView] = useState<AllocView>('sector');
  const [posView, setPosView] = useState<'table' | 'gains'>('table');
  const [showUpload, setShowUpload] = useState(false);
  const [showQuickAdd, setShowQuickAdd] = useState(false);
  const [detailTicker, setDetailTicker] = useState<string | null>(null);

  // ?ticker=… deep-link: scroll the matching row into view + flash.
  useEffect(() => {
    if (isLoading) return;
    const params = new URLSearchParams(window.location.search);
    const t = params.get('ticker');
    if (!t) return;
    // Defer until the table has rendered the row.
    const id = window.setTimeout(() => {
      const row = document.querySelector<HTMLElement>(
        `tr[data-ticker="${t.toUpperCase()}"]`,
      );
      if (!row) return;
      // Smooth-scroll via top calculation rather than scrollIntoView
      // (the handoff explicitly bans scrollIntoView).
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
          ? `Updated ${result.updated}/${result.total} (${missing} skipped)`
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
          <button
            className="np-btn add-gain"
            onClick={() => setShowQuickAdd(true)}
            title="Log a gain"
          >
            + Log gain
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

        {/* Positions table / Gains log */}
        <div className="np-section">
          <div className="np-section-hd">
            <div className="np-section-title">
              Positions · {portfolio.rows.length}
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <div className="np-view-toggle">
                <button
                  className={posView === 'table' ? 'on' : ''}
                  onClick={() => setPosView('table')}
                >
                  Table
                </button>
                <button
                  className={posView === 'gains' ? 'on' : ''}
                  onClick={() => setPosView('gains')}
                >
                  Gains log
                </button>
              </div>
              <div className="np-section-meta">
                {posView === 'table' ? 'sortable · click any column' : 'click any cell to log'}
              </div>
            </div>
          </div>
          {portfolio.rows.length > 0 && (
            <RealizedSummary
              portfolio={portfolio}
              overlayByTicker={overlayByTicker}
            />
          )}
          {posView === 'table' ? (
            <PositionsTable
              rows={portfolio.rows}
              onUpload={() => setShowUpload(true)}
              loading={isLoading}
              overlayByTicker={overlayByTicker}
              onTickerClick={(t) => setDetailTicker(t)}
            />
          ) : (
            <GainsLogMatrix
              rows={portfolio.rows}
              gainsByTicker={gainsByTicker}
              onCellClick={(t) => setDetailTicker(t)}
              onTickerClick={(t) => setDetailTicker(t)}
            />
          )}
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

      {showQuickAdd && (
        <QuickAddGainModal
          positions={portfolio.rows}
          onClose={() => setShowQuickAdd(false)}
          onSave={(p) => {
            addGain.mutate(p, {
              onSuccess: () => {
                toast.success(`+${p.amount} ${p.source} · ${p.ticker}`);
                setShowQuickAdd(false);
              },
              onError: (e) => toast.error((e as Error).message),
            });
          }}
        />
      )}

      {detailTicker && <DetailModalWrapper
        ticker={detailTicker}
        rows={portfolio.rows}
        gainsByTicker={gainsByTicker}
        putProtectionByTicker={putProtectionByTicker}
        overlayByTicker={overlayByTicker}
        onClose={() => setDetailTicker(null)}
        onAddGain={(p) => addGain.mutate(p, { onError: (e) => toast.error((e as Error).message) })}
        onDeleteGain={(id) => deleteGain.mutate(id, { onError: (e) => toast.error((e as Error).message) })}
        onSetPutProtection={(p) =>
          setPutProtection.mutate(p, {
            onSuccess: () => toast.success(`Put protection · ${p.ticker}`),
            onError: (e) => toast.error((e as Error).message),
          })
        }
        onClearPutProtection={(ticker) =>
          clearPutProtection.mutate(ticker, {
            onSuccess: () => toast.success(`Cleared · ${ticker}`),
            onError: (e) => toast.error((e as Error).message),
          })
        }
        onSetStatus={(p) =>
          setPositionStatus.mutate(p, {
            onSuccess: () => toast.success(`${p.ticker} marked ${p.status}`),
            onError: (e) => toast.error((e as Error).message),
          })
        }
      />}
    </div>
  );
}

// Small wrapper that resolves the ticker → row + entries + protection before
// rendering the detail modal, so the parent stays uncluttered.
function DetailModalWrapper(props: {
  ticker: string;
  rows: ReturnType<typeof usePositions>['portfolio']['rows'];
  gainsByTicker: ReturnType<typeof usePositions>['gainsByTicker'];
  putProtectionByTicker: ReturnType<typeof usePositions>['putProtectionByTicker'];
  overlayByTicker: ReturnType<typeof usePositions>['overlayByTicker'];
  onClose: () => void;
  onAddGain: Parameters<typeof PositionDetailModal>[0]['onAddGain'];
  onDeleteGain: Parameters<typeof PositionDetailModal>[0]['onDeleteGain'];
  onSetPutProtection: Parameters<typeof PositionDetailModal>[0]['onSetPutProtection'];
  onClearPutProtection: Parameters<typeof PositionDetailModal>[0]['onClearPutProtection'];
  onSetStatus: Parameters<typeof PositionDetailModal>[0]['onSetStatus'];
}) {
  const pos = useMemo(
    () => props.rows.find((r) => r.ticker === props.ticker) ?? null,
    [props.rows, props.ticker],
  );
  if (!pos) return null;
  const entries = props.gainsByTicker.get(props.ticker) ?? [];
  const pp = props.putProtectionByTicker.get(props.ticker);
  const bucket = props.overlayByTicker.get(props.ticker);
  return (
    <PositionDetailModal
      position={pos}
      entries={entries}
      putProtection={pp}
      bucket={bucket}
      onClose={props.onClose}
      onAddGain={props.onAddGain}
      onDeleteGain={props.onDeleteGain}
      onSetPutProtection={props.onSetPutProtection}
      onClearPutProtection={props.onClearPutProtection}
      onSetStatus={props.onSetStatus}
    />
  );
}

