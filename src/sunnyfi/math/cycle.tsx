/**
 * Cycle calculators — shared math + UI primitives.
 *
 * Used by Expected Income, Put Cost, and Income vs Cost. Each one composes
 * <CycField>/<NumInput>/<HeroNumInput>/<Seg>/<Tile> with the FREQ_DEFS +
 * HORIZON_DEFS catalogs and the cycleStats/resolveHorizon helpers below.
 *
 * Ported from calc-cycle-shared.jsx (handoff bundle).
 */
import type { ReactNode } from "react";
import "./cycle.css";

// ── Frequency table ─────────────────────────────────────────────
export interface FreqDef {
  id: string;
  label: string;
  short: string;
  calDays: number;   // average calendar days between cycles
  perYear: number;
}

export const FREQ_DEFS: FreqDef[] = [
  { id: "daily",    label: "Daily",         short: "daily",        calDays: 365 / 252, perYear: 252 },
  { id: "3day",     label: "Every 3 days",  short: "every 3 days", calDays: 365 / 84,  perYear: 84  },
  { id: "weekly",   label: "Weekly",        short: "weekly",       calDays: 7,         perYear: 52  },
  { id: "biweekly", label: "Bi-weekly",     short: "bi-weekly",    calDays: 14,        perYear: 26  },
  { id: "monthly",  label: "Monthly",       short: "monthly",      calDays: 365 / 12,  perYear: 12  },
];
export const FREQ_BY_ID: Record<string, FreqDef> = Object.fromEntries(FREQ_DEFS.map(f => [f.id, f]));

export interface HorizonDef { id: string; label: string }
export const HORIZON_DEFS: HorizonDef[] = [
  { id: "month",   label: "End of month" },
  { id: "quarter", label: "End of quarter" },
  { id: "year",    label: "End of year" },
  { id: "rolling", label: "12mo rolling" },
  { id: "custom",  label: "Custom date" },
];

// ── Date helpers ────────────────────────────────────────────────
function endOfMonth(d: Date)    { return new Date(d.getFullYear(), d.getMonth() + 1, 0); }
function endOfQuarter(d: Date)  { const q = Math.floor(d.getMonth() / 3); return new Date(d.getFullYear(), q * 3 + 3, 0); }
function endOfYear(d: Date)     { return new Date(d.getFullYear(), 11, 31); }
function plusDays(d: Date, n: number) { const r = new Date(d); r.setDate(r.getDate() + n); return r; }
export function daysBetween(a: Date, b: Date): number {
  return Math.max(0, Math.round((b.getTime() - a.getTime()) / 86400000));
}

export function resolveHorizon(kind: string, customDate: string, now: Date = new Date()): Date | null {
  switch (kind) {
    case "month":   return endOfMonth(now);
    case "quarter": return endOfQuarter(now);
    case "year":    return endOfYear(now);
    case "rolling": return plusDays(now, 365);
    case "custom":  return customDate ? new Date(customDate + "T00:00:00") : null;
    default:        return null;
  }
}

export interface CycleStats { cycles: number; days: number; years: number }
export function cycleStats(freqId: string, horizonDate: Date | null, now: Date = new Date()): CycleStats {
  const freq = FREQ_BY_ID[freqId];
  if (!freq || !horizonDate || isNaN(horizonDate.getTime())) {
    return { cycles: NaN, days: NaN, years: NaN };
  }
  const days = daysBetween(now, horizonDate);
  const cycles = Math.floor(days / freq.calDays);
  const years = days / 365.25;
  return { cycles, days, years };
}

// ── Formatters ──────────────────────────────────────────────────
export function fmtDate(d: Date | null): string {
  if (!d || !(d instanceof Date) || isNaN(d.getTime())) return "—";
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}
export function fmtMoney(n: number, opts: { decimals?: number; signed?: boolean } = {}): string {
  if (!isFinite(n)) return "—";
  const decimals = opts.decimals ?? 2;
  const sign = opts.signed && n > 0 ? "+" : n < 0 ? "−" : "";
  return `${sign}$${Math.abs(n).toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}`;
}
export function fmtMoneyCompact(n: number): string {
  if (!isFinite(n)) return "—";
  const a = Math.abs(n);
  const sign = n < 0 ? "−$" : "$";
  if (a >= 1e6) return `${sign}${(a / 1e6).toFixed(2)}M`;
  if (a >= 1e4) return `${sign}${(a / 1e3).toFixed(1)}k`;
  return `${sign}${a.toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}
export function fmtPct(n: number, opts: { decimals?: number } = {}): string {
  if (!isFinite(n)) return "—";
  const decimals = opts.decimals ?? 2;
  return `${n.toFixed(decimals)}%`;
}
export function fmtCount(n: number): string {
  if (!isFinite(n)) return "—";
  return Math.round(n).toLocaleString("en-US");
}
export function fmtNum(s: string | number | null | undefined): string {
  return (s ?? "").toString().trim() || "—";
}

// ── Reusable inputs ─────────────────────────────────────────────
export function CycField({ label, children, span = 1 }: { label: string; children: ReactNode; span?: number }) {
  return (
    <div className="cyc-field" style={{ gridColumn: `span ${span}` }}>
      <div className="hf-label">{label}</div>
      {children}
    </div>
  );
}

interface NumInputProps {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  prefix?: string;
  suffix?: string;
  ariaLabel?: string;
  className?: string;
}

export function NumInput({ value, onChange, placeholder, prefix, suffix, ariaLabel, className = "" }: NumInputProps) {
  return (
    <div className="cyc-field-row">
      {prefix && <span className="cyc-prefix">{prefix}</span>}
      <input
        className={`cyc-input ${className}`}
        type="text"
        inputMode="decimal"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        spellCheck={false}
        autoComplete="off"
        aria-label={ariaLabel || ""}
      />
      {suffix && <span className="cyc-suffix">{suffix}</span>}
    </div>
  );
}

interface HeroNumInputProps {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  prefix?: string;
  ariaLabel?: string;
  muted?: boolean;
}

export function HeroNumInput({ value, onChange, placeholder, prefix, ariaLabel, muted = false }: HeroNumInputProps) {
  return (
    <div className="cyc-hero-row">
      {prefix && <span className="cyc-hero-prefix">{prefix}</span>}
      <input
        className={`cyc-hero-input ${muted ? "muted" : ""}`}
        type="text"
        inputMode="decimal"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        spellCheck={false}
        autoComplete="off"
        aria-label={ariaLabel || ""}
      />
    </div>
  );
}

interface SegOption<T extends string> { id: T; label: string }
interface SegProps<T extends string> {
  options: SegOption<T>[];
  value: T;
  onChange: (v: T) => void;
  ariaLabel?: string;
}

export function Seg<T extends string>({ options, value, onChange, ariaLabel }: SegProps<T>) {
  return (
    <div className="cyc-seg" role="radiogroup" aria-label={ariaLabel || ""}>
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          role="radio"
          aria-checked={value === o.id}
          className={`cyc-seg-opt ${value === o.id ? "active" : ""}`}
          onClick={() => onChange(o.id)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

interface TileProps {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  tone?: "pos" | "neg" | "neon" | "warn" | "neutral";
  primary?: boolean;
  mono?: boolean;
}

export function Tile({ label, value, sub, tone, primary, mono }: TileProps) {
  const toneCls = tone && tone !== "neutral" ? ` ${tone}` : "";
  return (
    <div className={`cyc-tile ${primary ? "primary" : ""}`}>
      <div className="cyc-tile-label">{label}</div>
      {sub && <div className="cyc-tile-sub">{sub}</div>}
      <div className={`cyc-tile-val${mono ? " mono" : ""}${toneCls}`}>{value}</div>
    </div>
  );
}

// ── Moneyness helper (shared between Put Cost + Income vs Cost) ────
export function moneynessLabel(strikeStr: string, priceStr: string): string | null {
  const strike = Number(strikeStr);
  const price = Number(priceStr);
  if (!isFinite(strike) || !isFinite(price) || strike <= 0 || price <= 0) return null;
  const m = ((strike - price) / price) * 100;
  if (Math.abs(m) < 0.05) return "ATM";
  return m < 0
    ? `OTM · ${Math.abs(m).toFixed(1)}% below spot`
    : `ITM · ${m.toFixed(1)}% above spot`;
}
