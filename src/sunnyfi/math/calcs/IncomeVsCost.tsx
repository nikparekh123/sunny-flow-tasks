/**
 * Income vs Cost — combine covered-call income and protective-put cost.
 *
 * Two-side panel layout (calls left, puts right) with independent contracts,
 * premium, strike, and frequency for each side. A single shared horizon
 * drives both. Five result tiles plus a stacked bar visualisation of
 * income vs cost.
 */
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  FREQ_DEFS, PUT_FREQ_DEFS, FREQ_BY_ID,
  cycleStats,
  fmtMoney, fmtPct, fmtCount, fmtDate,
  moneynessLabel,
  CycField, NumInput, HeroNumInput, Seg, Tile, PullFromSunnyfi,
} from "../cycle";
import { usePremiumAutofill } from "../usePremiumAutofill";
import { availableCadenceIds, pullOptionChain, type OptionContractQuote } from "../quote";

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
  /** Absolute put strike $. Linked to putDistance — editing either updates
   *  the other based on the current price. */
  strike: string;
  /** Distance % from spot. Positive number; pair with putDistanceDir to
   *  signal which side (puts most often "below spot" / OTM). */
  putDistance: string;
  putDistanceDir: "below" | "above";
  putFrequency: string;
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
  putDistance: "2.30",       // (655.06 − 640) / 655.06 ≈ 2.30% below spot
  putDistanceDir: "below",
  putFrequency: "monthly",
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

  // Horizon = one put cycle out. "How does the strategy stack up across one
  // full hedge period?" — eliminates the separate cut-off control.
  const putFreqDef = FREQ_BY_ID[state.putFrequency];
  const horizonDate = putFreqDef
    ? new Date(now.getTime() + putFreqDef.calDays * 86400000)
    : null;
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

/** Upsert by ticker — one card per ticker per calc in the Compare view. */
export function ivcUpsertKey(state: IVCState): string | null {
  return state.underlying?.trim().toUpperCase() || null;
}

/** Compare-view ranking: net annualised yield (net dollars ÷ notional, ann.).
 *  Apples-to-apples across stocks of different position sizes. Higher = better. */
export function ivcRank(state: IVCState): { score: number; label: string } | null {
  const c = computeIVC(state);
  if (!isFinite(c.netAnnYieldPct)) return null;
  return { score: c.netAnnYieldPct, label: "net ann. yield" };
}

export function ivcCardLine(state: IVCState): string {
  const c = computeIVC(state);
  const cov = fmtCoverage(c.coverage);
  return `${fmtCount(Number(state.shares))} sh × ${fmtMoney(Number(state.price))} · ${cov} coverage`;
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

  // ── Premium auto-fill ────────────────────────────────────────
  // Polygon supplies the premium for the user's chosen cadence so they
  // don't have to look it up. User can override either side by typing
  // directly — overrides hold until the ticker or strike/distance
  // changes (since those imply a new option contract).
  const [callPremManual, setCallPremManual] = useState(false);
  const [putPremManual, setPutPremManual]   = useState(false);
  useEffect(() => { setCallPremManual(false); }, [state.underlying, state.callDistance]);
  useEffect(() => { setPutPremManual(false);  }, [state.underlying, state.strike]);

  // ── Put-strike linked inputs ─────────────────────────────────
  // Distance % and $ strike are two views of the same thing. Edit either
  // and the other updates from the current price. When price changes (e.g.
  // user pulls a new ticker), recompute the field the user *didn't* last
  // edit so their intent survives.
  const lastEditedStrike = useRef<"distance" | "strike">("distance");

  const computeStrikeFromDistance = (
    distStr: string,
    dir: "below" | "above",
    priceStr: string,
  ): string => {
    const dist = Number(distStr);
    const price = Number(priceStr);
    if (!isFinite(dist) || !isFinite(price) || price <= 0) return "";
    const factor = dir === "below" ? -1 : 1;
    return (price * (1 + (factor * dist) / 100)).toFixed(2);
  };
  const computeDistanceFromStrike = (
    strikeStr: string,
    priceStr: string,
  ): { dist: string; dir: "below" | "above" } => {
    const strike = Number(strikeStr);
    const price = Number(priceStr);
    if (!isFinite(strike) || !isFinite(price) || price <= 0) return { dist: "", dir: "below" };
    const pct = ((strike - price) / price) * 100;
    return { dist: Math.abs(pct).toFixed(2), dir: pct >= 0 ? "above" : "below" };
  };

  const setPutDistance = (v: string) => {
    lastEditedStrike.current = "distance";
    setState((p) => ({
      ...p,
      putDistance: v,
      strike: computeStrikeFromDistance(v, p.putDistanceDir, p.price) || p.strike,
    }));
  };
  const togglePutDistanceDir = () => {
    lastEditedStrike.current = "distance";
    setState((p) => {
      const newDir: "below" | "above" = p.putDistanceDir === "below" ? "above" : "below";
      return {
        ...p,
        putDistanceDir: newDir,
        strike: computeStrikeFromDistance(p.putDistance, newDir, p.price) || p.strike,
      };
    });
  };
  const setPutStrikeDollars = (v: string) => {
    lastEditedStrike.current = "strike";
    setState((p) => {
      const { dist, dir } = computeDistanceFromStrike(v, p.price);
      return { ...p, strike: v, putDistance: dist || p.putDistance, putDistanceDir: dir };
    });
  };

  // Lightweight chain peek for smart-frequency filtering. Single fetch per
  // ticker/strike/type triple, debounced so it doesn't run on every keystroke.
  // The result feeds two filters: putAvailable and callAvailable below.
  const [putChain, setPutChain] = useState<OptionContractQuote[]>([]);
  const [callChain, setCallChain] = useState<OptionContractQuote[]>([]);
  useEffect(() => {
    if (!state.underlying || !isFinite(Number(state.strike)) || Number(state.strike) <= 0) return;
    const ctrl = new AbortController();
    const id = window.setTimeout(() => {
      pullOptionChain(state.underlying, Number(state.strike), "put")
        .then((c) => { if (!ctrl.signal.aborted) setPutChain(c); })
        .catch(() => { /* ignore — autofill handles error surfacing */ });
    }, 500);
    return () => { ctrl.abort(); window.clearTimeout(id); };
  }, [state.underlying, state.strike]);
  useEffect(() => {
    const implStrike = Number(state.price) * (1 + Number(state.callDistance) / 100);
    if (!state.underlying || !isFinite(implStrike) || implStrike <= 0) return;
    const ctrl = new AbortController();
    const id = window.setTimeout(() => {
      pullOptionChain(state.underlying, implStrike, "call")
        .then((c) => { if (!ctrl.signal.aborted) setCallChain(c); })
        .catch(() => { /* ignore */ });
    }, 500);
    return () => { ctrl.abort(); window.clearTimeout(id); };
  }, [state.underlying, state.price, state.callDistance]);

  const callAvailable = useMemo(
    () => callChain.length === 0
      ? null  // null = no chain data yet → show all (don't punish first paint)
      : availableCadenceIds(callChain, FREQ_DEFS),
    [callChain],
  );
  const putAvailable = useMemo(
    () => putChain.length === 0
      ? null
      : availableCadenceIds(putChain, PUT_FREQ_DEFS),
    [putChain],
  );

  // Auto-fallback: if user's selected cadence isn't available, pick the
  // closest viable one so the seg doesn't show "no active button".
  useEffect(() => {
    if (callAvailable && !callAvailable.has(state.callFrequency)) {
      const fallback = FREQ_DEFS.find((f) => callAvailable.has(f.id));
      if (fallback) setState((p) => ({ ...p, callFrequency: fallback.id }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [callAvailable]);
  useEffect(() => {
    if (putAvailable && !putAvailable.has(state.putFrequency)) {
      const fallback = PUT_FREQ_DEFS.find((f) => putAvailable.has(f.id));
      if (fallback) setState((p) => ({ ...p, putFrequency: fallback.id }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [putAvailable]);

  // When price changes (e.g. ticker pull), keep whichever side the user
  // last edited and recompute the other one.
  useEffect(() => {
    setState((p) => {
      const price = Number(p.price);
      if (!isFinite(price) || price <= 0) return p;
      if (lastEditedStrike.current === "distance") {
        const ns = computeStrikeFromDistance(p.putDistance, p.putDistanceDir, p.price);
        return ns && ns !== p.strike ? { ...p, strike: ns } : p;
      } else {
        const { dist, dir } = computeDistanceFromStrike(p.strike, p.price);
        if (!dist) return p;
        if (dist === p.putDistance && dir === p.putDistanceDir) return p;
        return { ...p, putDistance: dist, putDistanceDir: dir };
      }
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.price]);

  const callFill = usePremiumAutofill({
    ticker: state.underlying,
    strike: isFinite(c.impliedCallStrike) ? c.impliedCallStrike : NaN,
    cadenceDays: callFreq.calDays,
    contractType: "call",
    setPremium: (v) => setState((p) => ({ ...p, callPremium: v })),
    isOverridden: callPremManual,
  });
  const putFill = usePremiumAutofill({
    ticker: state.underlying,
    strike: Number(state.strike),
    cadenceDays: putFreq.calDays,
    contractType: "put",
    setPremium: (v) => setState((p) => ({ ...p, putPremium: v })),
    isOverridden: putPremManual,
  });

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
              <div className="hf-label">
                Premium per contract
                <AutofillBadge status={callFill.status} msg={callFill.msg} />
              </div>
              <HeroNumInput
                value={state.callPremium}
                onChange={(v) => { setCallPremManual(true); set("callPremium", v); }}
                placeholder="0.00" prefix="$" ariaLabel="Call premium per contract"
              />
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
                options={FREQ_DEFS
                  .filter((f) => !callAvailable || callAvailable.has(f.id))
                  .map(f => ({ id: f.id, label: f.label }))}
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
              <div className="hf-label">
                Premium per contract
                <AutofillBadge status={putFill.status} msg={putFill.msg} />
              </div>
              <HeroNumInput
                value={state.putPremium}
                onChange={(v) => { setPutPremManual(true); set("putPremium", v); }}
                placeholder="0.00" prefix="$" ariaLabel="Put premium per contract"
              />
              <div className="cyc-side-sub">
                Cost / cycle = <span className="accent">{fmtCount(Number(state.putContracts) || 0)} × {fmtMoney(Number(state.putPremium) || 0)} × 100</span> = <span className="accent">{fmtMoney(c.costPerCycle)}</span>
              </div>
            </div>
            <div className="cyc-side-strike">
              <div className="hf-label">Strike</div>
              <div className="put-strike-twin">
                <div className="put-strike-cell">
                  <div className="cyc-strike-row">
                    <input
                      className="cyc-strike-input"
                      type="text"
                      inputMode="decimal"
                      value={state.putDistance}
                      onChange={(e) => setPutDistance(e.target.value)}
                      placeholder="0.0"
                      spellCheck={false}
                      aria-label="Put strike distance percent"
                    />
                    <span className="cyc-prefix">%</span>
                  </div>
                  <button
                    type="button"
                    className={`put-strike-dir ${state.putDistanceDir}`}
                    onClick={togglePutDistanceDir}
                    title="Toggle below / above spot"
                  >
                    {state.putDistanceDir} spot
                  </button>
                </div>
                <div className="put-strike-cell">
                  <div className="cyc-strike-row">
                    <span className="cyc-prefix">$</span>
                    <input
                      className="cyc-strike-input"
                      type="text"
                      inputMode="decimal"
                      value={state.strike}
                      onChange={(e) => setPutStrikeDollars(e.target.value)}
                      placeholder="0.00"
                      spellCheck={false}
                      aria-label="Put strike dollars"
                    />
                  </div>
                  <div className="put-strike-aux">
                    {money ? money : "—"}
                  </div>
                </div>
              </div>
            </div>
            <div className="cyc-side-freq">
              <div className="hf-label">Frequency</div>
              <Seg
                options={PUT_FREQ_DEFS
                  .filter((f) => !putAvailable || putAvailable.has(f.id))
                  .map(f => ({ id: f.id, label: f.label }))}
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

// ── Autofill status badge ───────────────────────────────────────
// Tiny chip rendered next to the premium label showing whether the value
// is live from Polygon, being fetched, manually overridden, or unavailable.
function AutofillBadge({ status, msg }: { status: "idle" | "fetching" | "ok" | "err" | "overridden"; msg: string }) {
  if (status === "idle") return null;
  const label =
    status === "fetching"   ? "fetching…" :
    status === "ok"         ? `auto · ${msg}` :
    status === "overridden" ? "manual" :
                              `auto failed · ${msg}`;
  return <span className={`ivc-autofill ${status}`} title={msg || label}>{label}</span>;
}
