/**
 * Re-export shim — the count-up primitives have been promoted to
 * src/sunnyfi/lib/animation.tsx so they're usable across the whole
 * app (not just the dashboard). This file stays so existing
 * `dashboard/animation` imports keep working; new code should import
 * from `@/sunnyfi/lib/animation`.
 */
export {
  useCountUp,
  useEntered,
  MoneyCount,
  PctCount,
  CountUp,
} from "@/sunnyfi/lib/animation";
