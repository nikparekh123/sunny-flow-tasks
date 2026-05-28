/**
 * Dashboard animation primitives.
 *
 * Ported from the Claude design handoff. Two hooks + two display atoms:
 *
 *   useCountUp(target, opts)   — rAF count-up 0 → target, easeOutCubic
 *   useEntered(delay)          — flips true after first frame; lets CSS
 *                                transitions run as "enter from 0" effects
 *   <MoneyCount value sign />  — animated dollar amount
 *   <PctCount value sign />    — animated percentage
 *
 * Choreography rules (from ANIMATION-NUMBERS.md):
 *   • Hero number      → duration 1400, delay 0
 *   • Secondary nums   → duration 1100, delay 200
 *   • List staggers    → 80–90ms per row, starting around delay 300
 *   • All animations finish within ~1.6s total
 *
 * Negative sign uses the real minus glyph (U+2212) not hyphen so the
 * width matches the plus sign and tabular numerals stay aligned.
 */
import { useEffect, useState } from "react";

interface CountUpOptions {
  duration?: number;
  delay?: number;
}

export function useCountUp(target: number, { duration = 1100, delay = 0 }: CountUpOptions = {}): number {
  const [value, setValue] = useState(0);

  useEffect(() => {
    let raf: number | undefined;
    let start: number | undefined;

    function tick(now: number) {
      if (start == null) start = now + delay;
      const t = Math.max(0, Math.min(1, (now - start) / duration));
      // easeOutCubic — fast start, gentle settle.
      const eased = 1 - Math.pow(1 - t, 3);
      setValue(target * eased);
      if (t < 1) raf = requestAnimationFrame(tick);
    }

    raf = requestAnimationFrame(tick);
    return () => { if (raf != null) cancelAnimationFrame(raf); };
  }, [target, duration, delay]);

  return value;
}

/** Returns false on initial render, true after the first rAF following
 *  the optional delay. Use for CSS-driven "enter" transitions where the
 *  initial style is the "from" state and the post-mount style is "to". */
export function useEntered(delay = 0): boolean {
  const [entered, setEntered] = useState(false);
  useEffect(() => {
    const t = setTimeout(() => requestAnimationFrame(() => setEntered(true)), delay);
    return () => clearTimeout(t);
  }, [delay]);
  return entered;
}

interface NumProps {
  value: number;
  sign?: "+" | "-";
  delay?: number;
  duration?: number;
}

/** $4,820 / +$4,820 / −$94,200. Pass an absolute value plus a separate
 *  `sign` so the minus glyph stays consistent. */
export function MoneyCount({ value, sign, delay = 0, duration = 1100 }: NumProps) {
  const v = useCountUp(Math.abs(value), { duration, delay });
  const rounded = Math.round(v);
  const signChar = sign === "+" ? "+" : sign === "-" ? "−" : "";
  return <>{signChar}${rounded.toLocaleString("en-US")}</>;
}

/** 0.76% / +0.76% / −2.10% */
export function PctCount({
  value, sign, delay = 0, duration = 1100, decimals = 2,
}: NumProps & { decimals?: number }) {
  const v = useCountUp(Math.abs(value), { duration, delay });
  const signChar = sign === "+" ? "+" : sign === "-" ? "−" : "";
  return <>{signChar}{v.toFixed(decimals)}%</>;
}
