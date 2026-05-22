/**
 * Income vs Cost — combine covered-call income and protective-put cost.
 *
 * Two-side panel layout (calls left, puts right) with independent contracts,
 * premium, strike, and frequency for each side. A single shared horizon
 * drives both. Five result tiles plus a stacked bar visualisation of
 * income vs cost.
 */
import { useMemo, type ReactNode } from "react";
import {
  CALL_FREQ_DEFS, PUT_FREQ_DEFS, FREQ_BY_ID, PUT_HORIZON_DEFS,
  cycleStats, resolveHorizon,
  fmtMoney, fmtPct, fmtCount, fmtDate,
  moneynessLabel,
  CycField, NumInput, HeroNumInput, Seg, Tile, PullFromSunnyfi,
} from "../cycle";

export interface IVCState extends Record<string, unknown> {
  underlying: string;
  shares: string;
  price: string;

  callContracts: string;
  callPremium: string;
  callDistance: string;
  callFrequency: string;

  putContracts: string;
  putPremium: string;
  strike: string;
  putFrequency: string;

  horizon: string;
  customDate: string;
}

export const ivcInitial: IVCState = {
  underlying: "SPY",
  shares: "500",
  price: "655.06",

  callContracts: "5",
  callPremium: "2.80",
  callDistance: "1.0",
  callFrequency: "weekly",

  putContracts: "5",
  putPremium: "4.20",
  strike: "640.00",
  putFrequency: "monthly",

  horizon: "rolling",
  customDate: "",
};

interface Computed {
  callContracts: number;
  putContracts: number;
  notional: number;
  callCovered: number;
  putCovered: number;
  incomePerCycle: number;
  totalIncome: number;
  costPerCycle: number;
  totalCost: number;
  net: number;
  coverage: number;
  annualNet: number;
  netAnnYieldPct: number;
  breakevenCallPrem: number;
  daysToFundOnePut: number;
  horizonDate: Date | null;
  days: number;
  years: number;
  callCycles: number;
  putCycles: number;
  moneyness: number;
  impliedCallStrike: number;
}

export function computeIVC(state: IVCState, now: Date = new Date()): Computed {
  const shares    = Number(state.shares);
  const price     = Number(state.price);
  const callPrem  = Number(state.callPremium);
  const callDist  = Number(state.callDistance);
  const putPrem   = Number(state.putPremium);
  const strike    = Number(state.strike);
  const callContracts = Number(state.callContracts);
  const putContracts  = Number(state.putContracts);

  const validShares    = state.shares    !== "" && isFinite(shares)    && shares > 0;
  const validPrice     = state.price     !== "" && isFinite(price)     && price > 0;
  const validCallPrem  = state.callPremium  !== "" && isFinite(callPrem) && callPrem >= 0;
  const validCallDist  = state.callDistance !== "" && isFinite(callDist);
  const validPutPrem   = state.putPremium   !== "" && isFinite(putPrem)  && putPrem >= 0;
  const validStrike    = state.strike       !== "" && isFinite(strike)   && strike > 0;
  const validCallContracts = state.callContracts !== "" && isFinite(callContracts) && callContracts >= 0;
  const validPutContracts  = state.putContracts  !== "" && isFinite(putContracts)  && putContracts >= 0;

  const notional = validShares && validPrice ? shares * price : NaN;
  const callCovered = validCallContracts ? callContracts * 100 : NaN;
  const putCovered  = validPutContracts  ? putContracts  * 100 : NaN;
  const impliedCallStrike = validPrice && validCallDist ? price * (1 + callDist / 100) : NaN;

  const horizonDate = resolveHorizon(state.horizon, state.customDate, now);
  const callStats = cycleStats(state.callFrequency, horizonDate, now);
  const putStats  = cycleStats(state.putFrequency,  horizonDate, now);
  const years = callStats.years;
  const days  = callStats.days;

  const incomePerCycle = validCallContracts && validCallPrem ? callContracts * callPrem * 100 : NaN;
  const totalIncome = isFinite(incomePerCycle) && isFinite(callStats.cycles) ? incomePerCycle * callStats.cycles : NaN;

  const costPerCycle = validPutContracts && validPutPrem ? putContracts * putPrem * 100 : NaN;
  const totalCost = isFinite(costPerCycle) && isFinite(putStats.cycles) ? costPerCycle * putStats.cycles : NaN;

  const net = isFinite(totalIncome) && isFinite(totalCost) ? totalIncome - totalCost : NaN;

  let coverage: number;
  if (isFinite(totalIncome) && isFinite(totalCost) && totalCost > 0) coverage = totalIncome / totalCost;
  else if (totalCost === 0 && isFinite(totalIncome) && totalIncome > 0) coverage = Infinity;
  else coverage = NaN;

  let annualNet = NaN;
  if (isFinite(net) && isFinite(years) && years > 0) annualNet = net / years;
  const netAnnYieldPct = isFinite(annualNet) && isFinite(notional) && notional > 0 ? (annualNet / notional) * 100 : NaN;

  const breakevenCallPrem =
    isFinite(totalCost) && validCallContracts && callContracts > 0 && isFinite(callStats.cycles) && callStats.cycles > 0
      ? totalCost / (callContracts * callStats.cycles * 100)
      : NaN;

  const callFreq = FREQ_BY_ID[state.callFrequency];
  const daysToFundOnePut = isFinite(costPerCycle) && isFinite(incomePerCycle) && incomePerCycle > 0 && callFreq
    ? (costPerCycle / incomePerCycle) * callFreq.calDays
    : NaN;

  const moneyness = validStrike && validPrice ? ((strike - price) / price) * 100 : NaN;

  return {
    callContracts, putContracts, notional, callCovered, putCovered,
    incomePerCycle, totalIncome, costPerCycle, totalCost,
    net, coverage, annualNet, netAnnYieldPct,
    breakevenCallPrem, daysToFundOnePut,
    horizonDate, days, years,
    callCycles: callStats.cycles, putCycles: putStats.cycles,
    moneyness, impliedCallStrike,
  };
}

// ── Registry helpers ─────────────────────────────────────────────
function fmtCoverage(n: number): string {
  if (!isFinite(n)) return "—";
  if (n === Infinity) return "∞";
  return `${n.toFixed(2)}x`;
}
function fmtDays(n: number): string {
  if (!isFinite(n)) return "—";
  if (n < 1) return `${(n * 24).toFixed(1)} hrs`;
  return `${n.toFixed(1)} days`;
}

export function ivcCopy(state: IVCState): string {
  const c = computeIVC(state);
  const incomeFmt = isFinite(c.totalIncome) ? `+${fmtMoney(c.totalIncome).replace(/^[+−]?/, "")}` : "—";
  const costFmt   = isFinite(c.totalCost)   ? `−${fmtMoney(c.totalCost).replace(/^[+−]?/, "")}`   : "—";
  const netFmt    = fmtMoney(c.net, { signed: true });
  return `${state.underlying} ${fmtCount(Number(state.shares))}sh: ${incomeFmt} calls / ${costFmt} puts = ${netFmt} net (${fmtCoverage(c.coverage)} coverage, ${fmtPct(c.netAnnYieldPct)} annualised) through ${fmtDate(c.horizonDate)}`;
}

export function ivcDisplay(state: IVCState): { value: string; tone: "neon" | "pos" | "neg" | "muted" } {
  const c = computeIVC(state);
  if (!isFinite(c.net)) return { value: "—", tone: "muted" };
  return {
    value: fmtMoney(c.net, { signed: true }),
    tone: c.net > 0 ? "pos" : c.net < 0 ? "neg" : "neon",
  };
}

export function ivcFields(state: IVCState): Array<{ label: string; value: string; mono?: boolean }> {
  const c = computeIVC(state);
  return [
    { label: "Underlying",     value: state.underlying || "—", mono: true },
    { label: "Shares · Price", value: `${fmtCount(Number(state.shares))} · ${fmtMoney(Number(state.price))}`, mono: true },
    { label: "Total income",   value: fmtMoney(c.totalIncome), mono: true },
    { label: "Total cost",     value: fmtMoney(c.totalCost), mono: true },
    { label: "Coverage",       value: fmtCoverage(c.coverage), mono: true },
    { label: "Through",        value: fmtDate(c.horizonDate), mono: true },
  ];
}

// ── Body ─────────────────────────────────────────────────────────
export function IncomeVsCostCalc({
  state,
  setState,
}: {
  state: IVCState;
  setState: (next: IVCState | ((prev: IVCState) => IVCState)) => void;
}) {
  const set = <K extends keyof IVCState>(k: K, v: IVCState[K]) => setState({ ...state, [k]: v });
  const c = useMemo(() => computeIVC(state), [state]);
  const callFreq = FREQ_BY_ID[state.callFrequency] || FREQ_BY_ID.weekly;
  const putFreq  = FREQ_BY_ID[state.putFrequency]  || FREQ_BY_ID.monthly;

  const netTone: "pos" | "neg" | "neutral" = !isFinite(c.net) ? "neutral" : c.net > 0 ? "pos" : c.net < 0 ? "neg" : "neutral";
  const coverageTone: "pos" | "warn" | "neutral" = !isFinite(c.coverage) ? "neutral" : c.coverage >= 1 ? "pos" : "warn";
  const money = moneynessLabel(state.strike, state.price);

  const helper: ReactNode = (() => {
    if (!isFinite(c.net) || (c.callCycles === 0 && c.putCycles === 0)) {
      return <>Fill in shares, price, call &amp; put premiums, frequencies, and a horizon to see net economics.</>;
    }
    return (
      <>
        To <b>{fmtDate(c.horizonDate)}</b> ({c.days} days):{" "}
        <b className="pos">+{fmtMoney(c.totalIncome).replace(/^[+−]?/, "")}</b> calls,{" "}
        <b className="neg">−{fmtMoney(c.totalCost).replace(/^[+−]?/, "")}</b> puts ={" "}
        <b className={netTone}>{fmtMoney(c.net, { signed: true })}</b> net (
        <b className={coverageTone}>{fmtCoverage(c.coverage)}</b> coverage,{" "}
        <b className="neon">{fmtPct(c.netAnnYieldPct)}</b> annualised).
      </>
    );
  })();

  // Stacked bar — scale to max(income, cost)
  const barMax = Math.max(isFinite(c.totalIncome) ? c.totalIncome : 0, isFinite(c.totalCost) ? c.totalCost : 0) || 1;
  const incomePct = isFinite(c.totalIncome) ? Math.min(100, (c.totalIncome / barMax) * 100) : 0;
  const costPct   = isFinite(c.totalCost)   ? Math.min(100, (c.totalCost   / barMax) * 100) : 0;

  return (
    <div className="cyc">
      <p className="cyc-desc">
        Net economics of running covered calls and protective puts together. Pick frequencies, pick a horizon, see if the structure pays for itself.
      </p>

      {/* Position context — shares spans 2 cols so Current price aligns
          with the same column position as Put Cost / Expected Income. */}
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
                // Snap the put strike to the nearest whole dollar — reads as
                // a realistic strike vs the raw quote (HOOD $73.46 → $74).
                strike: Math.round(price).toFixed(2),
                ...(shares ? { shares: String(shares) } : {}),
              })
            }
          />
        </CycField>
        <CycField label="Shares" span={2}>
          <NumInput value={state.shares} onChange={(v) => set("shares", v)} placeholder="0" ariaLabel="Shares" />
        </CycField>
        <CycField label="Current price">
          <NumInput value={state.price} onChange={(v) => set("price", v)} placeholder="0.00" prefix="$" ariaLabel="Current price" />
        </CycField>
      </div>

      {/* Two-side */}
      <div className="cyc-section">
        <div className="cyc-twoside">
          {/* CALL */}
          <div className="cyc-side calls">
            <div className="cyc-side-head">
              <div className="cyc-side-title">Call side · sell to open</div>
              <div className="cyc-side-meta">{isFinite(c.callCycles) ? `${fmtCount(c.callCycles)} cycles` : ""}</div>
            </div>
            <div className="cyc-side-contracts">
              <div className="hf-label">Contracts</div>
              <input
                type="text"
                inputMode="numeric"
                value={state.callContracts}
                onChange={(e) => set("callContracts", e.target.value)}
                placeholder="0"
                spellCheck={false}
                aria-label="Call contracts"
              />
              <span className="meta">× 100 = {fmtCount(c.callCovered)} sh</span>
            </div>
            <div className="cyc-side-hero">
              <div className="hf-label">Premium per contract</div>
              <HeroNumInput value={state.callPremium} onChange={(v) => set("callPremium", v)} placeholder="0.00" prefix="$" ariaLabel="Call premium per contract" />
              <div className="cyc-side-sub">
                Income / cycle = <span className="accent">{fmtCount(Number(state.callContracts) || 0)} × {fmtMoney(Number(state.callPremium) || 0)} × 100</span> = <span className="accent">{fmtMoney(c.incomePerCycle)}</span>
              </div>
            </div>
            <div className="cyc-side-strike">
              <div className="hf-label">Strike distance · OTM</div>
              <div className="cyc-strike-row">
                <input
                  className="cyc-strike-input"
                  type="text"
                  inputMode="decimal"
                  value={state.callDistance}
                  onChange={(e) => set("callDistance", e.target.value)}
                  placeholder="0.0"
                  spellCheck={false}
                  aria-label="Call strike distance OTM"
                />
                <span className="cyc-prefix">%</span>
              </div>
              <div className="cyc-side-sub">
                {isFinite(c.impliedCallStrike)
                  ? <>Implied strike <span className="accent">{fmtMoney(c.impliedCallStrike)}</span></>
                  : <>Set a distance to see implied strike</>}
              </div>
            </div>
            <div className="cyc-side-freq">
              <div className="hf-label">Frequency</div>
              <Seg
                options={CALL_FREQ_DEFS.map(f => ({ id: f.id, label: f.label }))}
                value={state.callFrequency}
                onChange={(v) => set("callFrequency", v)}
                ariaLabel="Call frequency"
              />
              <div className="cyc-side-sub">
                <span className="accent">{callFreq.label}</span> · ~{callFreq.perYear} cycles/year
              </div>
            </div>
          </div>

          {/* PUT */}
          <div className="cyc-side puts">
            <div className="cyc-side-head">
              <div className="cyc-side-title">Put side · buy to open</div>
              <div className="cyc-side-meta">{isFinite(c.putCycles) ? `${fmtCount(c.putCycles)} cycles` : ""}</div>
            </div>
            <div className="cyc-side-contracts">
              <div className="hf-label">Contracts</div>
              <input
                type="text"
                inputMode="numeric"
                value={state.putContracts}
                onChange={(e) => set("putContracts", e.target.value)}
                placeholder="0"
                spellCheck={false}
                aria-label="Put contracts"
              />
              <span className="meta">× 100 = {fmtCount(c.putCovered)} sh</span>
            </div>
            <div className="cyc-side-hero">
              <div className="hf-label">Premium per contract</div>
              <HeroNumInput value={state.putPremium} onChange={(v) => set("putPremium", v)} placeholder="0.00" prefix="$" ariaLabel="Put premium per contract" />
              <div className="cyc-side-sub">
                Cost / cycle = <span className="accent">{fmtCount(Number(state.putContracts) || 0)} × {fmtMoney(Number(state.putPremium) || 0)} × 100</span> = <span className="accent">{fmtMoney(c.costPerCycle)}</span>
              </div>
            </div>
            <div className="cyc-side-strike">
              <div className="hf-label">Strike</div>
              <div className="cyc-strike-row">
                <span className="cyc-prefix">$</span>
                <input
                  className="cyc-strike-input"
                  type="text"
                  inputMode="decimal"
                  value={state.strike}
                  onChange={(e) => set("strike", e.target.value)}
                  placeholder="0.00"
                  spellCheck={false}
                  aria-label="Put strike"
                />
              </div>
              <div className="cyc-side-sub">
                {money ? <span className="accent">{money}</span> : <>Set a strike to see moneyness</>}
              </div>
            </div>
            <div className="cyc-side-freq">
              <div className="hf-label">Frequency</div>
              <Seg
                options={PUT_FREQ_DEFS.map(f => ({ id: f.id, label: f.label }))}
                value={state.putFrequency}
                onChange={(v) => set("putFrequency", v)}
                ariaLabel="Put frequency"
              />
              <div className="cyc-side-sub">
                <span className="accent">{putFreq.label}</span> · ~{putFreq.perYear} cycles/year
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Shared cut off */}
      <div className="cyc-section">
        <div className="cyc-horizon-only">
          <div className="hf-label">Cut off</div>
          <Seg
            options={PUT_HORIZON_DEFS.map(h => ({ id: h.id, label: h.label }))}
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
            {isFinite(c.days) && <> · <span className="accent">{c.days}</span> days · <span className="accent">{fmtCount(c.callCycles)}</span> call cycles · <span className="accent">{fmtCount(c.putCycles)}</span> put cycles</>}
          </div>
        </div>
      </div>

      {/* Results */}
      <div className="cyc-results">
        <Tile label="Net to horizon"        value={isFinite(c.net) ? fmtMoney(c.net, { signed: true }) : "—"} tone={netTone} />
        <Tile label="Coverage ratio"        value={fmtCoverage(c.coverage)} sub="income ÷ cost" tone={coverageTone} primary />
        <Tile label="Net annualised yield"  value={fmtPct(c.netAnnYieldPct)} tone={netTone === "neg" ? "neg" : "neon"} sub="net ÷ notional, ann." />
        <Tile label="Breakeven call premium" value={fmtMoney(c.breakevenCallPrem)} mono sub="to fully fund puts" />
        <Tile label="Days of calls"         value={fmtDays(c.daysToFundOnePut)} mono sub="to fund one put cycle" />
      </div>

      <div className="cyc-helper">{helper}</div>

      {/* Stacked bar */}
      <div className="cyc-bar-wrap">
        <div className="cyc-bar-legend">
          <span><span className="swatch income" />Income {fmtMoney(c.totalIncome)}</span>
          <span><span className="swatch cost" />Cost {fmtMoney(c.totalCost)}</span>
          <span className="spacer" />
          <span>Net <span className={`net ${netTone}`}>{isFinite(c.net) ? fmtMoney(c.net, { signed: true }) : "—"}</span></span>
        </div>
        <div className="cyc-bar-track" aria-hidden>
          <div className="cyc-bar-row">
            <div className="cyc-bar-seg income" style={{ width: `${incomePct}%` }}>
              {incomePct > 18 ? fmtMoney(c.totalIncome) : ""}
            </div>
            <span className="cyc-bar-row-label">Income</span>
          </div>
          <div className="cyc-bar-row">
            <div className="cyc-bar-seg cost" style={{ width: `${costPct}%` }}>
              {costPct > 18 ? `−${fmtMoney(c.totalCost).replace(/^[+−]?/, "")}` : ""}
            </div>
            <span className="cyc-bar-row-label">Cost</span>
          </div>
          {isFinite(c.net) && c.net !== 0 && incomePct > 0 && costPct > 0 && (
            <div
              className="cyc-bar-marker"
              style={{ left: `calc(${Math.min(incomePct, costPct)}% + 4px)` }}
              data-label={`${c.net > 0 ? "surplus" : "shortfall"} ${fmtMoney(Math.abs(c.net))}`}
            />
          )}
        </div>
      </div>
    </div>
  );
}
