/**
 * Shared atoms — DeltaBar / Flags / LiveStatus / useEntered. Port of
 * the same-named helpers in the handoff `mp-data.jsx`.
 */
import { useEffect, useState } from "react";
import { fmtGreek, signCls, type Flag } from "./data";

export function useEntered(delay = 0): boolean {
  const [on, setOn] = useState(false);
  useEffect(() => {
    const id = setTimeout(() => setOn(true), delay);
    return () => clearTimeout(id);
  }, [delay]);
  return on;
}

export function LiveStatus({ time = "06:42" }: { time?: string }) {
  return (
    <span className="live-status">
      <span className="live-dot" />
      <span className="lbl">updated {time} PT</span>
      <span className="delay">15-MIN DELAY</span>
    </span>
  );
}

export function Flags({ flags, max }: { flags: Flag[]; max?: number }) {
  const shown = max ? flags.slice(0, max) : flags;
  return (
    <span className="flagrow">
      {shown.map((f, i) => (
        <span key={i} className={"flag " + f.tone}>{f.label}</span>
      ))}
      {max && flags.length > max && (
        <span className="flag more">+{flags.length - max}</span>
      )}
    </span>
  );
}

/** Signed delta exposure bar — centered at 0. Width scales by abs(value)/max. */
export function DeltaBar({
  value, max, h = 18, showVal = true,
}: {
  value: number; max: number; h?: number; showVal?: boolean;
}) {
  const entered = useEntered(200);
  const pct = Math.min(1, Math.abs(value) / max);
  const pos = value >= 0;
  return (
    <span className="dbar" style={{ height: h }}>
      <span className="dbar-axis" />
      <span
        className={"dbar-fill " + (pos ? "pos" : "neg")}
        style={{
          width: entered ? pct * 50 + "%" : "0%",
          left: pos ? "50%" : "auto",
          right: pos ? "auto" : "50%",
        }}
      />
      {showVal && (
        <span className={"dbar-val " + signCls(value)}>{fmtGreek(Math.round(value))}</span>
      )}
    </span>
  );
}
