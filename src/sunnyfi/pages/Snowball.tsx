/**
 * Snowball — DCF/valuation dashboard.
 *
 * Reads `public.snowball` (populated nightly by the refresh-snowball edge
 * function from Polygon). Static analysis fields (intrinsic, growth, tier)
 * come from the CSV import; price + 52w high/low come from Polygon.
 */
import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  fetchStocks,
  setWatch,
  sortStocks,
  updateAssumptions,
  refreshSnowball,
  syncFundamentals,
  applyDefaults,
  loadDefaults,
  saveDefaults,
  addStock,
  applySectorMultiples,
  updateMultiples,
  type SnowballDefaults,
  type NewStockInput,
  dcfIntrinsic,
  fmtMcap,
  fmtPrice,
  fmtPrice2,
  fmtPct,
  fmtUps,
  TIER_LABEL,
  SORTS,
  type ComputedStock,
  type SortKey,
} from "@/sunnyfi/lib/snowball";
import "@/sunnyfi/research.css"; // np-top + np-btn + np-pill primitives
import "@/sunnyfi/snowball.css";

const DASHBOARD_URL = "https://www.sunnyfi.co/dashboard";
const PAGE_SIZE = 50;

export default function Snowball() {
  const qc = useQueryClient();
  const stocksQ = useQuery({
    queryKey: ["snowball", "stocks"],
    queryFn: fetchStocks,
  });
  const all = stocksQ.data ?? [];

  const sectors = useMemo(() => {
    const s = new Set<string>();
    all.forEach((x) => x.sector && s.add(x.sector));
    return Array.from(s).sort();
  }, [all]);

  const [filter, setFilter] = useState<string>("All");
  const [sort, setSort] = useState<SortKey>("Most undervalued");
  const [watchOnly, setWatchOnly] = useState(false);
  const [hideOvervalued, setHideOvervalued] = useState(false);
  const [search, setSearch] = useState("");
  const [opened, setOpened] = useState<ComputedStock | null>(null);
  const [shown, setShown] = useState(PAGE_SIZE);
  const [refreshing, setRefreshing] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [showDefaults, setShowDefaults] = useState(false);
  const [showAdd, setShowAdd] = useState(false);

  const handleRefresh = async () => {
    setRefreshing(true);
    try {
      const r = await refreshSnowball();
      stocksQ.refetch();
      const msg = r.missing_count > 0
        ? `Updated ${r.updated}/${r.total} (${r.missing_count} skipped)`
        : `Updated ${r.updated}/${r.total} prices`;
      toast.success(msg);
    } catch (e) {
      toast.error(`Refresh failed: ${(e as Error).message}`);
    } finally {
      setRefreshing(false);
    }
  };

  const handleSync = async () => {
    if (!confirm(
      "Pull fundamentals (CFO, investing, shares, name) for all 524 tickers from Polygon?\n\n" +
      "Takes ~3-5 minutes. Recomputes intrinsic value from your saved assumptions × API fundamentals."
    )) return;
    setSyncing(true);
    try {
      const r = await syncFundamentals();
      stocksQ.refetch();
      const msg = r.missing_count > 0
        ? `Synced ${r.updated}/${r.total} (${r.missing_count} skipped)`
        : `Synced ${r.updated}/${r.total} fundamentals`;
      toast.success(msg);
    } catch (e) {
      toast.error(`Sync failed: ${(e as Error).message}`);
    } finally {
      setSyncing(false);
    }
  };

  const filtered = useMemo(() => {
    let r = all;
    if (filter !== "All") r = r.filter((s) => s.sector === filter);
    if (watchOnly) r = r.filter((s) => s.watchlist);
    if (hideOvervalued) {
      r = r.filter((s) => !s.intrinsic_invalid && s.upside > 0);
    }
    const q = search.trim().toLowerCase();
    if (q) {
      r = r.filter(
        (s) =>
          s.ticker.toLowerCase().includes(q) ||
          s.name.toLowerCase().includes(q),
      );
    }
    return sortStocks(r, sort);
  }, [all, filter, sort, watchOnly, hideOvervalued, search]);

  // Reset paging when the visible list size changes meaningfully.
  const filteredLen = filtered.length;
  useMemo(() => {
    setShown(PAGE_SIZE);
  }, [filteredLen, filter, sort, watchOnly]);

  const visible = filtered.slice(0, shown);
  const watchlistItems = useMemo(() => all.filter((s) => s.watchlist), [all]);
  const lastUpdate = useMemo(() => {
    const ts = all
      .map((s) => s.last_quote_at)
      .filter(Boolean)
      .sort();
    return ts[ts.length - 1] ?? null;
  }, [all]);

  const toggleWatch = async (ticker: string, current: boolean) => {
    // Optimistic update.
    qc.setQueryData<ComputedStock[]>(["snowball", "stocks"], (prev) =>
      prev?.map((s) => (s.ticker === ticker ? { ...s, watchlist: !current } : s)),
    );
    try {
      await setWatch(ticker, !current);
    } catch (e) {
      toast.error(`Couldn't update watchlist: ${(e as Error).message}`);
      stocksQ.refetch();
    }
  };

  return (
    <div className="sb-app">
      <header className="np-top">
        <div className="np-brand-row">
          <a className="np-brand" href={DASHBOARD_URL} title="Back to dashboard">
            Sunnyfi<span className="cursor" />
          </a>
          <span className="np-crumb-sep">/</span>
          <span className="np-crumb">SNOWBALL</span>
        </div>
        <div className="np-actions">
          <span className="np-pill">
            <span className="dot" />
            {lastUpdate
              ? `updated ${new Date(lastUpdate).toLocaleString("en-US", {
                  month: "short",
                  day: "numeric",
                  hour: "numeric",
                  minute: "2-digit",
                })}`
              : "no quote yet"}
          </span>
          <button
            className="np-btn ghost"
            onClick={handleRefresh}
            disabled={refreshing || syncing}
            title="Pull live prices + 52-week ranges from Polygon (fast)"
          >
            ↻ {refreshing ? "Refreshing…" : "Refresh prices"}
          </button>
          <button
            className="np-btn tinted"
            onClick={handleSync}
            disabled={refreshing || syncing}
            title="Pull fundamentals (CFO, shares, names) — slow, run weekly"
          >
            ⟳ {syncing ? "Syncing…" : "Sync fundamentals"}
          </button>
          <button className="np-btn neon" onClick={() => setShowAdd(true)}>
            + Add stock
          </button>
        </div>
      </header>

      <main className="sb-stage">
        <div className="sb-controls">
          <div className="sb-toolbar">
            <div className="sb-tb-row">
              <input
                type="text"
                className="sb-search"
                placeholder="⌕ Search ticker or name…"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
              <div className="sb-tb-group">
                <label className="sb-select">
                  <span className="sb-select-lbl">Sector</span>
                  <select
                    value={filter}
                    onChange={(e) => setFilter(e.target.value)}
                  >
                    {["All", ...sectors].map((s) => (
                      <option key={s} value={s}>
                        {s}
                      </option>
                    ))}
                  </select>
                  <span className="sb-select-caret">▾</span>
                </label>
                <label className="sb-select">
                  <span className="sb-select-lbl">Sort</span>
                  <select
                    value={sort}
                    onChange={(e) => setSort(e.target.value as SortKey)}
                  >
                    {SORTS.map((s) => (
                      <option key={s} value={s}>
                        {s}
                      </option>
                    ))}
                  </select>
                  <span className="sb-select-caret">▾</span>
                </label>
              </div>
              <div className="sb-tb-group sb-tb-right">
                <button
                  className="sb-toggle"
                  onClick={() => setShowDefaults(true)}
                  title="Set the universe-wide growth/discount/terminal assumptions"
                >
                  ⚙ Defaults
                </button>
                <button
                  className="sb-toggle"
                  onClick={async () => {
                    if (!confirm(
                      "Apply sector-default P/E and EV/EBITDA multiples to every stock?\n\n" +
                      "Per-stock customizations will be overwritten. Edit the snowball_sector_defaults table to tune the bands."
                    )) return;
                    try {
                      const n = await applySectorMultiples();
                      stocksQ.refetch();
                      toast.success(`Sector multiples applied to ${n} stocks.`);
                    } catch (e) {
                      toast.error((e as Error).message);
                    }
                  }}
                  title="Apply industry-median P/E and EV/EBITDA multiples by sector"
                >
                  ⛁ Sector multiples
                </button>
                <button
                  className={"sb-toggle " + (hideOvervalued ? "on" : "")}
                  onClick={() => setHideOvervalued((v) => !v)}
                  title="Show only stocks where intrinsic > price"
                >
                  ↑ Undervalued only
                </button>
                <button
                  className={"sb-toggle " + (watchOnly ? "on" : "")}
                  onClick={() => setWatchOnly((v) => !v)}
                >
                  ★ Watchlist only
                </button>
              </div>
            </div>
          </div>

          <div className="sb-wl">
            <div className="sb-wl-head">
              <span className="sb-wl-label">★ Watchlist</span>
              <span className="sb-wl-count">{watchlistItems.length}</span>
            </div>
            <div className="sb-wl-scroll">
              {watchlistItems.length === 0 ? (
                <div className="sb-wl-empty">
                  Star stocks to track them here.
                </div>
              ) : (
                watchlistItems.map((s) => (
                  <button
                    key={s.ticker}
                    type="button"
                    className={`sb-wl-chip tier tier-${s.tier ?? 4}`}
                    onClick={() => setOpened(s)}
                  >
                    <span
                      className="sb-wl-x"
                      onClick={(e) => {
                        e.stopPropagation();
                        toggleWatch(s.ticker, s.watchlist);
                      }}
                      title="Remove from watchlist"
                    >
                      ★
                    </span>
                    <span className="t">{s.ticker}</span>
                    <span className="u">{fmtUps(s.upside)}</span>
                    <span className="p">{fmtPrice(s.price)}</span>
                  </button>
                ))
              )}
            </div>
          </div>
        </div>

        <div className="sb-status">
          <div className="l">
            {stocksQ.isLoading ? (
              "Loading…"
            ) : (
              <>
                <strong>{filtered.length}</strong> stocks · sorted by{" "}
                {sort.toLowerCase()}
              </>
            )}
          </div>
          <div className="r">
            DCF · P/E · EV/EBITDA
          </div>
        </div>

        <div className="sb-grid">
          {visible.map((s) => (
            <Card
              key={s.ticker}
              s={s}
              ranked={sort === "Most undervalued" || sort === "Most overvalued"}
              selected={opened?.ticker === s.ticker}
              onOpen={() => setOpened(s)}
              onToggleWatch={() => toggleWatch(s.ticker, s.watchlist)}
            />
          ))}
          {!stocksQ.isLoading && filtered.length === 0 && (
            <div
              style={{
                gridColumn: "1/-1",
                padding: 60,
                textAlign: "center",
                color: "var(--navi-fg3)",
              }}
            >
              No stocks match these filters.
            </div>
          )}
        </div>

        {filtered.length > shown && (
          <div className="sb-load-more">
            <div className="status">
              Showing <strong>{visible.length}</strong> of{" "}
              <strong>{filtered.length}</strong> stocks
            </div>
            <button
              className="sb-btn-tinted"
              onClick={() => setShown((n) => n + PAGE_SIZE)}
            >
              Load {PAGE_SIZE} more ↓
            </button>
          </div>
        )}
      </main>

      {opened && (
        <DetailDrawer
          stock={opened}
          onClose={() => setOpened(null)}
          onToggleWatch={() => toggleWatch(opened.ticker, opened.watchlist)}
        />
      )}

      {showDefaults && (
        <DefaultsModal
          onClose={() => setShowDefaults(false)}
          onApplied={() => stocksQ.refetch()}
        />
      )}

      {showAdd && (
        <AddStockModal
          onClose={() => setShowAdd(false)}
          onAdded={() => stocksQ.refetch()}
        />
      )}
    </div>
  );
}

// ─── Add stock modal ──────────────────────────────────────────
function AddStockModal({
  onClose,
  onAdded,
}: {
  onClose: () => void;
  onAdded: () => void;
}) {
  const initial = loadDefaults();
  const [ticker, setTicker] = useState("");
  const [growth, setGrowth] = useState(initial.growth);
  const [discount, setDiscount] = useState(initial.discount);
  const [terminal, setTerminal] = useState(initial.terminal);
  const [targetPe, setTargetPe] = useState(18);
  const [targetEvEbitda, setTargetEvEbitda] = useState(12);
  const [pin, setPin] = useState(false);
  const [hold, setHold] = useState(false);
  const [saving, setSaving] = useState(false);

  const valid = ticker.trim().length > 0 && discount > terminal;

  const handleSave = async () => {
    if (!valid) return;
    setSaving(true);
    try {
      const input: NewStockInput = {
        ticker: ticker.trim().toUpperCase(),
        stage1_growth_pct: growth,
        discount_rate_pct: discount,
        terminal_growth_pct: terminal,
        target_pe: targetPe,
        target_ev_ebitda: targetEvEbitda,
        watchlist: pin,
        hold_position: hold,
      };
      await addStock(input);
      toast.success(
        `${input.ticker} added. Click "⟳ Sync fundamentals" to pull data.`,
      );
      onAdded();
      onClose();
    } catch (e) {
      toast.error((e as Error).message);
      setSaving(false);
    }
  };

  return (
    <div className="sb-drawer-overlay" onClick={onClose}>
      <div
        className="sb-drawer"
        onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: 480 }}
      >
        <div className="sb-drawer-hero tier tier-3" style={{ marginBottom: 16 }}>
          <button className="close" onClick={onClose}>
            ✕
          </button>
          <div className="ticker">+ Add stock</div>
          <div className="meta">
            Adds the ticker to the universe with your assumptions. Name,
            sector, price, EPS, EBITDA, and shares are filled in by the
            next "Sync fundamentals" run.
          </div>
        </div>

        <h3>Ticker</h3>
        <input
          type="text"
          className="sb-search"
          style={{ width: "100%" }}
          placeholder="e.g. AAPL"
          autoFocus
          value={ticker}
          onChange={(e) => setTicker(e.target.value.toUpperCase())}
        />

        <h3>Assumptions</h3>
        <div className="sb-slider-block">
          <Slider
            label="Stage 1 growth"
            value={growth}
            min={-20}
            max={50}
            step={0.5}
            unit="%"
            onChange={setGrowth}
          />
          <Slider
            label="Discount rate (WACC)"
            value={discount}
            min={4}
            max={20}
            step={0.25}
            unit="%"
            onChange={setDiscount}
          />
          <Slider
            label="Terminal growth"
            value={terminal}
            min={0}
            max={5}
            step={0.25}
            unit="%"
            onChange={setTerminal}
          />
          <Slider
            label="Target P/E"
            value={targetPe}
            min={5}
            max={50}
            step={0.5}
            unit="x"
            onChange={setTargetPe}
          />
          <Slider
            label="Target EV/EBITDA"
            value={targetEvEbitda}
            min={3}
            max={30}
            step={0.5}
            unit="x"
            onChange={setTargetEvEbitda}
          />
          {discount <= terminal && (
            <div
              style={{
                color: "var(--navi-negative)",
                fontSize: 11,
                marginTop: 8,
                fontFamily: "var(--navi-font-mono)",
              }}
            >
              Discount must exceed terminal growth.
            </div>
          )}
        </div>

        <div style={{ marginTop: 18, display: "flex", gap: 24 }}>
          <label
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              fontSize: 13,
              color: "var(--navi-fg2)",
              cursor: "pointer",
            }}
          >
            <input
              type="checkbox"
              checked={pin}
              onChange={(e) => setPin(e.target.checked)}
              style={{ accentColor: "var(--navi-neon)" }}
            />
            ★ Add to watchlist
          </label>
          <label
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              fontSize: 13,
              color: "var(--navi-fg2)",
              cursor: "pointer",
            }}
          >
            <input
              type="checkbox"
              checked={hold}
              onChange={(e) => setHold(e.target.checked)}
              style={{ accentColor: "var(--navi-neon)" }}
            />
            I hold this
          </label>
        </div>

        <div style={{ display: "flex", gap: 8, marginTop: 24 }}>
          <button
            className="sb-btn-tinted"
            style={{ flex: 1 }}
            onClick={onClose}
            disabled={saving}
          >
            Cancel
          </button>
          <button
            className="sb-btn-primary"
            style={{ flex: 1 }}
            onClick={handleSave}
            disabled={!valid || saving}
          >
            {saving ? "Adding…" : "Add stock"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Defaults modal ───────────────────────────────────────────
function DefaultsModal({
  onClose,
  onApplied,
}: {
  onClose: () => void;
  onApplied: () => void;
}) {
  const initial = loadDefaults();
  const [d, setD] = useState<SnowballDefaults>(initial);
  const [saving, setSaving] = useState(false);
  const valid = d.discount > d.terminal;

  const handleApply = async () => {
    if (!valid) return;
    setSaving(true);
    try {
      const n = await applyDefaults(d);
      saveDefaults(d);
      toast.success(`Applied to ${n} tickers.`);
      onApplied();
      onClose();
    } catch (e) {
      toast.error(`Failed: ${(e as Error).message}`);
      setSaving(false);
    }
  };

  return (
    <div className="sb-drawer-overlay" onClick={onClose}>
      <div
        className="sb-drawer"
        onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: 480 }}
      >
        <div className="sb-drawer-hero tier tier-3" style={{ marginBottom: 16 }}>
          <button className="close" onClick={onClose}>
            ✕
          </button>
          <div className="ticker">⚙ Defaults</div>
          <div className="meta">
            Universe-wide DCF assumptions. Applies to all 524 tickers and
            recomputes every intrinsic value + target buy price.
          </div>
        </div>

        <div className="sb-slider-block">
          <Slider
            label="Stage 1 growth"
            value={d.growth}
            min={-20}
            max={50}
            step={0.5}
            unit="%"
            onChange={(v) => setD({ ...d, growth: v })}
          />
          <Slider
            label="Discount rate (WACC)"
            value={d.discount}
            min={4}
            max={20}
            step={0.25}
            unit="%"
            onChange={(v) => setD({ ...d, discount: v })}
          />
          <Slider
            label="Terminal growth"
            value={d.terminal}
            min={0}
            max={5}
            step={0.25}
            unit="%"
            onChange={(v) => setD({ ...d, terminal: v })}
          />
          {!valid && (
            <div
              style={{
                color: "var(--navi-negative)",
                fontSize: 11,
                marginTop: 8,
                fontFamily: "var(--navi-font-mono)",
              }}
            >
              Discount must exceed terminal growth.
            </div>
          )}
        </div>

        <p
          style={{
            fontSize: 11,
            color: "var(--navi-fg3)",
            marginTop: 16,
            fontFamily: "var(--navi-font-mono)",
            lineHeight: 1.5,
          }}
        >
          ⚠ This overwrites any per-ticker customizations you've made via
          the drawer sliders. Individual overrides can be set again
          afterwards.
        </p>

        <div style={{ display: "flex", gap: 8, marginTop: 20 }}>
          <button
            className="sb-btn-tinted"
            style={{ flex: 1 }}
            onClick={onClose}
            disabled={saving}
          >
            Cancel
          </button>
          <button
            className="sb-btn-primary"
            style={{ flex: 1 }}
            onClick={handleApply}
            disabled={!valid || saving}
          >
            {saving ? "Applying…" : "Apply to all"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Card ─────────────────────────────────────────────────────
function Card({
  s,
  ranked,
  selected,
  onOpen,
  onToggleWatch,
}: {
  s: ComputedStock;
  ranked: boolean;
  selected: boolean;
  onOpen: () => void;
  onToggleWatch: () => void;
}) {
  const tier = s.tier ?? 4;
  const has52 = s.low_52w != null && s.high_52w != null && s.price != null;
  return (
    <button
      type="button"
      onClick={onOpen}
      className={
        "sb-card tier tier-" +
        tier +
        (selected ? " is-selected" : "") +
        (ranked ? " has-rank" : "")
      }
    >
      {ranked && <span className="sb-rank">#{s.rank}</span>}
      {s.hold_position && <span className="sb-hold-tag">HOLD</span>}
      <button
        type="button"
        className={"sb-star " + (s.watchlist ? "on" : "")}
        onClick={(e) => {
          e.stopPropagation();
          onToggleWatch();
        }}
        title={s.watchlist ? "Remove from watchlist" : "Add to watchlist"}
      >
        {s.watchlist ? "★" : "☆"}
      </button>

      <div className="sb-card-head">
        <div>
          <div className="ticker">{s.ticker}</div>
          <div className="name">{s.name}</div>
        </div>
      </div>

      <div className="upside">
        {s.intrinsic_invalid ? "—" : fmtUps(s.upside)}
      </div>

      <div className="intrinsic-row">
        <span className="l">Intrinsic</span>
        <span className="v">
          {s.intrinsic_invalid ? "—" : fmtPrice2(s.intrinsic_value)}
        </span>
      </div>

      {/* Margin of safety pill — Buffett's framing: "trading at X% off
          intrinsic". Positive = undervalued (good). Hidden when we don't
          have valid data. */}
      {!s.intrinsic_invalid && (
        <div
          style={{
            fontSize: 10,
            fontFamily: "var(--navi-font-mono)",
            opacity: 0.85,
            display: "flex",
            justifyContent: "space-between",
            padding: "4px 12px",
            background: "rgba(0,0,0,.18)",
            borderRadius: 100,
          }}
        >
          <span style={{ letterSpacing: 1, textTransform: "uppercase" }}>
            Margin of safety
          </span>
          <strong>
            {s.margin_of_safety > 0
              ? `${s.margin_of_safety.toFixed(0)}% off`
              : `${Math.abs(s.margin_of_safety).toFixed(0)}% premium`}
          </strong>
        </div>
      )}

      {has52 ? (
        <Range52w price={s.price!} low={s.low_52w!} high={s.high_52w!} />
      ) : s.distance_to_buy ? (
        <span className="sb-distance">{s.distance_to_buy}</span>
      ) : null}

      <div className="footer-row">
        <span style={{ opacity: 0.6, fontSize: 10 }}>{s.sector ?? "—"}</span>
        <span style={{ fontFamily: "var(--navi-font-mono)" }}>
          {fmtPrice(s.price)}
        </span>
      </div>
    </button>
  );
}

// ─── 52-week range bar ────────────────────────────────────────
function Range52w({
  price,
  low,
  high,
}: {
  price: number;
  low: number;
  high: number;
}) {
  const pct = Math.max(0, Math.min(1, (price - low) / (high - low || 1)));
  return (
    <div className="sb-r52">
      <span className="cap">52w</span>
      <span className="lo">{fmtPrice(low)}</span>
      <div className="track">
        <div className="fill" style={{ width: pct * 100 + "%" }} />
        <div className="thumb" style={{ left: pct * 100 + "%" }} />
      </div>
      <span className="hi">{fmtPrice(high)}</span>
    </div>
  );
}

// ─── Detail drawer ────────────────────────────────────────────
function DetailDrawer({
  stock,
  onClose,
  onToggleWatch,
}: {
  stock: ComputedStock;
  onClose: () => void;
  onToggleWatch: () => void;
}) {
  const qc = useQueryClient();
  const s = stock;
  const tier = s.tier ?? 4;

  // Local slider state — diverges from the saved row until "Save & recalc".
  const [growth, setGrowth] = useState<number>(s.stage1_growth_pct ?? 5);
  const [discount, setDiscount] = useState<number>(s.discount_rate_pct ?? 10);
  const [terminal, setTerminal] = useState<number>(s.terminal_growth_pct ?? 2.5);
  const [tpe, setTpe] = useState<number>(s.target_pe ?? 18);
  const [tev, setTev] = useState<number>(s.target_ev_ebitda ?? 12);
  const [saving, setSaving] = useState(false);

  // Reset when a different stock is opened.
  useMemo(() => {
    setGrowth(s.stage1_growth_pct ?? 5);
    setDiscount(s.discount_rate_pct ?? 10);
    setTerminal(s.terminal_growth_pct ?? 2.5);
    setTpe(s.target_pe ?? 18);
    setTev(s.target_ev_ebitda ?? 12);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s.ticker]);

  // Live recompute as user drags.
  const liveIntrinsic = useMemo(
    () =>
      dcfIntrinsic({
        total_owner_earnings: s.total_owner_earnings ?? 0,
        shares_outstanding: s.shares_outstanding ?? 0,
        stage1_growth_pct: growth,
        discount_rate_pct: discount,
        terminal_growth_pct: terminal,
      }),
    [growth, discount, terminal, s.total_owner_earnings, s.shares_outstanding],
  );

  const liveUpside =
    liveIntrinsic != null && s.price && s.price > 0
      ? ((liveIntrinsic - s.price) / s.price) * 100
      : null;

  const dirty =
    growth !== (s.stage1_growth_pct ?? 5) ||
    discount !== (s.discount_rate_pct ?? 10) ||
    terminal !== (s.terminal_growth_pct ?? 2.5) ||
    tpe !== (s.target_pe ?? 18) ||
    tev !== (s.target_ev_ebitda ?? 12);

  const valid = liveIntrinsic != null;

  const handleSave = async () => {
    if (!dirty || !valid) return;
    setSaving(true);
    try {
      // 1) Save the multiple overrides separately (DCF doesn't depend on them).
      if (tpe !== (s.target_pe ?? 18) || tev !== (s.target_ev_ebitda ?? 12)) {
        await updateMultiples(s.ticker, {
          target_pe: tpe,
          target_ev_ebitda: tev,
        });
      }
      // 2) Then assumption update — this also triggers DCF recompute.
      await updateAssumptions(s.ticker, {
        stage1_growth_pct: growth,
        discount_rate_pct: discount,
        terminal_growth_pct: terminal,
      });
      qc.invalidateQueries({ queryKey: ["snowball", "stocks"] });
      toast.success(`${s.ticker} updated.`);
    } catch (e) {
      toast.error(`Save failed: ${(e as Error).message}`);
    } finally {
      setSaving(false);
    }
  };

  const displayedIntrinsic = dirty ? liveIntrinsic : s.intrinsic_value;
  const displayedUpside = dirty ? liveUpside : s.upside;

  return (
    <div className="sb-drawer-overlay" onClick={onClose}>
      <div className="sb-drawer" onClick={(e) => e.stopPropagation()}>
        <div className={`sb-drawer-hero tier tier-${tier}`}>
          <button className="close" onClick={onClose}>
            ✕
          </button>
          <div className="ticker">{s.ticker}</div>
          <div className="meta">
            {s.name} · {s.sector ?? "—"} · {fmtMcap(s.market_cap)}
          </div>
          <div className="upside">{fmtUps(displayedUpside ?? 0)}</div>
          <div className="badge">
            margin of safety · {TIER_LABEL[tier]}
            {dirty ? " · live preview" : ""}
          </div>
        </div>

        <h3>The story</h3>
        <div className="sb-story">
          {s.price && s.price > 0 ? (
            <>
              Trading at <strong>{fmtPrice2(s.price)}</strong> against an
              estimated intrinsic value of{" "}
              <strong>{fmtPrice2(displayedIntrinsic)}</strong>.{" "}
              {(displayedUpside ?? 0) > 15
                ? "Market is mispricing this lower than the fundamentals justify — meaningful margin of safety."
                : (displayedUpside ?? 0) > 0
                  ? "Fundamentals support modest upside from current levels."
                  : (displayedUpside ?? 0) > -15
                    ? "Close to fair value; little margin in either direction."
                    : "Market may be pricing in growth that the fundamentals do not yet support."}
              {s.distance_to_buy && !dirty ? ` Status: ${s.distance_to_buy}.` : ""}
            </>
          ) : (
            <>
              Estimated intrinsic value{" "}
              <strong>{fmtPrice2(displayedIntrinsic)}</strong> per share. No
              live quote yet — click <strong>↻ Refresh prices</strong> to pull
              the latest from Polygon.
            </>
          )}
        </div>

        <h3>Three lenses</h3>
        <div className="sb-tbp-grid">
          <div className="sb-lens">
            <div className="lbl">DCF</div>
            <div className="val">
              {fmtPrice2(dirty ? liveIntrinsic : s.intrinsic_dcf)}
            </div>
            <div className="sub">
              weight {Math.round((s.weight_dcf ?? 0.4) * 100)}%
            </div>
          </div>
          <div className="sb-lens">
            <div className="lbl">P/E</div>
            <div className="val">{fmtPrice2(s.intrinsic_pe)}</div>
            <div className="sub">
              eps {fmtPrice2(s.eps_ttm)} × {(s.target_pe ?? 18).toFixed(0)}x
            </div>
          </div>
          <div className="sb-lens">
            <div className="lbl">EV/EBITDA</div>
            <div className="val">{fmtPrice2(s.intrinsic_ev_ebitda)}</div>
            <div className="sub">
              ebitda × {(s.target_ev_ebitda ?? 12).toFixed(0)}x
            </div>
          </div>
        </div>

        <h3>Target buy prices</h3>
        <div className="sb-tbp-grid">
          <div className="sb-lens">
            <div className="lbl">Aggressive 15%</div>
            <div className="val">
              {fmtPrice2(
                dirty && liveIntrinsic != null
                  ? liveIntrinsic * 0.85
                  : s.tbp_aggressive_15,
              )}
            </div>
          </div>
          <div className="sb-lens">
            <div className="lbl">Conservative 30%</div>
            <div className="val">
              {fmtPrice2(
                dirty && liveIntrinsic != null
                  ? liveIntrinsic * 0.7
                  : s.tbp_conservative_30,
              )}
            </div>
          </div>
          <div className="sb-lens">
            <div className="lbl">Deep value 50%</div>
            <div className="val">
              {fmtPrice2(
                dirty && liveIntrinsic != null
                  ? liveIntrinsic * 0.5
                  : s.tbp_deep_value_50,
              )}
            </div>
          </div>
        </div>

        <h3>Tune assumptions</h3>
        <div className="sb-slider-block">
          <Slider
            label="Stage 1 growth"
            value={growth}
            min={-20}
            max={50}
            step={0.5}
            unit="%"
            onChange={setGrowth}
          />
          <Slider
            label="Discount rate (WACC)"
            value={discount}
            min={4}
            max={20}
            step={0.25}
            unit="%"
            onChange={setDiscount}
          />
          <Slider
            label="Terminal growth"
            value={terminal}
            min={0}
            max={5}
            step={0.25}
            unit="%"
            onChange={setTerminal}
          />
          <Slider
            label="Target P/E"
            value={tpe}
            min={5}
            max={50}
            step={0.5}
            unit="x"
            onChange={setTpe}
          />
          <Slider
            label="Target EV/EBITDA"
            value={tev}
            min={3}
            max={30}
            step={0.5}
            unit="x"
            onChange={setTev}
          />
          {!valid && (
            <div
              style={{
                color: "var(--navi-negative)",
                fontSize: 11,
                marginTop: 8,
                fontFamily: "var(--navi-font-mono)",
              }}
            >
              Discount must exceed terminal growth (Gordon model diverges).
            </div>
          )}
        </div>

        <h3>Fundamentals</h3>
        <div className="sb-fund-grid">
          <Fund l="Price" v={fmtPrice2(s.price)} />
          <Fund
            l="52w range"
            v={
              s.low_52w != null && s.high_52w != null
                ? `${fmtPrice(s.low_52w)} – ${fmtPrice(s.high_52w)}`
                : "—"
            }
          />
          <Fund l="Today" v={fmtPct(s.change_pct, 2)} />
          <Fund l="Owner earnings" v={fmtPrice(s.total_owner_earnings)} />
          <Fund l="Shares out" v={s.shares_outstanding != null ? `${(s.shares_outstanding).toFixed(1)}M` : "—"} />
          <Fund l="Dividend yield" v={fmtPct(s.dividend_yield_pct, 2)} />
          <Fund l="Industry" v={s.industry ?? "—"} />
          <Fund l="Earnings" v={s.earnings_date ?? "—"} />
          <Fund l="Distance" v={s.distance_to_buy ?? "—"} />
        </div>

        <div style={{ display: "flex", gap: 8, marginTop: 20 }}>
          <button
            className="sb-btn-primary"
            style={{ flex: 1 }}
            disabled={!dirty || !valid || saving}
            onClick={handleSave}
          >
            {saving ? "Saving…" : dirty ? "Save & recalc ↗" : "No changes"}
          </button>
          <button className="sb-btn-tinted" onClick={onToggleWatch}>
            {s.watchlist ? "★ Remove" : "☆ Watchlist"}
          </button>
        </div>
      </div>
    </div>
  );
}

function Slider({
  label,
  value,
  min,
  max,
  step,
  unit,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  unit?: string;
  onChange: (v: number) => void;
}) {
  return (
    <div className="sb-slider-row">
      <div className="top">
        <span className="l">{label}</span>
        <span className="v">
          {value.toFixed(step < 1 ? 2 : 1)}
          {unit ?? ""}
        </span>
      </div>
      <input
        type="range"
        className="sb-slider"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
    </div>
  );
}

function Fund({ l, v }: { l: string; v: string }) {
  return (
    <div className="sb-fund">
      <div className="l">{l}</div>
      <div className="v">{v}</div>
    </div>
  );
}
