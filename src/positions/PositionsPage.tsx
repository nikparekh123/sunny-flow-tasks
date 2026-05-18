import { useEffect, useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import Auth from '@/pages/Auth';
import { usePositions, type WatchingRow } from './usePositions';
import { AllocationTreemap, type AllocView } from './AllocationTreemap';
import { PositionsTable } from './PositionsTable';
import { CsvUploadModal } from './CsvUploadModal';
import { fmtUSD, fmtPct, fmtUSD2 } from './types';
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
    watching,
    replacePositions,
    refreshPrices,
    addWatching,
    removeWatching,
  } = usePositions();
  const [allocView, setAllocView] = useState<AllocView>('sector');
  const [showUpload, setShowUpload] = useState(false);
  const [showAddWatch, setShowAddWatch] = useState(false);

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

  const handleExport = () => {
    const lines = ['ticker,sector,quantity,avg_cost,strategy'];
    for (const r of portfolio.rows) {
      const strat = overlayByTicker.get(r.ticker) ?? '';
      lines.push(`${r.ticker},${r.sector},${r.quantity},${r.avg_cost},${strat}`);
    }
    const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `positions-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
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
          <PriceTimestamp last={portfolio.last_price_update} />
          <button
            className="np-btn ghost"
            onClick={handleRefresh}
            disabled={refreshPrices.isPending}
          >
            ↻ {refreshPrices.isPending ? 'Refreshing…' : 'Refresh prices'}
          </button>
          <button
            className="np-btn tinted"
            onClick={handleExport}
            disabled={portfolio.rows.length === 0}
          >
            ↓ Export CSV
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

        {/* Positions table */}
        <div className="np-section">
          <div className="np-section-hd">
            <div className="np-section-title">
              Positions · {portfolio.rows.length}
            </div>
            <div className="np-section-meta">sortable · click any column</div>
          </div>
          <PositionsTable
            rows={portfolio.rows}
            onUpload={() => setShowUpload(true)}
            loading={isLoading}
            overlayByTicker={overlayByTicker}
          />
        </div>

        {/* Watching */}
        <div className="np-section">
          <div className="np-section-hd">
            <div className="np-section-title">
              Watching · {watching.length}
            </div>
            <button
              className="np-btn ghost"
              onClick={() => setShowAddWatch(true)}
            >
              + add ticker
            </button>
          </div>
          {watching.length === 0 ? (
            <div className="np-empty">
              <p>Not watching anything yet. Add a ticker to track its price without buying.</p>
            </div>
          ) : (
            <div className="np-watching-grid">
              {watching.map((w: WatchingRow) => (
                <div key={w.id} className="np-watching-card">
                  <div className="row">
                    <span className="ticker">{w.ticker}</span>
                    <span className="px">
                      {w.current_price != null ? fmtUSD2(w.current_price) : '—'}
                    </span>
                  </div>
                  <div className="row">
                    <span className="name">{w.name ?? w.sector}</span>
                  </div>
                  <button
                    className="remove"
                    onClick={() => {
                      removeWatching.mutate(w.ticker, {
                        onSuccess: () => toast.success(`${w.ticker} removed`),
                        onError: (e) => toast.error((e as Error).message),
                      });
                    }}
                  >
                    × remove
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {showAddWatch && (
        <AddWatchModal
          onClose={() => setShowAddWatch(false)}
          onConfirm={(payload) => {
            addWatching.mutate(payload, {
              onSuccess: () => {
                toast.success(`Watching ${payload.ticker}`);
                setShowAddWatch(false);
              },
              onError: (e) => toast.error((e as Error).message),
            });
          }}
        />
      )}

      <CsvUploadModal
        open={showUpload}
        onClose={() => setShowUpload(false)}
        onConfirm={async (rows) => {
          await replacePositions.mutateAsync(rows);
          refreshPrices.mutate();
        }}
      />
    </div>
  );
}

function AddWatchModal({
  onClose,
  onConfirm,
}: {
  onClose: () => void;
  onConfirm: (p: { ticker: string; name?: string; sector?: string; current_price?: number }) => void;
}) {
  const [ticker, setTicker] = useState('');
  const [name, setName] = useState('');
  const [sector, setSector] = useState('Other');
  const [price, setPrice] = useState('');

  return (
    <div className="strat-modal-backdrop" onClick={onClose}>
      <div className="strat-modal" onClick={(e) => e.stopPropagation()}>
        <h2>Add to watching</h2>
        <div className="strat-field">
          <label>Ticker</label>
          <input
            value={ticker}
            onChange={(e) => setTicker(e.target.value.toUpperCase())}
            placeholder="HOOD"
          />
        </div>
        <div className="strat-field">
          <label>Name</label>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Robinhood" />
        </div>
        <div className="strat-field">
          <label>Sector</label>
          <input value={sector} onChange={(e) => setSector(e.target.value)} />
        </div>
        <div className="strat-field">
          <label>Current price ($)</label>
          <input
            type="number"
            value={price}
            onChange={(e) => setPrice(e.target.value)}
            placeholder="94.20"
          />
        </div>
        <div className="strat-modal-actions">
          <button className="np-btn ghost" onClick={onClose}>cancel</button>
          <button
            className="np-btn neon"
            disabled={!ticker.trim()}
            onClick={() =>
              onConfirm({
                ticker: ticker.trim(),
                name: name.trim() || undefined,
                sector: sector || 'Other',
                current_price: price ? Number(price) : undefined,
              })
            }
          >
            watch
          </button>
        </div>
      </div>
    </div>
  );
}

function PriceTimestamp({ last }: { last: string | null }) {
  const text = last
    ? `prices · ${new Date(last).toLocaleString('en-US', {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      })}`
    : 'prices · never refreshed';
  return (
    <span className="np-pill">
      <span className="dot" />
      {text}
    </span>
  );
}
