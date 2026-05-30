/**
 * Master Positions — TableView / CardsView / CockpitView.
 * Port of the handoff `mp-views.jsx`. Each takes filtered/sorted data
 * plus shared callbacks. Strict 1:1 with the prototype.
 */
import { useRef, useState } from "react";
import {
  type Company, type Leg, LEG_MAX,
  fmtMoney, fmtK, fmtPct, fmtNum, fmtGreek, signCls,
  eventText, eventFar, relExpiry, relDays, legLabel,
} from "./data";
import { DeltaBar, Flags, useEntered } from "./atoms";

const _ovChg = (v: number) =>
  (v >= 0 ? "+" : "−") + Math.abs(v * 100).toFixed(0) + "%";

/* fixed column widths so the header strip and every per-ticker table line up */
const COLW = [212, 78, 80, 84, 78, 62, 80, 72, 76, 62, 70, 62, 64, 112, 74, 124];
const TBL_MIN = COLW.reduce((a, b) => a + b, 0);
function PCols() {
  return (
    <colgroup>
      {COLW.map((w, i) => <col key={i} style={{ width: w + "px" }} />)}
    </colgroup>
  );
}

/* The shared header strip uses CSS grid (mirroring COLW) instead of an
   empty-body <table>, because some browsers refuse to honor a <colgroup>
   on a table with no <tbody> rows — that's the alignment bug seen
   in early PD-0 testing. Per-ticker tables below stay as real tables
   (they have real rows, so colgroup works there). */
const stripCols = COLW.map((w) => w + "px").join(" ");

function StripBand() {
  return (
    <div className="strip-band" style={{ gridTemplateColumns: stripCols }}>
      <div className="zh-spacer" />
      <div className="zh-basic" style={{ gridColumn: "span 7" }}>Basics &amp; P&amp;L</div>
      <div className="zh-greek" style={{ gridColumn: "span 4" }}>Greeks · position</div>
      <div className="zh-opt"   style={{ gridColumn: "span 3" }}>Options</div>
      <div className="zh-pos" />
    </div>
  );
}

function StripCols() {
  return (
    <div className="strip-cols" style={{ gridTemplateColumns: stripCols }}>
      <div className="l">Leg</div>
      <div className="ze-basic">Qty</div>
      <div>Avg</div>
      <div>Net cost</div>
      <div>Last</div>
      <div>1D</div>
      <div>Unreal</div>
      <div className="zr-basic">Real</div>
      <div className="ze-greek">Delta</div>
      <div>Gamma</div>
      <div>Theta</div>
      <div className="zr-greek">Vega</div>
      <div className="ze-opt">IV</div>
      <div>OI · Vol</div>
      <div className="zr-opt">Expiry</div>
      <div className="ze-pos">Position Δ</div>
    </div>
  );
}

/* Open-interest / volume cell with daily change + 4-day hover popover */
function OICell({ leg }: { leg: Leg }) {
  const [tip, setTip] = useState<{ left: number; top: number } | null>(null);
  const ref = useRef<HTMLTableCellElement>(null);
  if (!leg.oi) return <td className="z-opt muted">·</td>;
  const enter = () => {
    if (!ref.current) return;
    const r = ref.current.getBoundingClientRect();
    setTip({ left: r.right, top: r.top });
  };
  const bars = (hist: number[]) => {
    const mx = Math.max(...hist);
    return hist.map((v, i) => (
      <span key={i} className={"ov-bar-wrap" + (i === 3 ? " now" : "")}>
        <span className="ov-bar" style={{ height: (v / mx) * 100 + "%" }} />
      </span>
    ));
  };
  return (
    <td className="z-opt oivol-td" ref={ref} onMouseEnter={enter} onMouseLeave={() => setTip(null)}>
      <span className="oivol">
        <span className="ov-line">
          <span className="ov-k">OI</span>
          <span className="ov-v">{leg.oi.toLocaleString()}</span>
          <span className={"ov-c " + (leg.oiChg != null ? signCls(leg.oiChg) : "fg3")}>
            {leg.oiChg != null ? _ovChg(leg.oiChg) : "—"}
          </span>
        </span>
        <span className="ov-line">
          <span className="ov-k">Vol</span>
          <span className="ov-v">{(leg.vol ?? 0).toLocaleString()}</span>
          <span className={"ov-c " + (leg.volChg != null ? signCls(leg.volChg) : "fg3")}>
            {leg.volChg != null ? _ovChg(leg.volChg) : "—"}
          </span>
        </span>
      </span>
      {tip && leg.oiHist && leg.volHist && (
        <div className="ov-tip" style={{ position: "fixed", left: tip.left, top: tip.top }}>
          <div className="ov-tip-h">
            4-day flow · ${leg.strike} {leg.kind === "call" ? "call" : "put"}
          </div>
          <div className="ov-tip-row">
            <span className="ov-tip-k">OI</span>
            <span className="ov-bars">{bars(leg.oiHist)}</span>
            <span className="ov-tip-v">{leg.oi.toLocaleString()}</span>
          </div>
          <div className="ov-tip-row">
            <span className="ov-tip-k">Vol</span>
            <span className="ov-bars">{bars(leg.volHist)}</span>
            <span className="ov-tip-v">{(leg.vol ?? 0).toLocaleString()}</span>
          </div>
          <div className="ov-tip-days">
            <span>3d</span><span>2d</span><span>1d</span><span>now</span>
          </div>
        </div>
      )}
    </td>
  );
}

/* ============================================================
   A · DENSE EXCEL TABLE
   ============================================================ */
export function TableView({
  data, onFocusMenu,
}: {
  data: Company[];
  onFocusMenu?: (c: Company, x: number, y: number) => void;
}) {
  const num = (v: number, d = 0) => (v === 0 ? "·" : fmtNum(v, d));
  return (
    <div className="tbl-wrap zone-C">
      <div className="tbl-scroll">
        <div className="tbl-stack" style={{ minWidth: TBL_MIN }}>

          {/* Shared header strip — div-grid, NOT an empty <table>, so its
              column widths line up to the pixel with the per-ticker tables
              below (see StripBand / StripCols above). */}
          <div className="ptable-strip">
            <StripBand />
            <StripCols />
          </div>

          {data.map((c) => {
            const attn = c.flags.some((f) => f.tone === "neg");
            return (
              <div className={"ptbl-card" + (attn ? " attn" : "") + (c.closed ? " closed" : "")} key={c.t}>
                <table className="ptable">
                  <PCols />
                  <tbody>
                    <tr
                      className="co-head"
                      onContextMenu={(e) => {
                        e.preventDefault();
                        onFocusMenu?.(c, e.clientX, e.clientY);
                      }}
                    >
                      <td className="l" colSpan={16}>
                        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 18, flexWrap: "wrap" }}>
                          <div className="co-id">
                            <span className="t">{c.t}</span>
                            <span className="nm">{c.name}</span>
                            <span className="nm">· {c.sector}</span>
                            <span className={"strat " + c.strat}>{c.strat}</span>
                          </div>
                          <div className="co-meta">
                            <span className="px">${c.spot.toFixed(2)}</span>
                            <span className={signCls(c.day)}>{fmtPct(c.day)}</span>
                            <span className={"ev" + (eventFar(c) ? " far" : "")}>{eventText(c)}</span>
                            <Flags flags={c.flags} max={3} />
                            <button
                              className="co-focus"
                              title="Show in Large Type — or right-click the row"
                              onClick={(e) => {
                                e.stopPropagation();
                                const r = e.currentTarget.getBoundingClientRect();
                                onFocusMenu?.(c, r.right, r.bottom + 4);
                              }}
                            >
                              ⤢ Focus <span className="cv">⌄</span>
                            </button>
                          </div>
                        </div>
                      </td>
                    </tr>

                    {c.legs.map((l, li) => {
                      const lab = legLabel(l);
                      const compact = l.kind === "stock"
                        ? "Stock"
                        : "$" + l.strike + " " + (l.kind === "call" ? "C" : "P");
                      const qty = l.kind === "stock"
                        ? l.qty.toLocaleString() + " sh"
                        : (l.qty > 0 ? "+" : "−") + Math.abs(l.qty);
                      const netCost = l.kind === "stock" && l.qty !== 0
                        ? l.avg - l.real / l.qty
                        : null;
                      return (
                        <tr className="leg" key={li}>
                          <td className="l">
                            <span className="leg-id">
                              <span className={"leg-glyph " + lab.tone}>{lab.glyph}</span>
                              <span className="leg-name">
                                {compact}
                                {lab.side && <span className="side">{lab.side}</span>}
                              </span>
                            </span>
                          </td>
                          <td className="z-basic ze-basic dim">{qty}</td>
                          <td className="z-basic dim">${l.avg.toFixed(2)}</td>
                          <td className={"z-basic " + (netCost != null ? "neon" : "muted")}>
                            {netCost != null ? "$" + netCost.toFixed(2) : "·"}
                          </td>
                          <td className="z-basic">${l.last.toFixed(2)}</td>
                          <td className={"z-basic " + (l.kind === "stock" && l.day != null ? signCls(l.day) : "muted")}>
                            {l.kind === "stock" && l.day != null ? fmtPct(l.day) : "·"}
                          </td>
                          <td className={"z-basic " + signCls(l.unreal)}>{fmtK(l.unreal)}</td>
                          <td className={"z-basic zr-basic " + (l.real ? signCls(l.real) : "muted")}>
                            {l.real ? fmtK(l.real) : "·"}
                          </td>
                          <td className="z-greek ze-greek">{fmtGreek(l.delta)}</td>
                          <td className={"z-greek " + (l.gamma ? "" : "muted")}>{num(l.gamma)}</td>
                          <td className={"z-greek " + (l.theta ? signCls(l.theta) : "muted")}>{num(l.theta)}</td>
                          <td className={"z-greek zr-greek " + (l.vega ? signCls(l.vega) : "muted")}>{num(l.vega)}</td>
                          <td className={"z-opt ze-opt " + (l.iv ? "dim" : "muted")}>
                            {l.iv ? l.iv.toFixed(1) + "%" : "·"}
                          </td>
                          <OICell leg={l} />
                          <td className={"z-opt zr-opt " + (l.dte != null ? (l.dte <= 6 ? "warn" : "dim") : "muted")}>
                            {l.dte != null ? relExpiry(l.dte) : "·"}
                          </td>
                          <td className="z-pos ze-pos barcell">
                            <span className="posd-cell">
                              <span className="pd-bar">
                                <DeltaBar value={l.delta} max={LEG_MAX} showVal={false} h={8} />
                              </span>
                            </span>
                          </td>
                        </tr>
                      );
                    })}

                    <tr className="agg">
                      <td className="l">
                        <span className="agg-lbl">{c.closed ? "Closed · " : "Net · "}{c.t}</span>
                      </td>
                      <td className="z-basic ze-basic muted">·</td>
                      <td className="z-basic muted">·</td>
                      <td className="z-basic muted">·</td>
                      <td className="z-basic strong">${c.spot.toFixed(2)}</td>
                      <td className={"z-basic " + signCls(c.day)}>{fmtPct(c.day)}</td>
                      <td className={"z-basic " + signCls(c.agg.unreal) + " strong"}>{fmtK(c.agg.unreal)}</td>
                      <td className={"z-basic zr-basic " + (c.agg.real ? signCls(c.agg.real) : "muted")}>
                        {c.agg.real ? fmtK(c.agg.real) : "·"}
                      </td>
                      <td className="z-greek ze-greek strong">{fmtGreek(c.agg.delta)}</td>
                      <td className="z-greek">{fmtGreek(c.agg.gamma)}</td>
                      <td className={"z-greek " + signCls(c.agg.theta)}>{fmtGreek(c.agg.theta)}</td>
                      <td className={"z-greek zr-greek " + signCls(c.agg.vega)}>{fmtGreek(c.agg.vega)}</td>
                      <td className="z-opt ze-opt muted">·</td>
                      <td className="z-opt muted">·</td>
                      <td className="z-opt zr-opt muted">·</td>
                      <td className="z-pos ze-pos">
                        <span className="posd pd-num neon">{fmtGreek(c.agg.delta)}</span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   B · CARDS
   ============================================================ */
export function CardsView({ data }: { data: Company[] }) {
  return (
    <div className="card-grid">
      {data.map((c) => {
        const attn = c.flags.some((f) => f.tone === "neg");
        return (
          <div className={"pcard" + (attn ? " attn" : "")} key={c.t} style={c.closed ? { opacity: 0.55 } : undefined}>
            <div className="pc-head">
              <div className="pc-id">
                <div className="t">{c.t}</div>
                <div className="nm">
                  <span>{c.name}</span>
                  <span className={"pc-strat " + c.strat}>{c.strat}</span>
                </div>
              </div>
              <div className="pc-px">
                <div className="v">${c.spot.toFixed(2)}</div>
                <div className={"ch " + signCls(c.day)}>{fmtPct(c.day)}</div>
                <div className={"pc-ev" + (eventFar(c) ? " far" : "")}>
                  {c.event.kind === "none" ? c.event.label : c.event.label + " · " + relDays(c.event.days)}
                </div>
              </div>
            </div>

            {c.flags.length > 0 && (
              <div className="pc-flags top"><Flags flags={c.flags} /></div>
            )}

            <div className="pc-legs">
              {c.legs.length === 0 ? (
                <div className="pc-leg" style={{ color: "var(--fg3)", fontStyle: "normal" }}>
                  <span className="lg" style={{ color: "var(--fg3)" }}>Position closed · fully realized</span>
                  <span /><span /><span />
                </div>
              ) : (
                <>
                  <div className="pc-leg headrow">
                    <span className="v head" style={{ textAlign: "left" }}>Leg</span>
                    <span className="v head">Qty</span>
                    <span className="v head">Mark</span>
                    <span className="v head">Unreal</span>
                  </div>
                  {c.legs.map((l, i) => {
                    const lab = legLabel(l);
                    const qty = l.kind === "stock"
                      ? l.qty.toLocaleString()
                      : (l.qty > 0 ? "+" : "−") + Math.abs(l.qty);
                    return (
                      <div className="pc-leg" key={i}>
                        <span className="lg">
                          <span className={"leg-glyph " + lab.tone}>{lab.glyph}</span>
                          <span style={{ color: "var(--fg1)" }}>{l.kind === "stock" ? "Stock" : lab.main}</span>
                          {l.dte != null && (
                            <span style={{ color: "var(--fg4)", fontSize: 9 }}>{relExpiry(l.dte)}</span>
                          )}
                        </span>
                        <span className="v">{qty}</span>
                        <span className="v">${l.last.toFixed(2)}</span>
                        <span className={"v " + signCls(l.unreal)}>{fmtK(l.unreal)}</span>
                      </div>
                    );
                  })}
                </>
              )}
            </div>

            <div className="pc-greeks">
              {([
                ["Delta", c.agg.delta, false, ""],
                ["Gamma", c.agg.gamma, false, ""],
                ["Theta", c.agg.theta, true, " /day"],
                ["Vega", c.agg.vega, true, " /1%"],
              ] as const).map(([k, v, col, suf]) => (
                <div className="pc-gk" key={k}>
                  <div className="k">{k}{suf}</div>
                  <div className={"v " + (col ? signCls(v) : "")}>{fmtGreek(v)}</div>
                </div>
              ))}
            </div>

            <div className="pc-foot">
              <div className="net">
                <div className="k">Net P&amp;L</div>
                <div className={"v " + signCls(c.agg.net)}>{fmtMoney(c.agg.net, true)}</div>
              </div>
              <div className="posd-wrap">
                <div className="k">◆ Position delta</div>
                <div className="v">{fmtGreek(c.agg.delta)}</div>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

/* ============================================================
   C · DELTA EXPOSURE COCKPIT
   ============================================================ */
export function CockpitView({ data }: { data: Company[] }) {
  const AX = 2200;
  const toPct = (v: number) => 50 + (v / AX) * 50;
  const ticks = [-2000, -1000, 0, 1000, 2000];
  const entered = useEntered(150);

  return (
    <div className="cockpit">
      <div className="ck-axis-head">
        <span className="lbl">Position · net delta</span>
        <div className="ck-scale">
          {ticks.map((t) => (
            <span key={t} className={"tk" + (t === 0 ? " zero" : "")} style={{ left: toPct(t) + "%" }}>
              {t === 0 ? "0" : (t > 0 ? "+" : "−") + Math.abs(t / 1000) + "k"}
            </span>
          ))}
        </div>
        <span className="lbl" style={{ textAlign: "right" }}>Theta / Vega · risk</span>
      </div>
      <div className="ck-caption">
        Each bar is a leg's contribution to position delta — width = size of delta, left of zero = short / negative, right = long. Not profit, not open vs close.
      </div>

      {data.map((c) => {
        const attn = c.flags.some((f) => f.tone === "neg");
        let posAcc = 0, negAcc = 0;
        const segs = c.legs.map((l) => {
          const w = (Math.abs(l.delta) / AX) * 50;
          let leftPct: number;
          if (l.delta >= 0) {
            leftPct = 50 + (posAcc / AX) * 50;
            posAcc += l.delta;
          } else {
            negAcc += l.delta;
            leftPct = 50 + (negAcc / AX) * 50;
          }
          return { l, w, leftPct };
        });
        return (
          <div
            className={"ck-row" + (attn ? " attn" : "")}
            key={c.t}
            style={c.closed ? { opacity: 0.5 } : undefined}
          >
            <div className="ck-id">
              <div className="top">
                <span className="t">{c.t}</span>
                <span className={"net " + signCls(c.agg.net)}>{fmtK(c.agg.net)}</span>
              </div>
              <span className="meta">
                {c.strat} · {c.legs.length} legs · {c.event.kind === "none" ? "closed" : relDays(c.event.days)}
              </span>
            </div>

            <div className="ck-track">
              <span className="ck-zero" style={{ left: "50%" }} />
              {segs.map((s, i) => {
                const lab = legLabel(s.l);
                return (
                  <span
                    key={i}
                    className={"ck-seg " + lab.tone}
                    style={{
                      left: entered ? s.leftPct + "%" : "50%",
                      width: entered ? s.w + "%" : "0%",
                    }}
                    title={lab.main + " · Δ " + fmtGreek(s.l.delta)}
                  >
                    {s.w > 7 && (
                      <span className="seglab">{s.l.kind === "stock" ? "STOCK" : lab.glyph}</span>
                    )}
                  </span>
                );
              })}
              <span
                className="ck-net-mark"
                style={{ left: entered ? toPct(c.agg.delta) + "%" : "50%" }}
              >
                <span className="nm-val">{fmtGreek(c.agg.delta)}</span>
              </span>
            </div>

            <div className="ck-rail">
              <div className="ck-gk">
                <div className="k">Theta</div>
                <div className={"v " + signCls(c.agg.theta)}>{fmtGreek(c.agg.theta)}</div>
              </div>
              <div className="ck-gk">
                <div className="k">Vega</div>
                <div className={"v " + signCls(c.agg.vega)}>{fmtGreek(c.agg.vega)}</div>
              </div>
              <div className="ck-flags">
                {c.flags.length ? <Flags flags={c.flags} max={3} /> : <span className="flag">clear</span>}
              </div>
            </div>
          </div>
        );
      })}

      <div className="ck-legend">
        <span className="lg"><span className="sw stock" />stock delta</span>
        <span className="lg"><span className="sw c-short" />short call</span>
        <span className="lg"><span className="sw p-short" />short put</span>
        <span className="lg"><span className="sw c-long" />long call</span>
        <span className="lg"><span className="sw p-long" />long put</span>
        <span className="lg" style={{ marginLeft: "auto" }}>│ white mark = net position delta</span>
      </div>
    </div>
  );
}
