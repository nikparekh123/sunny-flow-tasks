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
const PAGE_SIZE = 60;

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
  const [opened, setOpened] = useState<ComputedStock | null>(null);
  const [shown, setShown] = useState(PAGE_SIZE);

  const filtered = useMemo(() => {
    let r = all;
    if (filter !== "All") r = r.filter((s) => s.sector === filter);
    if (watchOnly) r = r.filter((s) => s.watchlist);
    return sortStocks(r, sort);
  }, [all, filter, sort, watchOnly]);

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
        </div>
      </header>

      <main className="sb-stage">
        <div className="sb-controls">
          <div className="sb-toolbar">
            <div className="sb-tb-row">
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

      <div className="upside">{fmtUps(s.upside)}</div>

      <div className="intrinsic-row">
        <span className="l">Intrinsic</span>
        <span className="v">{fmtPrice2(s.intrinsic_value)}</span>
      </div>

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
  const [saving, setSaving] = useState(false);

  // Reset when a different stock is opened.
  useMemo(() => {
    setGrowth(s.stage1_growth_pct ?? 5);
    setDiscount(s.discount_rate_pct ?? 10);
    setTerminal(s.terminal_growth_pct ?? 2.5);
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
    terminal !== (s.terminal_growth_pct ?? 2.5);

  const valid = liveIntrinsic != null;

  const handleSave = async () => {
    if (!dirty || !valid) return;
    setSaving(true);
    try {
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
          Trading at <strong>{fmtPrice2(s.price)}</strong> against an estimated
          intrinsic value of <strong>{fmtPrice2(displayedIntrinsic)}</strong>.{" "}
          {(displayedUpside ?? 0) > 15
            ? "Market is mispricing this lower than the fundamentals justify — meaningful margin of safety."
            : (displayedUpside ?? 0) > 0
              ? "Fundamentals support modest upside from current levels."
              : (displayedUpside ?? 0) > -15
                ? "Close to fair value; little margin in either direction."
                : "Market may be pricing in growth that the fundamentals do not yet support."}
          {s.distance_to_buy && !dirty ? ` Status: ${s.distance_to_buy}.` : ""}
        </div>

        <h3>Target buy prices {dirty && <span style={{ color: "var(--navi-neon)", fontWeight: 500, letterSpacing: 0 }}>(live)</span>}</h3>
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
            <div className="sub">small margin</div>
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
            <div className="sub">standard</div>
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
            <div className="sub">strict</div>
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
