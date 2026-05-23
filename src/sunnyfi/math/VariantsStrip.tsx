/**
 * VariantsStrip — per-ticker exploration scratchpad below the calc body.
 *
 * Auto-mode: when the calc declares a `quote`-backed sweep (currently the
 * put-frequency sweep on IvC and Put Cost), this component fires the sweep
 * AUTOMATICALLY whenever the ticker or strike changes — replacing all
 * existing variants for that (calc, ticker) with one per cadence, each
 * priced from Polygon at its nearest available expiry.
 *
 * Card names encode the matched expiry so it's obvious when the chain is
 * sparse — e.g. "TSM · 12mo target · exp Aug 15 (⚠ no LEAPS) · $21.28" —
 * instead of the silent collision you'd otherwise see.
 *
 * Manual + Promote buttons stay for tighter control / promoting the
 * winner into Compare.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import { useVariants } from "./store";
import { type CalcModule } from "./calcs";
import { pullOptionChain, nearestExpiry, type OptionContractQuote } from "./quote";
import { toast } from "sonner";

export interface SweepOption {
  label: string;
  stateKey: string;
  values: Array<{ id: string; label: string; calDays?: number }>;
  quote?: {
    type: "put" | "call";
    strikeFrom: { strikeKey: string } | { spotKey: string; distanceKey: string };
    premiumKey: string;
  };
}

const PURPOSE_SEP = "|";
const PURPOSE_PREFIX = "auto:";

/** Encode auto-sweep metadata into the `purpose` column so the card can
 *  decode it later (matched expiry, target expiry, warn flag). */
function encodePurpose(matched: string, target: string, warn: boolean): string {
  return `${PURPOSE_PREFIX}match=${matched}${PURPOSE_SEP}target=${target}${PURPOSE_SEP}warn=${warn ? "1" : "0"}`;
}
function decodePurpose(purpose?: string): { matched?: string; target?: string; warn?: boolean } | null {
  if (!purpose || !purpose.startsWith(PURPOSE_PREFIX)) return null;
  const parts = purpose.slice(PURPOSE_PREFIX.length).split(PURPOSE_SEP);
  const out: { matched?: string; target?: string; warn?: boolean } = {};
  for (const p of parts) {
    const [k, v] = p.split("=");
    if (k === "match") out.matched = v;
    else if (k === "target") out.target = v;
    else if (k === "warn") out.warn = v === "1";
  }
  return out;
}

/** Friendly short expiry e.g. "Aug 15" — strips year unless it differs. */
function shortDate(iso?: string): string {
  if (!iso) return "—";
  const d = new Date(iso + "T00:00:00Z");
  if (isNaN(d.getTime())) return iso;
  const sameYear = d.getUTCFullYear() === new Date().getUTCFullYear();
  return d.toLocaleDateString(undefined, {
    month: "short", day: "numeric",
    ...(sameYear ? {} : { year: "numeric" }),
  });
}

export function VariantsStrip<S extends Record<string, unknown>>({
  calcKey,
  calcModule,
  state,
  onLoad,
  sweeps,
}: {
  calcKey: string;
  calcModule: CalcModule<S>;
  state: S;
  onLoad: (next: S) => void;
  sweeps?: SweepOption[];
}) {
  const ticker = (calcModule.upsertKey?.(state) ?? "").toUpperCase();
  const { variants, isLoading, create, remove, promote, replaceAll } =
    useVariants(calcKey, ticker || null);

  // Pick the put-frequency sweep with real-quote support as the "auto"
  // sweep. (Calls follow later — they're a separate API call against the
  // call chain.) For Put Cost the calc has a single freq sweep.
  const autoSweep = useMemo<SweepOption | undefined>(
    () => sweeps?.find((s) => s.quote?.type === "put") ?? sweeps?.find((s) => !!s.quote),
    [sweeps],
  );

  // Auto-mode rerun: every input that affects the compute should trigger a
  // re-sweep, except for the dimension the sweep itself is varying (e.g.
  // putFrequency for an IvC put-side sweep — that's the axis, not an input).
  // Serialise the rest of state into a watcher key.
  const watchedKey = useMemo(() => {
    if (!autoSweep) return "";
    // Drop the swept key + any value-list metadata so changes to it don't
    // re-trigger the sweep (which would otherwise loop the auto-fallback).
    const filtered: Record<string, unknown> = {};
    for (const k of Object.keys(state)) {
      if (k === autoSweep.stateKey) continue;
      filtered[k] = state[k];
    }
    return JSON.stringify(filtered);
  }, [autoSweep, state]);

  const [busy, setBusy] = useState(false);
  const lastSweepKey = useRef<string>("");

  // Debounced auto-sweep trigger. Bumped to 900ms now that every keystroke
  // can re-trigger — the user typically pauses between inputs.
  useEffect(() => {
    if (!autoSweep || !ticker || !watchedKey) return;
    const sweepKey = `${ticker}|${watchedKey}`;
    if (sweepKey === lastSweepKey.current) return;
    const t = window.setTimeout(() => {
      lastSweepKey.current = sweepKey;
      void runAutoSweep(autoSweep);
    }, 900);
    return () => window.clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoSweep, ticker, watchedKey]);

  const ranked = useMemo(() => {
    const scored = variants.map((v) => {
      const r = calcModule.rank?.(v.payload as S);
      return { snap: v, score: r?.score, label: r?.label };
    });
    return [...scored].sort((a, b) => {
      const aS = typeof a.score === "number" && isFinite(a.score);
      const bS = typeof b.score === "number" && isFinite(b.score);
      if (aS && bS) return (b.score as number) - (a.score as number);
      if (aS) return -1;
      if (bS) return 1;
      return b.snap.createdAt - a.snap.createdAt;
    });
  }, [variants, calcModule]);

  async function runAutoSweep(opt: SweepOption) {
    if (!ticker || !opt.quote) return;
    const strike = resolveStrike(state, opt.quote.strikeFrom);
    if (!isFinite(strike) || strike <= 0) return;

    setBusy(true);
    let chain: OptionContractQuote[] = [];
    try {
      chain = await pullOptionChain(ticker, strike, opt.quote.type);
    } catch (e) {
      toast.error(`Chain fetch failed: ${(e as Error).message}`);
      setBusy(false);
      return;
    }

    const today = new Date();
    const todayIso = today.toISOString().slice(0, 10);
    const payloads = opt.values.map((v) => {
      const days = v.calDays ?? 30;
      const targetDate = new Date(today.getTime() + days * 86400000)
        .toISOString().slice(0, 10);
      const matched = nearestExpiry(chain, targetDate);
      const payload: Record<string, unknown> = { ...state, [opt.stateKey]: v.id };
      let displaySuffix = v.label;
      let purpose: string | undefined;

      if (matched) {
        payload[opt.quote!.premiumKey] = matched.premium.toFixed(2);
        const matchedT = new Date(matched.expiry + "T00:00:00Z").getTime();
        const targetT = new Date(targetDate + "T00:00:00Z").getTime();
        const driftDays = Math.abs(matchedT - targetT) / 86400000;
        const warn = driftDays > 30;
        purpose = encodePurpose(matched.expiry, targetDate, warn);
        const expShort = shortDate(matched.expiry);
        displaySuffix = warn
          ? `${v.label} → exp ${expShort} ⚠ · $${matched.premium.toFixed(2)}`
          : `${v.label} · ${expShort} · $${matched.premium.toFixed(2)}`;
      } else {
        // No contract at all — keep cadence value but record the miss.
        purpose = encodePurpose("", todayIso, true);
        displaySuffix = `${v.label} ⚠ no listed contract`;
      }

      return {
        name: `${ticker} · ${displaySuffix}`,
        purpose,
        payload,
      };
    });

    try {
      await replaceAll({ calcKey, ticker, payloads });
      toast.success(`Auto-swept ${opt.label.toLowerCase()} · ${payloads.length} variants (real Polygon)`);
    } catch (e) {
      toast.error(`Sweep failed: ${(e as Error).message}`);
    } finally {
      setBusy(false);
    }
  }

  const handleSaveCurrent = async () => {
    if (!ticker) { toast.error("Enter a ticker first to save a variant"); return; }
    try {
      const name = autoVariantName(calcModule, state, variants.length + 1);
      await create({ calcKey, name, payload: { ...state } });
      toast.success(`+ Variant saved · ${ticker}`);
    } catch (e) {
      toast.error(`Save failed: ${(e as Error).message}`);
    }
  };

  const handlePromoteBest = async () => {
    const best = ranked[0];
    if (!best || !isFiniteScore(best.score)) {
      toast.error("No rankable variant to promote");
      return;
    }
    try {
      await promote(best.snap.id);
      toast.success(`✓ Promoted "${best.snap.name}" to Compare`);
    } catch (e) {
      toast.error(`Promote failed: ${(e as Error).message}`);
    }
  };

  return (
    <div className="vstrip">
      <div className="vstrip-hd">
        <div>
          <div className="vstrip-eyebrow">Variants {ticker ? `· ${ticker}` : ""}</div>
          <div className="vstrip-count">
            {!ticker ? "Pull or type a ticker to auto-generate variants"
              : busy ? "Fetching Polygon chain · regenerating variants…"
              : isLoading ? "loading…"
              : variants.length === 0 ? "Set a strike to auto-spawn one variant per cadence"
              : `${variants.length} variants · auto-priced from Polygon · ranked by ${ranked[0]?.label ?? "yield"}`}
          </div>
        </div>
        <div className="vstrip-actions">
          <button type="button" className="hf-btn tinted" onClick={handleSaveCurrent} disabled={!ticker || busy}>
            + Pin current
          </button>
          <button
            type="button"
            className="hf-btn neon"
            onClick={handlePromoteBest}
            disabled={ranked.length === 0 || !isFiniteScore(ranked[0]?.score) || busy}
            title="Promote the #1 variant to a Compare snapshot"
          >
            → Promote best
          </button>
        </div>
      </div>

      {variants.length > 0 && (
        <div className="vstrip-cards">
          {ranked.map(({ snap, score }, i) => {
            const isBest = i === 0 && isFiniteScore(score);
            const meta = decodePurpose(snap.purpose);
            const warn = meta?.warn === true;
            const disp = calcModule.display?.(snap.payload as S) ?? { value: "—", tone: "muted" as const };
            const line = calcModule.cardLine?.(snap.payload as S) ?? "";
            return (
              <button
                key={snap.id}
                type="button"
                className={`vstrip-card${isBest ? " best" : ""}${warn ? " warn" : ""}`}
                onClick={() => onLoad({ ...calcModule.initial, ...snap.payload } as S)}
                title="Click to load this variant into the calculator"
              >
                <span className={`vstrip-card-rank${isBest ? " best" : ""}`}>
                  {isBest ? "BEST" : `#${i + 1}`}
                </span>
                {warn && (
                  <span className="vstrip-card-warn" title="Polygon's nearest expiry was >30 days from the cadence's target — long-dated options may not be listed at this strike">
                    ⚠
                  </span>
                )}
                <span
                  className="vstrip-card-x"
                  role="button"
                  aria-label="Delete variant"
                  onClick={(e) => { e.stopPropagation(); remove(snap.id); }}
                >
                  ✕
                </span>
                <div className="vstrip-card-name">{snap.name}</div>
                <div className={`vstrip-card-hero ${disp.tone}`}>{disp.value}</div>
                {isFiniteScore(score) && (
                  <div className="vstrip-card-metric">{(score as number).toFixed(2)}%</div>
                )}
                {line && <div className="vstrip-card-line">{line}</div>}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

function isFiniteScore(n: number | undefined): boolean {
  return typeof n === "number" && isFinite(n);
}

function resolveStrike(
  state: Record<string, unknown>,
  spec: { strikeKey: string } | { spotKey: string; distanceKey: string },
): number {
  if ("strikeKey" in spec) return Number(state[spec.strikeKey]);
  const spot = Number(state[spec.spotKey]);
  const dist = Number(state[spec.distanceKey]);
  if (!isFinite(spot) || !isFinite(dist)) return NaN;
  return spot * (1 + dist / 100);
}

function autoVariantName<S extends Record<string, unknown>>(
  mod: CalcModule<S>,
  state: S,
  nextN: number,
): string {
  const ticker = (mod.upsertKey?.(state) ?? "").toString().toUpperCase();
  return ticker ? `${ticker} · pinned v${nextN}` : `Variant ${nextN}`;
}
