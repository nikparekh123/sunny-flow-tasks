/**
 * Expected Income — project premium income from selling covered calls.
 *
 * State shape: all numeric inputs are strings so the controls can hold partial
 * entries ("2.") without trapping the user. Cast to Number() at compute time.
 */
import { useMemo, type ReactNode } from "react";
import {
  FREQ_DEFS, FREQ_BY_ID, HORIZON_DEFS,
  cycleStats, resolveHorizon,
  fmtMoney, fmtPct, fmtCount, fmtDate,
  CycField, NumInput, HeroNumInput, Seg, Tile, PullFromSunnyfi,
} from "../cycle";

export interface EIState extends Record<string, unknown> {
  underlying: string;
  shares: string;
  contracts: string;
  price: string;
  premium: string;
  callDistance: string;
  frequency: string;
  horizon: string;
  customDate: string;
}

export const eiInitial: EIState = {
  underlying: "SPY",
  shares: "500",
  contracts: "5",
  price: "655.06",
  premium: "2.80",
  callDistance: "1.0",
  frequency: "weekly",
  horizon: "year",
  customDate: "",
};

interface Computed {
  contracts: number;
  incomePerCycle: number;
  cycles: number;
  days: number;
  years: number;
  totalIncome: number;
  notional: number;
  annualIncome: number;
  annYieldPct: number;
  annROIPct: number;
  horizonDate: Date | null;
  impliedStrike: number;
  coveredShares: number;
  coveragePct: number;
}

export function computeEI(state: EIState, now: Date = new Date()): Computed {
  const shares    = Number(state.shares);
  const price     = Number(state.price);
  const premium   = Number(state.premium);
  const distance  = Number(state.callDistance);
  const contracts = Number(state.contracts);
  const validShares    = state.shares    !== "" && isFinite(shares)    && shares > 0;
  const validPrice     = state.price     !== "" && isFinite(price)     && price > 0;
  const validPrem      = state.premium   !== "" && isFinite(premium)   && premium >= 0;
  const validDist      = state.callDistance !== "" && isFinite(distance);
  const validContracts = state.contracts !== "" && isFinite(contracts) && contracts >= 0;

  const incomePerCycle = validContracts && validPrem ? contracts * premium * 100 : NaN;
  const horizonDate    = resolveHorizon(state.horizon, state.customDate, now);
  const { cycles, days, years } = cycleStats(state.frequency, horizonDate, now);
  const totalIncome = isFinite(cycles) && isFinite(incomePerCycle) ? cycles * incomePerCycle : NaN;
  const notional    = validShares && validPrice ? shares * price : NaN;
  const impliedStrike = validPrice && validDist ? price * (1 + distance / 100) : NaN;
  const coveredShares = validContracts ? contracts * 100 : NaN;
  const coveragePct   = validShares && isFinite(coveredShares) ? (coveredShares / shares) * 100 : NaN;

  let annualIncome = NaN;
  if (isFinite(cycles) && isFinite(incomePerCycle) && isFinite(years) && years > 0) {
    annualIncome = (cycles * incomePerCycle) / years;
  }
  const annYieldPct = isFinite(annualIncome) && isFinite(notional) && notional > 0
    ? (annualIncome / notional) * 100 : NaN;
  const annROIPct = annYieldPct;

  return {
    contracts, incomePerCycle, cycles, days, years, totalIncome, notional,
    annualIncome, annYieldPct, annROIPct, horizonDate, impliedStrike,
    coveredShares, coveragePct,
  };
}

// ── Registry helpers ─────────────────────────────────────────────
export function eiCopy(state: EIState): string {
  const c = computeEI(state);
  return `${state.underlying} · ${fmtCount(Number(state.shares))} sh × ${fmtMoney(Number(state.price))} · premium ${fmtMoney(Number(state.premium))} × ${fmtCount(c.cycles)} cycles to ${fmtDate(c.horizonDate)} = ${fmtMoney(c.totalIncome)} total (${fmtPct(c.annYieldPct)} ann.)`;
}

export function eiDisplay(state: EIState): { value: string; tone: "neon" | "pos" | "neg" | "muted" } {
  const c = computeEI(state);
  if (!isFinite(c.totalIncome)) return { value: "—", tone: "muted" };
  return { value: fmtMoney(c.totalIncome), tone: c.totalIncome > 0 ? "pos" : "muted" };
}

/** Saved snapshots upsert on ticker so re-saving SPY replaces the existing
 *  SPY card in the Compare view instead of stacking duplicates. */
export function eiUpsertKey(state: EIState): string | null {
  return state.underlying?.trim().toUpperCase() || null;
}

/** Compare-view ranking: prefer the trade with the highest annualised yield.
 *  Higher score = better trade. */
export function eiRank(state: EIState): { score: number; label: string } | null {
  const c = computeEI(state);
  if (!isFinite(c.annYieldPct)) return null;
  return { score: c.annYieldPct, label: "ann. yield" };
}

export function eiCardLine(state: EIState): string {
  const c = computeEI(state);
  return `${fmtCount(Number(state.shares))} sh × ${fmtMoney(Number(state.price))} · ${fmtCount(c.cycles)} cycles to ${fmtDate(c.horizonDate)}`;
}

export function eiFields(state: EIState): Array<{ label: string; value: string; mono?: boolean }> {
  const c = computeEI(state);
  return [
    { label: "Underlying",     value: state.underlying || "—",                            mono: true },
    { label: "Shares × Price", value: `${fmtCount(Number(state.shares))} × ${fmtMoney(Number(state.price))}`, mono: true },
    { label: "Premium",        value: fmtMoney(Number(state.premium)),                    mono: true },
    { label: "Cycles · Horizon", value: `${fmtCount(c.cycles)} · ${fmtDate(c.horizonDate)}`, mono: true },
    { label: "Total income",   value: fmtMoney(c.totalIncome),                            mono: true },
    { label: "Ann. yield",     value: fmtPct(c.annYieldPct),                              mono: true },
  ];
}

// ── Body ─────────────────────────────────────────────────────────
export function ExpectedIncomeCalc({
  state,
  setState,
}: {
  state: EIState;
  setState: (next: EIState | ((prev: EIState) => EIState)) => void;
}) {
  const set = <K extends keyof EIState>(k: K, v: EIState[K]) => setState({ ...state, [k]: v });
  const c = useMemo(() => computeEI(state), [state]);
  const freq = FREQ_BY_ID[state.frequency] || FREQ_BY_ID.weekly;
  const tone: "pos" | "neutral" = isFinite(c.totalIncome) && c.totalIncome > 0 ? "pos" : "neutral";

  const helper: ReactNode = (() => {
    if (!isFinite(c.totalIncome) || c.cycles === 0) {
      return <>Enter shares, current price, premium, frequency, and a horizon to see projected income.</>;
    }
    return (
      <>
        <b>{fmtCount(c.cycles)}</b> cycle{c.cycles === 1 ? "" : "s"} between now and{" "}
        <b>{fmtDate(c.horizonDate)}</b> × <b>{fmtMoney(c.incomePerCycle)}</b> per cycle ={" "}
        <b className="pos">{fmtMoney(c.totalIncome)}</b> total
        {isFinite(c.annYieldPct) ? <> (<b className="neon">{fmtPct(c.annYieldPct)}</b> annualised yield)</> : null}.
      </>
    );
  })();

  return (
    <div className="cyc">
      <p className="cyc-desc">
        Project premium income from selling covered calls. Pick a frequency, pick a horizon.
      </p>

      {/* Position context */}
      <div className="cyc-context">
        <CycField label="Underlying">
          <NumInput
            value={state.underlying}
            onChange={(v) => set("underlying", v.toUpperCase())}
            placeholder="SPY"
            ariaLabel="Underlying ticker"
            className="ticker"
          />
          <PullFromSunnyfi
            ticker={state.underlying}
            onPull={({ price, shares }) =>
              setState({
                ...state,
                price: price.toFixed(2),
                ...(shares ? { shares: String(shares) } : {}),
              })
            }
          />
        </CycField>

        <CycField label="Shares">
          <NumInput value={state.shares} onChange={(v) => set("shares", v)} placeholder="0" ariaLabel="Shares" />
        </CycField>

        <CycField label="Contracts">
          <NumInput
            value={state.contracts}
            onChange={(v) => set("contracts", v)}
            placeholder="0"
            ariaLabel="Contracts to sell"
            suffix={isFinite(c.coveredShares) ? `× 100 = ${fmtCount(c.coveredShares)} sh` : ""}
          />
        </CycField>

        <CycField label="Current price">
          <NumInput value={state.price} onChange={(v) => set("price", v)} placeholder="0.00" prefix="$" ariaLabel="Current price" />
        </CycField>
      </div>

      {/* Hero — premium + OTM distance */}
      <div className="cyc-section">
        <div className="cyc-hero two">
          <div className="cyc-hero-field">
            <div className="hf-label">Premium per contract</div>
            <HeroNumInput value={state.premium} onChange={(v) => set("premium", v)} placeholder="0.00" prefix="$" ariaLabel="Premium per contract" />
            <div className="cyc-hero-sub">
              Income per cycle = <span className="accent">{fmtCount(Number(state.contracts) || 0)} contracts × {fmtMoney(Number(state.premium) || 0)} × 100</span> = <span className="accent">{fmtMoney(c.incomePerCycle)}</span>
            </div>
          </div>
          <div className="cyc-hero-field">
            <div className="hf-label">Strike distance · OTM</div>
            <div className="cyc-hero-row">
              <input
                className="cyc-hero-input muted"
                type="text"
                inputMode="decimal"
                value={state.callDistance}
                onChange={(e) => set("callDistance", e.target.value)}
                placeholder="0.0"
                spellCheck={false}
                aria-label="Strike distance OTM"
              />
              <span className="cyc-hero-prefix" style={{ color: "var(--navi-fg2)" }}>%</span>
            </div>
            <div className="cyc-hero-sub">
              {isFinite(c.impliedStrike)
                ? <>Implied strike <span className="accent">{fmtMoney(c.impliedStrike)}</span> · {Number(state.callDistance) > 0 ? "above" : Number(state.callDistance) < 0 ? "below" : "at"} spot</>
                : <>Set a distance to see implied strike</>}
            </div>
          </div>
        </div>
      </div>

      {/* Cadence */}
      <div className="cyc-section">
        <div className="cyc-cadence">
          <div className="cyc-cad-field">
            <div className="hf-label">Frequency</div>
            <Seg
              options={FREQ_DEFS.map(f => ({ id: f.id, label: f.label }))}
              value={state.frequency}
              onChange={(v) => set("frequency", v)}
              ariaLabel="Cycle frequency"
            />
            <div className="cyc-cad-readout">
              <span className="accent">{freq.label}</span> · ~<span className="accent">{freq.perYear}</span> cycles/year
            </div>
          </div>

          <div className="cyc-cad-field">
            <div className="hf-label">Cut off</div>
            <Seg
              options={HORIZON_DEFS.map(h => ({ id: h.id, label: h.label }))}
              value={state.horizon}
              onChange={(v) => set("horizon", v)}
              ariaLabel="Cut off"
            />
            {state.horizon === "custom" && (
              <div className="cyc-cad-date">
                <span>→</span>
                <input
                  type="date"
                  value={state.customDate}
                  onChange={(e) => set("customDate", e.target.value)}
                  aria-label="Custom horizon date"
                />
              </div>
            )}
            <div className="cyc-cad-readout">
              Through <span className="neon">{fmtDate(c.horizonDate)}</span>
              {isFinite(c.days) && <> · <span className="accent">{c.days}</span> days · <span className="accent">{fmtCount(c.cycles)}</span> cycles</>}
            </div>
          </div>
        </div>
      </div>

      {/* Results */}
      <div className="cyc-results">
        <Tile label="Income per cycle"        value={fmtMoney(c.incomePerCycle)} tone={tone} />
        <Tile label="Cycles until horizon"    value={fmtCount(c.cycles)}         mono />
        <Tile label="Total income to horizon" value={fmtMoney(c.totalIncome)}    tone={tone} primary />
        <Tile label="Annualised yield"        value={fmtPct(c.annYieldPct)}      tone="neon" sub="vs notional" />
        <Tile label="Annualised ROI"          value={fmtPct(c.annROIPct)}        tone="neon" sub="on position cost basis" />
      </div>

      <div className="cyc-helper">{helper}</div>
    </div>
  );
}
