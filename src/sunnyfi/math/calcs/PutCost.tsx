/**
 * Put Cost — project the cost of protective puts.
 *
 * Mirror of Expected Income except: tracks cost per cycle (negative tone),
 * has an explicit strike (not OTM distance), reports coverage and warning-
 * gold annualised cost as % of notional.
 */
import { useMemo, type ReactNode } from "react";
import {
  FREQ_DEFS, FREQ_BY_ID, HORIZON_DEFS,
  cycleStats, resolveHorizon,
  fmtMoney, fmtPct, fmtCount, fmtDate,
  moneynessLabel,
  CycField, NumInput, HeroNumInput, Seg, Tile, PullFromSunnyfi,
} from "../cycle";

export interface PCState extends Record<string, unknown> {
  underlying: string;
  mode: "held" | "buy";
  shares: string;
  contracts: string;
  price: string;
  premium: string;
  strike: string;
  frequency: string;
  horizon: string;
  customDate: string;
}

export const pcInitial: PCState = {
  underlying: "SPY",
  mode: "held",
  shares: "500",
  contracts: "5",
  price: "655.06",
  premium: "4.20",
  strike: "640.00",
  frequency: "monthly",
  horizon: "year",
  customDate: "",
};

interface Computed {
  contracts: number;
  costPerCycle: number;
  cycles: number;
  days: number;
  years: number;
  totalCost: number;
  notional: number;
  annualCost: number;
  annCostPct: number;
  coveragePct: number;
  coveredShares: number;
  horizonDate: Date | null;
  moneyness: number;
}

export function computePC(state: PCState, now: Date = new Date()): Computed {
  const shares    = Number(state.shares);
  const price     = Number(state.price);
  const premium   = Number(state.premium);
  const strike    = Number(state.strike);
  const contracts = Number(state.contracts);
  const validShares    = state.shares    !== "" && isFinite(shares)    && shares > 0;
  const validPrice     = state.price     !== "" && isFinite(price)     && price > 0;
  const validPrem      = state.premium   !== "" && isFinite(premium)   && premium >= 0;
  const validStrike    = state.strike    !== "" && isFinite(strike)    && strike > 0;
  const validContracts = state.contracts !== "" && isFinite(contracts) && contracts >= 0;

  const costPerCycle = validContracts && validPrem ? contracts * premium * 100 : NaN;
  const horizonDate  = resolveHorizon(state.horizon, state.customDate, now);
  const { cycles, days, years } = cycleStats(state.frequency, horizonDate, now);
  const totalCost = isFinite(cycles) && isFinite(costPerCycle) ? cycles * costPerCycle : NaN;
  const notional  = validShares && validPrice ? shares * price : NaN;

  let annualCost = NaN;
  if (isFinite(cycles) && isFinite(costPerCycle) && isFinite(years) && years > 0) {
    annualCost = (cycles * costPerCycle) / years;
  }
  const annCostPct = isFinite(annualCost) && isFinite(notional) && notional > 0
    ? (annualCost / notional) * 100 : NaN;

  const coveredShares = validContracts ? contracts * 100 : NaN;
  const coveragePct   = validShares && isFinite(coveredShares) ? (coveredShares / shares) * 100 : NaN;
  const moneyness     = validStrike && validPrice ? ((strike - price) / price) * 100 : NaN;

  return {
    contracts, costPerCycle, cycles, days, years, totalCost, notional,
    annualCost, annCostPct, coveragePct, coveredShares, horizonDate, moneyness,
  };
}

// ── Registry helpers ─────────────────────────────────────────────
export function pcCopy(state: PCState): string {
  const c = computePC(state);
  return `${state.underlying} · ${state.mode === "held" ? "Held" : "Planning to buy"} · ${fmtCount(Number(state.shares))} sh × ${fmtMoney(Number(state.price))} · put ${fmtMoney(Number(state.premium))} strike ${fmtMoney(Number(state.strike))} × ${fmtCount(c.cycles)} cycles to ${fmtDate(c.horizonDate)} = ${fmtMoney(c.totalCost)} total (${fmtPct(c.annCostPct)} of notional ann.)`;
}

export function pcDisplay(state: PCState): { value: string; tone: "neon" | "pos" | "neg" | "muted" } {
  const c = computePC(state);
  if (!isFinite(c.totalCost)) return { value: "—", tone: "muted" };
  return { value: fmtMoney(c.totalCost), tone: c.totalCost > 0 ? "neg" : "muted" };
}

export function pcFields(state: PCState): Array<{ label: string; value: string; mono?: boolean }> {
  const c = computePC(state);
  return [
    { label: "Underlying",       value: state.underlying || "—", mono: true },
    { label: "Shares × Price",   value: `${fmtCount(Number(state.shares))} × ${fmtMoney(Number(state.price))}`, mono: true },
    { label: "Premium · Strike", value: `${fmtMoney(Number(state.premium))} · ${fmtMoney(Number(state.strike))}`, mono: true },
    { label: "Cycles · Horizon", value: `${fmtCount(c.cycles)} · ${fmtDate(c.horizonDate)}`, mono: true },
    { label: "Total cost",       value: fmtMoney(c.totalCost), mono: true },
    { label: "Coverage",         value: fmtPct(c.coveragePct, { decimals: 1 }), mono: true },
  ];
}

// ── Body ─────────────────────────────────────────────────────────
export function PutCostCalc({
  state,
  setState,
}: {
  state: PCState;
  setState: (next: PCState | ((prev: PCState) => PCState)) => void;
}) {
  const set = <K extends keyof PCState>(k: K, v: PCState[K]) => setState({ ...state, [k]: v });
  const c = useMemo(() => computePC(state), [state]);
  const freq = FREQ_BY_ID[state.frequency] || FREQ_BY_ID.weekly;
  const tone: "neg" | "neutral" = isFinite(c.totalCost) && c.totalCost > 0 ? "neg" : "neutral";
  const money = moneynessLabel(state.strike, state.price);

  const helper: ReactNode = (() => {
    if (!isFinite(c.totalCost) || c.cycles === 0) {
      return <>Enter shares, current price, put premium, strike, frequency, and a horizon to see projected cost.</>;
    }
    return (
      <>
        <b>{fmtCount(c.cycles)}</b> cycle{c.cycles === 1 ? "" : "s"} between now and{" "}
        <b>{fmtDate(c.horizonDate)}</b> × <b>{fmtMoney(c.costPerCycle)}</b> per cycle ={" "}
        <b className="neg">{fmtMoney(c.totalCost)}</b> total
        {isFinite(c.annCostPct) ? <> (<b className="warn">{fmtPct(c.annCostPct)}</b> of notional annualised)</> : null}.
      </>
    );
  })();

  return (
    <div className="cyc">
      <p className="cyc-desc">
        Project the cost of protective puts. Pick a frequency, pick a horizon.
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

        <CycField label="Position mode">
          <Seg<"held" | "buy">
            options={[{ id: "held", label: "Held" }, { id: "buy", label: "Planning to buy" }]}
            value={state.mode}
            onChange={(v) => set("mode", v)}
            ariaLabel="Position mode"
          />
        </CycField>

        <CycField label="Shares to protect">
          <NumInput value={state.shares} onChange={(v) => set("shares", v)} placeholder="0" ariaLabel="Shares to protect" />
        </CycField>

        <CycField label="Contracts">
          <NumInput
            value={state.contracts}
            onChange={(v) => set("contracts", v)}
            placeholder="0"
            ariaLabel="Contracts to buy"
            suffix={isFinite(c.coveredShares) ? `× 100 = ${fmtCount(c.coveredShares)} sh` : ""}
          />
        </CycField>

        <CycField label="Current price">
          <NumInput value={state.price} onChange={(v) => set("price", v)} placeholder="0.00" prefix="$" ariaLabel="Current price" />
        </CycField>
      </div>

      {/* Hero — put premium + strike */}
      <div className="cyc-section">
        <div className="cyc-hero two">
          <div className="cyc-hero-field">
            <div className="hf-label">Put premium per contract</div>
            <HeroNumInput value={state.premium} onChange={(v) => set("premium", v)} placeholder="0.00" prefix="$" ariaLabel="Put premium per contract" />
            <div className="cyc-hero-sub">
              Cost per cycle = <span className="accent">{fmtCount(Number(state.contracts) || 0)} contracts × {fmtMoney(Number(state.premium) || 0)} × 100</span> = <span className="accent">{fmtMoney(c.costPerCycle)}</span>
            </div>
          </div>
          <div className="cyc-hero-field">
            <div className="hf-label">Strike</div>
            <HeroNumInput value={state.strike} onChange={(v) => set("strike", v)} placeholder="0.00" prefix="$" ariaLabel="Strike" muted />
            <div className="cyc-hero-sub">
              {money ? <span className="accent">{money}</span> : <>Set a strike to see moneyness</>}
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
            <div className="hf-label">Horizon</div>
            <Seg
              options={HORIZON_DEFS.map(h => ({ id: h.id, label: h.label }))}
              value={state.horizon}
              onChange={(v) => set("horizon", v)}
              ariaLabel="Horizon"
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
        <Tile label="Cost per cycle"          value={fmtMoney(c.costPerCycle)} tone={tone} />
        <Tile label="Cycles until horizon"    value={fmtCount(c.cycles)}       mono />
        <Tile label="Total cost to horizon"   value={fmtMoney(c.totalCost)}    tone={tone} primary />
        <Tile label="Annualised cost"         value={fmtPct(c.annCostPct)}     tone="warn" sub="% of notional" />
        <Tile
          label="Coverage"
          value={fmtPct(c.coveragePct, { decimals: 1 })}
          tone={isFinite(c.coveragePct) && c.coveragePct >= 100 ? "pos" : "neutral"}
          sub={isFinite(c.coveredShares) ? `${fmtCount(c.coveredShares)} / ${fmtCount(Number(state.shares) || 0)} shares` : "of position"}
        />
      </div>

      <div className="cyc-helper">{helper}</div>
    </div>
  );
}
