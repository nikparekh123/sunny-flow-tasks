/**
 * Master Positions — "Show in Large Type" focus story + right-click menu.
 *
 * Port of the handoff `mp-focus.jsx` (FocusStage variant only — the
 * earlier overlay/drawer variants in the prototype were exploration,
 * not part of the shipping design). React portals to document.body so
 * `position: fixed` escapes any transformed wrapper.
 */
import { useEffect } from "react";
import { createPortal } from "react-dom";
import {
  type Company, type Flag,
  fmtMoney, fmtGreek, fmtPct, signCls, legLabel, relDays, relExpiry,
} from "./data";

/* ---- analyst-voice captions, derived from real data ---- */
function strategyLine(c: Company): string {
  return ({
    Income: "Selling calls against the stock for steady monthly income.",
    Investment: "A core long thesis with options shaping the risk around it.",
    Yield: "Held for yield — short puts harvesting premium on the way.",
  } as const)[c.strat] ?? "A defined-risk options position.";
}
function flagStory(f: Flag): { h: string; s: string } {
  switch (f.k) {
    case "assign": return { h: "Assignment risk", s: "A short option sits near the money with little time left to expiry." };
    case "delta":  return { h: f.label, s: "Short-call delta has pushed past the roll threshold — consider rolling up." };
    case "crush":  return { h: f.label.replace("IV crush ", "IV crush · "), s: "Earnings ahead; short premium should compress hard after the print." };
    case "earn":   return { h: f.label.replace("earnings ", "Earnings · "), s: "Event risk lands before this position settles — size accordingly." };
    case "below":  return { h: "Below 200-day", s: "Trading under its long-term trend line — momentum is against it." };
    case "move":   return { h: "Big move today", s: "An outsized daily move versus its normal trading range." };
    default:       return { h: f.label, s: "" };
  }
}
function greekStory(c: Company): { delta: string; theta: string; vega: string; gamma: string } {
  const a = c.agg;
  const abs = (v: number) => Math.abs(v).toLocaleString("en-US");
  return {
    delta: `${a.delta >= 0 ? "Net long" : "Net short"} ${abs(a.delta)} shares-equivalent of directional exposure.`,
    theta: `${a.theta >= 0 ? "Collecting" : "Paying"} ${fmtMoney(Math.abs(a.theta))} a day in time decay.`,
    vega:  a.vega < 0 ? "Short volatility — this gains when implied vol falls." : "Long volatility — this gains when implied vol rises.",
    gamma: `Net delta shifts ${fmtGreek(a.gamma)} for every $1 the stock moves.`,
  };
}

/* ---- focus stage leg row ---- */
function FsLeg({ l }: { l: Company["legs"][number] }) {
  const lab = legLabel(l);
  const qty = l.kind === "stock"
    ? l.qty.toLocaleString() + " sh"
    : (l.qty > 0 ? "+" : "−") + Math.abs(l.qty);
  const bits = [qty, "$" + l.last.toFixed(2)];
  if (l.iv) bits.push("IV " + l.iv.toFixed(1) + "%");
  if (l.dte != null) bits.push(relExpiry(l.dte) ?? "");
  return (
    <div className="fs-leg">
      <span className={"leg-glyph " + lab.tone}>{lab.glyph}</span>
      <span className="fs-leg-name">
        {l.kind === "stock" ? "Common stock" : lab.main}
        {lab.side && <span className="side">{lab.side}</span>}
      </span>
      <span className="fs-leg-meta">{bits.filter(Boolean).join(" · ")}</span>
      <span className={"fs-leg-pl " + signCls(l.unreal)}>{fmtMoney(l.unreal, true)}</span>
    </div>
  );
}

/* ---- full-screen "keynote" presentation ---- */
export function FocusStage({
  data, t, onClose, onStep,
}: {
  data: Company[]; t: string;
  onClose: () => void; onStep: (dir: number) => void;
}) {
  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      else if (e.key === "ArrowRight") onStep(1);
      else if (e.key === "ArrowLeft") onStep(-1);
    };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, [onClose, onStep]);

  const idx = data.findIndex((c) => c.t === t);
  const c = data[idx];
  if (!c) return null;
  const opts = c.legs.filter((l) => l.kind !== "stock");
  const gs = greekStory(c);
  const pad = (n: number) => String(n).padStart(2, "0");
  const eventLine = c.event.kind === "none"
    ? "Closed " + c.event.date
    : c.event.label + " " + c.event.date + " · " + relDays(c.event.days);

  return createPortal(
    <div className="fs-stage">
      <div className="fs-top">
        <span className="fs-eyebrow"><span className="d">◆</span> Position · large type</span>
        <span className="fs-count">{pad(idx + 1)} <span className="sl">/</span> {pad(data.length)}</span>
        <button className="fs-exit" onClick={onClose}><span className="k">Esc</span> Close ✕</button>
      </div>

      <div className="fs-main" key={c.t}>
        {/* LEFT — the narrative spine */}
        <div className="fs-left">
          <div className="fs-kicker">{c.strat} · {c.sector}</div>
          <div className="fs-ticker">{c.t}</div>
          <div className="fs-name">{c.name}</div>
          <div className="fs-spotline">
            <span className="px">${c.spot.toFixed(2)}</span>
            <span className={"fs-day " + signCls(c.day)}>{fmtPct(c.day)} today</span>
          </div>
          <p className="fs-strategy">{strategyLine(c)}</p>

          <div className="fs-headline">
            <div className="fs-hk">Open P&amp;L</div>
            <div className={"fs-hv " + signCls(c.agg.unreal)}>{fmtMoney(c.agg.unreal, true)}</div>
            <div className="fs-hsub">
              {c.agg.real ? fmtMoney(c.agg.real, true) + " realized this year · " : ""}
              {fmtMoney(c.agg.mv)} market value
            </div>
          </div>
        </div>

        {/* RIGHT — attention, greeks, legs */}
        <div className="fs-right">
          <div className="fs-section">
            <div className="fs-slabel">Needs attention</div>
            {c.flags.length ? c.flags.map((f, i) => {
              const st = flagStory(f);
              return (
                <div className={"fs-alert " + f.tone} key={i}>
                  <div className="fs-alert-h">{st.h}</div>
                  <div className="fs-alert-s">{st.s}</div>
                </div>
              );
            }) : (
              <div className="fs-alert clear">
                <div className="fs-alert-h">All clear</div>
                <div className="fs-alert-s">Ladder inside its expected range — nothing to action right now.</div>
              </div>
            )}
            <div className="fs-event">{eventLine}</div>
          </div>

          <div className="fs-section">
            <div className="fs-slabel greek">Greeks · position</div>
            <div className="fs-bigstat">
              <div className="v neon">{fmtGreek(c.agg.delta)}</div>
              <div className="cap">{gs.delta}</div>
            </div>
            <div className="fs-trio">
              <div className="fs-mini"><div className={"v " + signCls(c.agg.theta)}>{fmtGreek(c.agg.theta)}</div><div className="k">Theta / day</div></div>
              <div className="fs-mini"><div className={"v " + signCls(c.agg.vega)}>{fmtGreek(c.agg.vega)}</div><div className="k">Vega / 1% IV</div></div>
              <div className="fs-mini"><div className={"v " + signCls(c.agg.gamma)}>{fmtGreek(c.agg.gamma)}</div><div className="k">Gamma</div></div>
            </div>
            <div className="fs-greekcap">{gs.theta} {gs.vega}</div>
          </div>

          <div className="fs-section">
            <div className="fs-slabel">
              {c.legs.length} {c.legs.length === 1 ? "leg" : "legs"} · {opts.length} option{opts.length === 1 ? "" : "s"}
            </div>
            <div className="fs-legs">
              {c.legs.length
                ? c.legs.map((l, i) => <FsLeg key={i} l={l} />)
                : <div className="fs-empty">Position closed · fully realized</div>}
            </div>
          </div>
        </div>
      </div>

      <div className="fs-foot">
        <button className="fs-nav" onClick={() => onStep(-1)}>←<span> Prev</span></button>
        <span className="fs-hint">← → step positions · Esc to exit</span>
        <button className="fs-nav" onClick={() => onStep(1)}><span>Next </span>→</button>
      </div>
    </div>,
    document.body,
  );
}

/* ---- right-click / hover context menu ---- */
export function FocusMenu({
  menu, onShow, onCopy, onClose,
}: {
  menu: { c: Company; x: number; y: number } | null;
  onShow: (t: string) => void;
  onCopy: (text: string, label: string) => void;
  onClose: () => void;
}) {
  useEffect(() => {
    const h = () => onClose();
    window.addEventListener("click", h);
    window.addEventListener("scroll", h, true);
    window.addEventListener("resize", h);
    return () => {
      window.removeEventListener("click", h);
      window.removeEventListener("scroll", h, true);
      window.removeEventListener("resize", h);
    };
  }, [onClose]);

  if (!menu) return null;
  const c = menu.c;
  const left = Math.min(menu.x, window.innerWidth - 232);
  const top = Math.min(menu.y, window.innerHeight - 188);
  return createPortal(
    <div className="lt-menu" style={{ left, top }} onClick={(e) => e.stopPropagation()}>
      <div className="lt-menu-h"><span className="t">{c.t}</span> · {c.name}</div>
      <button className="lt-mi primary" onClick={() => { onShow(c.t); onClose(); }}>
        <span className="g">⤢</span> Show in Large Type
      </button>
      <div className="lt-menu-div" />
      <button
        className="lt-mi"
        onClick={() => { onCopy("Net delta " + fmtGreek(c.agg.delta), "net delta"); onClose(); }}
      >
        <span className="g">Δ</span> Copy net delta
      </button>
      <button
        className="lt-mi"
        onClick={() => { onCopy("Open P&L " + fmtMoney(c.agg.unreal, true), "open P&L"); onClose(); }}
      >
        <span className="g">$</span> Copy open P&amp;L
      </button>
    </div>,
    document.body,
  );
}

export function FocusToast({ toast }: { toast: string | null }) {
  if (!toast) return null;
  return createPortal(
    <div className="lt-toast">✓ Copied {toast}</div>,
    document.body,
  );
}
