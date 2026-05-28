/**
 * Number count-up animation primitives — shared across the app.
 *
 * Documented at /Users/niketparekh/Downloads/ANIMATION-NUMBERS.md.
 *
 *   useCountUp(target, opts)   — rAF count-up 0 → target, easeOutCubic
 *   useEntered(delay)          — true after first rAF; CSS-transition fuse
 *   <MoneyCount value sign />  — animated dollar amount
 *   <PctCount value sign />    — animated percentage
 *
 * Choreography (from the spec):
 *   • Hero numbers      → duration 1400, delay 0
 *   • Secondary nums    → duration 1100, delay 200
 *   • Lists of numbers  → 80–90ms stagger starting around delay 300
 *   • All animations finish within ~1.6s total
 *
 * Use real minus glyph (U+2212) not hyphen so widths align across +/−.
 *
 * Caveat: hook resets to 0 every time `target` changes. For live-
 * updating values (price refreshes, etc.) the animation will replay
 * — usually fine, but consider memoizing the target if you want it
 * to stick after the first reveal.
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

/** Plain animated integer with a thousands-separator. No sign, no
 *  prefix — use for counts ("12 trades", "1,034 tickers"). */
export function CountUp({ value, delay = 0, duration = 1100 }: { value: number; delay?: number; duration?: number }) {
  const v = useCountUp(Math.abs(value), { duration, delay });
  return <>{Math.round(v).toLocaleString("en-US")}</>;
}

/** Animate a value 0 → target while letting the caller control how the
 *  intermediate value is formatted. Use this when your page already
 *  has a formatter (e.g. fmt$ / fmtK that produce "$642k" / "+$4.8k")
 *  and you don't want to switch to MoneyCount's full-decimal style.
 *
 *  Signed numbers: pass the original value (negatives included) — the
 *  format function receives the eased value with its original sign so
 *  the "−" / "+" appears naturally in the output. */
export function AnimatedNumber({
  value, format, delay = 0, duration = 1100,
}: {
  value: number;
  format: (n: number) => string;
  delay?: number;
  duration?: number;
}) {
  const eased = useCountUp(Math.abs(value), { duration, delay });
  const signed = value < 0 ? -eased : eased;
  return <>{format(signed)}</>;
}
