/**
 * Percentage Difference — the first real calculator.
 *
 * Pure body component: takes { state, setState }, renders the body, calls
 * setState on every input. Knows nothing about save/copy/reset — those live
 * on the host page (Math.tsx).
 *
 * State: { from, to, fromLabel, toLabel } — strings so "" → NaN edge case works.
 * Result:
 *   abs   = to - from
 *   pct   = (abs / from) * 100   (NaN when from === 0)
 *   mult  = to / from            (NaN when from === 0)
 *   tone  = pos | neg | neutral (white for zero/no-change)
 */
import { useMemo, type ReactNode } from "react";

export interface PctDiffState extends Record<string, unknown> {
  from: string;
  to: string;
  fromLabel: string;
  toLabel: string;
}

export const pctDiffInitial: PctDiffState = {
  from: "720",
  to: "750",
  fromLabel: "",
  toLabel: "",
};

// ── Formatters ───────────────────────────────────────────────────
function fmtAbs(n: number): string {
  if (!isFinite(n)) return "—";
  const sign = n < 0 ? "−" : n > 0 ? "+" : "";
  return `${sign}$${Math.abs(n).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
function fmtPct(n: number): string {
  if (!isFinite(n)) return "—";
  const sign = n < 0 ? "−" : n > 0 ? "+" : "";
  return `${sign}${Math.abs(n).toFixed(2)}%`;
}
function fmtMult(n: number): string {
  if (!isFinite(n)) return "—";
  return `${n.toFixed(2)}x`;
}
function fmtPlain(s: string | undefined | null): string {
  return (s ?? "").toString().trim() || "—";
}

interface Computed {
  abs: number;
  pct: number;
  mult: number;
  tone: "pos" | "neg" | "neutral";
}

export function computePD(state: PctDiffState): Computed {
  const f = Number(state.from);
  const t = Number(state.to);
  const validF = state.from !== "" && isFinite(f);
  const validT = state.to !== "" && isFinite(t);
  const abs = validF && validT ? t - f : NaN;
  const pct = validF && validT && f !== 0 ? (abs / f) * 100 : NaN;
  const mult = validF && validT && f !== 0 ? t / f : NaN;
  const tone: Computed["tone"] = !isFinite(abs) || abs === 0 ? "neutral" : abs > 0 ? "pos" : "neg";
  return { abs, pct, mult, tone };
}

// ── Copy-as-text + History display helpers (used by registry) ────
export function pctDiffCopy(state: PctDiffState): string {
  const c = computePD(state);
  const fLbl = state.fromLabel || "From";
  const tLbl = state.toLabel || "To";
  return `${fLbl} → ${tLbl}: ${state.from} → ${state.to} (${fmtPct(c.pct)}, ${fmtAbs(c.abs)}, ${fmtMult(c.mult)})`;
}

export function pctDiffDisplay(state: PctDiffState): { value: string; tone: "neon" | "pos" | "neg" | "muted" } {
  const c = computePD(state);
  if (!isFinite(c.pct)) return { value: "—", tone: "muted" };
  return {
    value: fmtPct(c.pct),
    tone: c.tone === "pos" ? "pos" : c.tone === "neg" ? "neg" : "neon",
  };
}

// ── Body ─────────────────────────────────────────────────────────
export function PercentageDifferenceCalc({
  state,
  setState,
}: {
  state: PctDiffState;
  setState: (next: PctDiffState | ((prev: PctDiffState) => PctDiffState)) => void;
}) {
  const { from, to, fromLabel, toLabel } = state;
  const set = <K extends keyof PctDiffState>(k: K, v: PctDiffState[K]) =>
    setState({ ...state, [k]: v });

  const computed = useMemo(() => computePD(state), [state]);

  const swap = () =>
    setState({
      ...state,
      from: to,
      to: from,
      fromLabel: toLabel,
      toLabel: fromLabel,
    });

  const helper: ReactNode = (() => {
    if (!isFinite(computed.abs)) {
      return <>Enter two numbers to see how they compare.</>;
    }
    if (computed.abs === 0) {
      return (
        <>
          <b>{fmtPlain(fromLabel || from)}</b> and <b>{fmtPlain(toLabel || to)}</b> are equal —
          <b className="neutral"> no change</b>.
        </>
      );
    }
    if (!isFinite(computed.pct)) {
      return <>From cannot be zero — multiple and percentage are undefined.</>;
    }
    const word = computed.abs > 0 ? "increase" : "decrease";
    return (
      <>
        Moving from <b>{fmtPlain(fromLabel || from)}</b> to <b>{fmtPlain(toLabel || to)}</b> is a{" "}
        <b className={computed.tone}>{fmtPct(computed.pct)}</b> {word}.
      </>
    );
  })();

  return (
    <div className="pdc">
      <p className="pdc-desc">
        Enter two numbers to see the absolute and percentage difference between them.
      </p>

      <div className="pdc-inputs">
        <NumField
          label="From"
          value={from}
          onChange={(v) => set("from", v)}
          subLabel={fromLabel}
          onSubLabelChange={(v) => set("fromLabel", v)}
          tone={computed.tone}
        />

        <button className="pdc-swap" onClick={swap} title="Flip direction">
          <span className="pdc-swap-icon">⇆</span>
          <span className="pdc-swap-label">flip</span>
        </button>

        <NumField
          label="To"
          value={to}
          onChange={(v) => set("to", v)}
          subLabel={toLabel}
          onSubLabelChange={(v) => set("toLabel", v)}
          tone={computed.tone}
          highlight
        />
      </div>

      <div className="pdc-results">
        <Tile label="Absolute difference"    value={fmtAbs(computed.abs)}  tone={computed.tone} />
        <Tile label="Percentage difference"  value={fmtPct(computed.pct)}  tone={computed.tone} primary />
        <Tile label="Multiple"               value={fmtMult(computed.mult)} tone="neutral" />
      </div>

      <div className="pdc-helper">{helper}</div>
    </div>
  );
}

function NumField({
  label,
  value,
  onChange,
  subLabel,
  onSubLabelChange,
  highlight,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  subLabel: string;
  onSubLabelChange: (v: string) => void;
  tone: Computed["tone"];
  highlight?: boolean;
}) {
  return (
    <div className="pdc-field">
      <div className="hf-label">{label}</div>
      <input
        className={`pdc-input ${highlight ? "highlight" : ""}`}
        type="text"
        inputMode="decimal"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        spellCheck={false}
        aria-label={label}
      />
      <input
        className="pdc-sublabel"
        placeholder="Optional label"
        value={subLabel}
        onChange={(e) => onSubLabelChange(e.target.value)}
        spellCheck={false}
        aria-label={`${label} label`}
      />
    </div>
  );
}

function Tile({ label, value, tone, primary }: { label: string; value: string; tone: Computed["tone"]; primary?: boolean }) {
  return (
    <div className={`pdc-tile ${primary ? "primary" : ""}`}>
      <div className="pdc-tile-label">{label}</div>
      <div className={`pdc-tile-val ${tone}`}>{value}</div>
    </div>
  );
}
