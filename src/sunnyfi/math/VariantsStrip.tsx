/**
 * VariantsStrip — per-ticker exploration scratchpad that lives below the
 * results of a calc body. Lets the user:
 *
 *   • + Save current as a variant card (manual mode)
 *   • Sweep a dimension to auto-spawn N variants in one click
 *   • Click any card to reload it back into the calc
 *   • ✕ delete a variant
 *   • → Promote the best one to a canonical Snapshot (shows up in Compare)
 *
 * Scoped to (calcKey + payload.underlying). Switching ticker → switches strip.
 */
import { useMemo, useState, type ReactNode } from "react";
import { useVariants, type Snapshot } from "./store";
import { CALC_MODULES, type CalcModule } from "./calcs";
import { toast } from "sonner";

export interface SweepOption {
  /** Label shown in the sweep dropdown. */
  label: string;
  /** State-key being varied (for the auto-generated variant name). */
  stateKey: string;
  /** Possible values to spawn variants for. */
  values: Array<{ id: string; label: string }>;
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
  /** Optional sweep dimensions, e.g. put frequency / put strike / etc. */
  sweeps?: SweepOption[];
}) {
  const ticker = (calcModule.upsertKey?.(state) ?? "").toUpperCase();
  const { variants, isLoading, create, remove, promote } = useVariants(calcKey, ticker || null);

  // Rank variants by the calc's own metric (same as Compare's Analyze).
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

  const handleSweep = async (opt: SweepOption) => {
    if (!ticker) { toast.error("Enter a ticker first to sweep"); return; }
    try {
      // Fire all create calls in parallel — they don't depend on each other.
      await Promise.all(
        opt.values.map((v) => {
          const payload = { ...state, [opt.stateKey]: v.id };
          const name = `${ticker} · ${v.label}`;
          return create({ calcKey, name, payload });
        }),
      );
      toast.success(`Swept ${opt.label} → ${opt.values.length} variants`);
    } catch (e) {
      toast.error(`Sweep failed: ${(e as Error).message}`);
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

  const [sweepOpen, setSweepOpen] = useState(false);

  return (
    <div className="vstrip">
      <div className="vstrip-hd">
        <div>
          <div className="vstrip-eyebrow">Variants {ticker ? `· ${ticker}` : ""}</div>
          <div className="vstrip-count">
            {isLoading ? "loading…"
              : variants.length === 0 ? "Save combos to compare them side by side"
              : `${variants.length} saved · ranked by ${ranked[0]?.label ?? "yield"}`}
          </div>
        </div>
        <div className="vstrip-actions">
          {sweeps && sweeps.length > 0 && (
            <div className="vstrip-sweep">
              <button
                type="button"
                className="hf-btn ghost"
                onClick={() => setSweepOpen((v) => !v)}
                disabled={!ticker}
              >
                ⇆ Sweep
              </button>
              {sweepOpen && (
                <div className="vstrip-sweep-menu" onMouseLeave={() => setSweepOpen(false)}>
                  {sweeps.map((s) => (
                    <button
                      key={s.stateKey}
                      type="button"
                      className="vstrip-sweep-opt"
                      onClick={() => { setSweepOpen(false); handleSweep(s); }}
                    >
                      <span>{s.label}</span>
                      <span className="vstrip-sweep-meta">{s.values.length} variants</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
          <button type="button" className="hf-btn tinted" onClick={handleSaveCurrent} disabled={!ticker}>
            + Save variant
          </button>
          <button
            type="button"
            className="hf-btn neon"
            onClick={handlePromoteBest}
            disabled={ranked.length === 0 || !isFiniteScore(ranked[0]?.score)}
            title="Promote the #1 variant to a Compare snapshot"
          >
            → Promote best
          </button>
        </div>
      </div>

      {variants.length > 0 && (
        <div className="vstrip-cards">
          {ranked.map(({ snap, score }, i) => (
            <VariantCard
              key={snap.id}
              snap={snap}
              calcModule={calcModule}
              rank={i + 1}
              score={score}
              onLoad={() => onLoad({ ...calcModule.initial, ...snap.payload } as S)}
              onDelete={() => remove(snap.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function VariantCard<S extends Record<string, unknown>>({
  snap, calcModule, rank, score, onLoad, onDelete,
}: {
  snap: Snapshot;
  calcModule: CalcModule<S>;
  rank: number;
  score: number | undefined;
  onLoad: () => void;
  onDelete: () => void;
}) {
  const disp = calcModule.display?.(snap.payload as S) ?? { value: "—", tone: "muted" as const };
  const line = calcModule.cardLine?.(snap.payload as S) ?? "";
  const isBest = rank === 1 && isFiniteScore(score);
  return (
    <button
      type="button"
      className={`vstrip-card${isBest ? " best" : ""}`}
      onClick={onLoad}
      title="Click to load this variant into the calculator"
    >
      <span className={`vstrip-card-rank${isBest ? " best" : ""}`}>
        {isBest ? "BEST" : `#${rank}`}
      </span>
      <span
        className="vstrip-card-x"
        role="button"
        aria-label="Delete variant"
        onClick={(e) => { e.stopPropagation(); onDelete(); }}
      >
        ✕
      </span>
      <div className="vstrip-card-name">{snap.name}</div>
      <div className={`vstrip-card-hero ${disp.tone}`}>{disp.value}</div>
      {isFiniteScore(score) && (
        <div className="vstrip-card-metric">{formatScore(calcModule, score!)}</div>
      )}
      {line && <div className="vstrip-card-line">{line}</div>}
    </button>
  );
}

function isFiniteScore(n: number | undefined): boolean {
  return typeof n === "number" && isFinite(n);
}

function formatScore<S extends Record<string, unknown>>(_mod: CalcModule<S>, score: number): string {
  // Mirror Math.tsx's formatScore — same display rules.
  return `${score.toFixed(2)}%`;
}

function autoVariantName<S extends Record<string, unknown>>(
  mod: CalcModule<S>,
  state: S,
  nextN: number,
): string {
  const ticker = (mod.upsertKey?.(state) ?? "").toString().toUpperCase();
  return ticker ? `${ticker} · v${nextN}` : `Variant ${nextN}`;
}

export type { ReactNode };
