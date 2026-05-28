/**
 * Dashboard atom components.
 *
 * Ported from the Claude design handoff. Reused by every content block:
 *
 *   <Spark>       — SVG sparkline with optional area-fill + dash-offset draw-in
 *   <AnimatedBar> — width-transition bar (0% → targetPct, 1s easeOutCubic)
 *   <HairRow>     — three-column row with bottom hairline (label · content · right)
 *   <Section>     — small mono section header with optional § N number + right
 */
import { useEntered } from "./animation";

type SparkKind = "pos" | "neg" | "neon" | "muted" | "muted-down";

/** SVG sparkline.
 *
 *  Without `series` it falls back to one of two pre-baked point sets:
 *    • `dense` = looks like a busy intraday tape (used by macro rows)
 *    • otherwise = a smoother portfolio-style curve
 *
 *  With `series` (an array of real numbers) it auto-scales the y-axis
 *  to [min, max] of the data and draws a line through every point.
 *
 *  The stroke animates in via dasharray + dashoffset over 1.4s. */
export function Spark({
  w = 120, h = 32, kind = "pos", dense = false, area = false, delay = 0, series,
}: {
  w?: number;
  h?: number;
  kind?: SparkKind;
  dense?: boolean;
  area?: boolean;
  delay?: number;
  series?: number[];
}) {
  const inv = kind === "neg" || kind === "muted-down";

  // Build the y values in [0..1] space. With a real series we
  // normalise to min/max so the line uses the full height; without, we
  // fall back to the pre-baked curves so the block looks alive while
  // data is still loading.
  let data: number[];
  if (series && series.length >= 2) {
    const min = Math.min(...series);
    const max = Math.max(...series);
    const range = max - min || 1;
    data = series.map((v) => 1 - (v - min) / range);     // higher value → lower y
  } else {
    const fallback = dense
      ? [0.5, 0.4, 0.55, 0.35, 0.45, 0.3, 0.5, 0.42, 0.3, 0.45, 0.25, 0.35, 0.4, 0.25, 0.2, 0.3, 0.15, 0.22, 0.28, 0.18]
      : [0.62, 0.55, 0.68, 0.48, 0.42, 0.52, 0.45, 0.38, 0.42, 0.28, 0.32, 0.22];
    data = inv ? fallback.map((p) => 1 - p * 0.8) : fallback;
  }

  const path = data.map((y, i) => {
    const x = (i / (data.length - 1)) * w;
    return `${i === 0 ? "M" : "L"} ${x.toFixed(1)} ${(y * (h - 4) + 2).toFixed(1)}`;
  }).join(" ");
  const fillPath = path + ` L ${w} ${h} L 0 ${h} Z`;
  const strokeClass = kind === "pos" ? "pos"
    : kind === "neg" ? "neg"
    : kind === "neon" ? "neon"
    : "muted";

  // Generous overestimate so the stroke is fully hidden at t=0.
  const totalLen = w * 2.2;
  const entered = useEntered(delay);

  return (
    <svg className={`spark${area ? " area" : ""}`} width={w} height={h} viewBox={`0 0 ${w} ${h}`}>
      {area && (
        <defs>
          <linearGradient id="sparkNeonGrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%"   stopColor="#d2e632" stopOpacity=".22" />
            <stop offset="100%" stopColor="#d2e632" stopOpacity="0" />
          </linearGradient>
        </defs>
      )}
      {area && (
        <path
          className="fill-neon"
          d={fillPath}
          style={{ opacity: entered ? 1 : 0, transition: "opacity 1.4s cubic-bezier(.16,1,.3,1) .3s" }}
        />
      )}
      <path
        d={path}
        className={strokeClass}
        style={{
          strokeDasharray: totalLen,
          strokeDashoffset: entered ? 0 : totalLen,
          transition: "stroke-dashoffset 1.4s cubic-bezier(.16,1,.3,1)",
        }}
      />
    </svg>
  );
}

/** Width-transition bar — 0% → targetPct over 1s, with a delay for the
 *  stagger choreography across a list. */
export function AnimatedBar({ targetPct, kind = "pos", delay = 0 }: {
  targetPct: number;
  kind?: "pos" | "neg";
  delay?: number;
}) {
  const entered = useEntered(delay);
  return (
    <div
      className={"bar " + kind}
      style={{
        width: entered ? `${targetPct * 100}%` : "0%",
        transition: "width 1s cubic-bezier(.16,1,.3,1)",
      }}
    />
  );
}

/** Three-column row with a bottom hairline. Used by Attention + Risk blocks
 *  and anywhere we want a "label / content / value" structure. */
export function HairRow({
  label, children, right, last,
}: {
  label: React.ReactNode;
  children: React.ReactNode;
  right?: React.ReactNode;
  last?: boolean;
}) {
  return (
    <div className={"hairrow" + (last ? " last" : "")}>
      <div className="label">{label}</div>
      <div className="row-content">{children}</div>
      <div className="row-right">{right}</div>
    </div>
  );
}

/** Section header. `n` was originally a "§ NN" numbering prefix from
 *  the design handoff — dropped because the symbol read as noise. The
 *  prop is kept on the type to avoid touching all the callers, but is
 *  no longer rendered.
 *
 *  `right` is the small muted text on the right edge ("4 picks",
 *  "reviewed 2d ago", "Week of Jun 23"). */
export function Section({ children, right }: {
  /** @deprecated number prefix from original design; no-op now. */
  n?: string;
  children?: React.ReactNode;
  right?: React.ReactNode;
}) {
  return (
    <div className="section">
      <span>{children}</span>
      {right && <span className="right">{right}</span>}
    </div>
  );
}
