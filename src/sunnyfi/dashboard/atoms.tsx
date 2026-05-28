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

/** SVG sparkline. Two pre-baked point series (dense for macro rows, looser
 *  for portfolio hero) — replace with real data series in the data-wiring
 *  pass. The stroke draws in via dasharray + dashoffset over 1.4s. */
export function Spark({
  w = 120, h = 32, kind = "pos", dense = false, area = false, delay = 0,
}: {
  w?: number;
  h?: number;
  kind?: SparkKind;
  dense?: boolean;
  area?: boolean;
  delay?: number;
}) {
  const points = dense
    ? [0.5, 0.4, 0.55, 0.35, 0.45, 0.3, 0.5, 0.42, 0.3, 0.45, 0.25, 0.35, 0.4, 0.25, 0.2, 0.3, 0.15, 0.22, 0.28, 0.18]
    : [0.62, 0.55, 0.68, 0.48, 0.42, 0.52, 0.45, 0.38, 0.42, 0.28, 0.32, 0.22];
  // Invert when the line should slope down (e.g. negative tickers).
  const inv = kind === "neg" || kind === "muted-down";
  const data = inv ? points.map((p) => 1 - p * 0.8) : points;
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

/** Section header. `n` is the small "§ NN" prefix (e.g. "§ 01"). `right`
 *  is the small muted text on the right edge ("4 picks", "updated 06:42"). */
export function Section({ n, children, right }: {
  n?: string;
  children?: React.ReactNode;
  right?: React.ReactNode;
}) {
  return (
    <div className="section">
      <span>{n && <span className="n">§ {n}</span>}{children}</span>
      {right && <span className="right">{right}</span>}
    </div>
  );
}
