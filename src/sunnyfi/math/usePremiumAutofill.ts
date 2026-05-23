/**
 * usePremiumAutofill — keeps a calc's premium field in sync with Polygon
 * for the nearest-to-cadence expiry.
 *
 * Hook semantics:
 *   - Watches (ticker, strike, cadenceDays) — when any of those changes,
 *     debounces ~500ms then fetches the option chain
 *   - Picks the contract whose expiry is closest to today + cadenceDays
 *   - Calls setPremium(matched.premium) with the per-share premium
 *   - Tracks a per-key "user override" flag — if the user types in the
 *     premium field directly, autofill backs off for that key until either
 *     the ticker changes or strike changes (whichever counts as "fresh
 *     intent")
 *
 * Returns:
 *   { status: 'idle' | 'fetching' | 'ok' | 'err' | 'overridden',
 *     msg, markOverride() }
 */
import { useEffect, useRef, useState } from "react";
import { pullOptionChain, nearestExpiry } from "./quote";

export function usePremiumAutofill(args: {
  ticker: string;
  strike: number;
  cadenceDays: number;
  contractType: "put" | "call";
  /** Called with the matched per-share premium (string for state). */
  setPremium: (v: string) => void;
  /** Skip autofill while user is manually editing this premium. */
  isOverridden: boolean;
}) {
  const { ticker, strike, cadenceDays, contractType, setPremium, isOverridden } = args;

  const [status, setStatus] = useState<"idle" | "fetching" | "ok" | "err" | "overridden">("idle");
  const [msg, setMsg] = useState<string>("");
  const lastKey = useRef<string>("");

  useEffect(() => {
    if (isOverridden) { setStatus("overridden"); setMsg("manual override"); return; }
    if (!ticker || !isFinite(strike) || strike <= 0 || !isFinite(cadenceDays) || cadenceDays <= 0) {
      setStatus("idle"); setMsg("");
      return;
    }
    const key = `${ticker}|${strike}|${contractType}|${cadenceDays}`;
    if (key === lastKey.current) return;

    const t = window.setTimeout(async () => {
      lastKey.current = key;
      setStatus("fetching");
      setMsg("");
      try {
        const chain = await pullOptionChain(ticker, strike, contractType);
        if (chain.length === 0) {
          setStatus("err");
          setMsg("no listed contract");
          return;
        }
        const target = new Date(Date.now() + cadenceDays * 86400000)
          .toISOString().slice(0, 10);
        const matched = nearestExpiry(chain, target);
        if (!matched) { setStatus("err"); setMsg("no nearby expiry"); return; }
        setPremium(matched.premium.toFixed(2));
        setStatus("ok");
        setMsg(`exp ${matched.expiry} · $${matched.premium.toFixed(2)}`);
      } catch (e) {
        setStatus("err");
        setMsg((e as Error).message);
      }
    }, 500);

    return () => window.clearTimeout(t);
  }, [ticker, strike, cadenceDays, contractType, isOverridden, setPremium]);

  return { status, msg };
}
