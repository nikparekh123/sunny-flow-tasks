import { useState } from 'react';
import { useAuth } from '@/hooks/useAuth';
import Auth from '@/pages/Auth';
import { usePositions } from './usePositions';
import { AllocationTreemap, type AllocView } from './AllocationTreemap';
import { PositionsTable } from './PositionsTable';
import { CsvUploadModal } from './CsvUploadModal';
import {
  fmtUSD2,
  fmtUSDShort,
  fmtPct,
  type PortfolioTotals,
} from './types';
import { toast } from 'sonner';

const DASHBOARD_URL = 'https://www.sunnyfi.co/dashboard';
const TREEMAP_HEIGHT = 600;
const COMPANION_MAX = 8;

export default function PositionsPage() {
  const { user, loading } = useAuth();
  const { portfolio, isLoading, replacePositions, refreshPrices } =
    usePositions();
  const [allocView, setAllocView] = useState<AllocView>('sector');
  const [showUpload, setShowUpload] = useState(false);

  if (loading) {
    return (
      <div
        className="flex min-h-screen items-center justify-center"
        style={{ backgroundColor: 'var(--owl-page)' }}
      >
        <p style={{ color: 'var(--owl-text-muted)', fontSize: 13 }}>Loading…</p>
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
    const lines = ['ticker,sector,quantity,avg_cost'];
    for (const r of portfolio.rows) {
      lines.push(`${r.ticker},${r.sector},${r.quantity},${r.avg_cost}`);
    }
    const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `positions-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div
      style={{
        minHeight: '100vh',
        background: 'var(--owl-page)',
        color: 'var(--owl-text-primary)',
        fontFamily: 'var(--owl-font-sans)',
      }}
    >
      {/* Sticky top bar */}
      <header
        style={{
          position: 'sticky',
          top: 0,
          zIndex: 30,
          background: 'var(--owl-dash)',
          padding: '18px 32px',
          borderBottom: '1px solid var(--owl-line)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 12,
        }}
      >
        <a
          href={DASHBOARD_URL}
          style={{
            display: 'inline-flex',
            alignItems: 'baseline',
            gap: 6,
            textDecoration: 'none',
          }}
          title="Back to dashboard"
        >
          <span
            style={{
              fontSize: 11,
              fontWeight: 500,
              letterSpacing: '2.8px',
              textTransform: 'uppercase',
              color: 'var(--owl-neon)',
            }}
          >
            Sunnyfi
          </span>
          <span
            style={{
              display: 'inline-block',
              width: '0.5ch',
              height: '0.9em',
              background: 'var(--owl-neon)',
              animation: 'owl-blink 1s step-end infinite',
            }}
            aria-hidden
          />
        </a>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <PriceTimestamp last={portfolio.last_updated} />
          <GhostButton onClick={handleRefresh} disabled={refreshPrices.isPending}>
            ↻ {refreshPrices.isPending ? 'Refreshing…' : 'Refresh prices'}
          </GhostButton>
          <TintedButton onClick={handleExport} disabled={portfolio.rows.length === 0}>
            ↓ Export CSV
          </TintedButton>
          <NeonButton onClick={() => setShowUpload(true)}>↑ Upload positions</NeonButton>
        </div>
      </header>

      {/* Hero */}
      <Hero portfolio={portfolio} loading={isLoading} />

      <main
        style={{
          maxWidth: 1440,
          margin: '0 auto',
          padding: '0 40px 96px',
        }}
      >
        {/* Allocation */}
        <section style={{ marginTop: 64 }}>
          <AllocationTreemap
            rows={portfolio.rows}
            view={allocView}
            onViewChange={setAllocView}
            height={TREEMAP_HEIGHT}
            maxItems={COMPANION_MAX}
          />
        </section>

        {/* Positions table */}
        <section style={{ marginTop: 64 }}>
          <PositionsTable
            rows={portfolio.rows}
            onUpload={() => setShowUpload(true)}
          />
        </section>
      </main>

      <CsvUploadModal
        open={showUpload}
        onClose={() => setShowUpload(false)}
        onConfirm={async (rows) => {
          await replacePositions.mutateAsync(rows);
          // After replace, kick off a price refresh in the background.
          refreshPrices.mutate();
        }}
      />
    </div>
  );
}

function Hero({
  portfolio,
  loading,
}: {
  portfolio: PortfolioTotals;
  loading: boolean;
}) {
  const empty = !loading && portfolio.rows.length === 0;
  const pnlColor =
    portfolio.total_pnl >= 0 ? 'var(--owl-positive)' : 'var(--owl-negative)';
  const dayColor =
    portfolio.total_day_change >= 0
      ? 'var(--owl-positive)'
      : 'var(--owl-negative)';

  return (
    <section
      style={{
        maxWidth: 1440,
        margin: '0 auto',
        padding: '64px 40px 48px',
      }}
    >
      <div
        style={{
          fontSize: 10,
          fontWeight: 500,
          letterSpacing: '1.5px',
          textTransform: 'uppercase',
          color: 'var(--owl-text-muted)',
          marginBottom: 12,
        }}
      >
        Total portfolio value
      </div>
      <div
        style={{
          fontSize: 'clamp(80px, 12vw, 180px)',
          fontWeight: 300,
          lineHeight: 0.9,
          letterSpacing: '-0.04em',
          color: 'var(--owl-text-primary)',
          fontVariantNumeric: 'tabular-nums',
        }}
      >
        {empty ? '$0' : fmtUSDShort(portfolio.total_market_value)}
      </div>
      {!empty && (
        <>
          {/* Total P&L (lifetime) */}
          <div
            style={{
              display: 'flex',
              alignItems: 'baseline',
              gap: 16,
              marginTop: 16,
              flexWrap: 'wrap',
            }}
          >
            <span
              style={{
                fontFamily: 'var(--owl-font-mono)',
                fontSize: 28,
                fontWeight: 500,
                letterSpacing: '-0.5px',
                color: pnlColor,
              }}
            >
              {portfolio.total_pnl >= 0 ? '↑ ' : '↓ '}
              {fmtUSD2(Math.abs(portfolio.total_pnl))}
            </span>
            <span
              style={{
                fontSize: 36,
                fontWeight: 600,
                letterSpacing: '-0.5px',
                color: pnlColor,
              }}
            >
              {fmtPct(portfolio.total_pnl_pct)}
            </span>
            <span
              style={{
                fontSize: 12,
                color: 'var(--owl-text-muted)',
                fontFamily: 'var(--owl-font-mono)',
                letterSpacing: '0.5px',
              }}
            >
              all-time
            </span>
          </div>

          {/* Day change */}
          {portfolio.total_day_change !== 0 && (
            <div
              style={{
                display: 'flex',
                alignItems: 'baseline',
                gap: 12,
                marginTop: 12,
              }}
            >
              <span
                style={{
                  fontFamily: 'var(--owl-font-mono)',
                  fontSize: 16,
                  color: dayColor,
                }}
              >
                {portfolio.total_day_change >= 0 ? '↑' : '↓'}{' '}
                {fmtUSD2(Math.abs(portfolio.total_day_change))}
              </span>
              <span
                style={{
                  fontSize: 12,
                  color: 'var(--owl-text-muted)',
                  fontFamily: 'var(--owl-font-mono)',
                  letterSpacing: '0.5px',
                }}
              >
                today
              </span>
            </div>
          )}
        </>
      )}
    </section>
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
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 6,
        background: 'var(--owl-tint-muted)',
        color: 'var(--owl-text-muted)',
        fontFamily: 'var(--owl-font-mono)',
        fontSize: 11,
        padding: '4px 10px',
        borderRadius: 100,
      }}
    >
      <span
        style={{
          width: 5,
          height: 5,
          borderRadius: '50%',
          background: last ? 'var(--owl-positive)' : 'var(--owl-text-muted)',
          animation: last ? 'owl-pulse 2.5s ease-in-out infinite' : 'none',
        }}
      />
      {text}
    </span>
  );
}

const buttonBase: React.CSSProperties = {
  fontFamily: 'var(--owl-font-sans)',
  fontSize: 12,
  fontWeight: 500,
  letterSpacing: '0.5px',
  padding: '8px 14px',
  border: 'none',
  cursor: 'pointer',
  whiteSpace: 'nowrap',
};

function GhostButton({
  children,
  onClick,
  disabled,
}: {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      style={{
        ...buttonBase,
        background: 'transparent',
        color: 'var(--owl-text-secondary)',
        opacity: disabled ? 0.5 : 1,
      }}
    >
      {children}
    </button>
  );
}
function TintedButton({
  children,
  onClick,
  disabled,
}: {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      style={{
        ...buttonBase,
        background: 'rgba(15,51,51,0.7)',
        color: 'var(--owl-text-secondary)',
        opacity: disabled ? 0.5 : 1,
      }}
    >
      {children}
    </button>
  );
}
function NeonButton({
  children,
  onClick,
}: {
  children: React.ReactNode;
  onClick?: () => void;
}) {
  return (
    <button
      onClick={onClick}
      style={{
        ...buttonBase,
        background: 'var(--owl-tint-neon)',
        color: 'var(--owl-neon)',
      }}
    >
      {children}
    </button>
  );
}
