const { useState, useEffect, useRef } = React;
const Roll = window.Roll, useTween = window.useTween;

const usd = (n) => {
  const a = Math.abs(n);
  if (a >= 1e6) return "$" + (n / 1e6).toFixed(a >= 1e7 ? 1 : 2).replace(/\.0+$/, "") + "M";
  return "$" + Math.round(n).toLocaleString("en-US");
};

/* Leg vocabulary — two axes, monochrome so it never competes with the direction hue.
   Shape: ▲ call (up) · ▼ put (down).  Fill: solid = sold/credit · hollow = bought/debit.
   Reinforced by the card spine: solid rule = short, dashed rule = long. */
const MARK = { "call/short": "▲", "call/long": "△", "put/short": "▼", "put/long": "▽" };
const mark = (kind, side) => MARK[kind + "/" + side];

/* direction carries the hue — fire when it moves against you, flood when it moves for you.
   Arrow sits beside the figure, sized to it, same hue. Flat reads · (Score Unit idiom). */
const HUE = { down: "var(--ink-peril-fire)", up: "var(--ink-peril-flood)", flat: "var(--ink-dim)" };

function Dir({ up, flat, size, children }) {
  const hue = flat ? HUE.flat : up ? HUE.up : HUE.down;
  const s = size || 17;
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: s > 24 ? 9 : 6, fontFamily: "var(--ink-font-mono)", color: hue }}>
      <span><Roll>{children}</Roll></span>
      <span style={{ fontSize: s * 0.82, lineHeight: 1, fontWeight: 400 }}>{flat ? "·" : up ? "↑" : "↓"}</span>
    </span>
  );
}

/* Law 1 — severity is typography: filled → outlined → faint. An elevated state may take a
   16% hue tint, the way the Score Unit bands its live score. */
function Band({ severity, hue, children }) {
  const base = { fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".14em", textTransform: "uppercase", padding: "5px 11px", borderRadius: 999, whiteSpace: "nowrap", flex: "none" };
  const skin = hue
    ? { background: "color-mix(in srgb, " + hue + " 16%, transparent)", color: hue }
    : severity === "mod" ? { border: "1px solid var(--ink-dim)", color: "var(--ink-text)" }
    : { background: "color-mix(in srgb, var(--ink-text) 8%, transparent)", color: "var(--ink-dim)" };
  return <span style={{ ...base, ...skin }}>{children}</span>;
}

function Eyebrow({ n, cat, mark: m, right }) {
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, minHeight: 24 }}>
      <span style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 0, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".18em", textTransform: "uppercase", color: "var(--ink-dim)" }}>
        {m}<span>{n} · {cat}</span>
      </span>
      {right}
    </div>
  );
}

function Hero({ v, unit }) {
  return (
    <div style={{ marginTop: 24 }}>
      <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 44, fontWeight: 300, letterSpacing: "-.04em", lineHeight: 1, color: "var(--ink-text)" }}><Roll>{v}</Roll></div>
      {unit ? <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)", marginTop: 12 }}>{unit}</div> : null}
    </div>
  );
}

/* Numbers in prose go mono — Ink's Figure treatment */
const FIG_RE = /\$?\d[\d,.–−-]*%?(?:\s(?:ct|sh|pts))?(?!\w)/g;
function Fig({ children }) {
  const s = String(children), out = [];
  let last = 0;
  for (const m of s.matchAll(FIG_RE)) {
    if (m.index > last) out.push(s.slice(last, m.index));
    out.push(<span key={m.index} style={{ fontFamily: "var(--ink-font-mono)", color: "var(--ink-text)" }}>{m[0]}</span>);
    last = m.index + m[0].length;
  }
  if (last < s.length) out.push(s.slice(last));
  return out;
}

function Bullets({ items }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 9, marginTop: 18 }}>
      {items.map((t) => (
        <div key={t} style={{ display: "flex", alignItems: "baseline", gap: 9, fontSize: 12.5, fontWeight: 300, lineHeight: 1.35, color: "var(--ink-dim)" }}>
          <span style={{ flex: "none", width: 4, height: 4, borderRadius: "50%", background: "var(--ink-dim)", transform: "translateY(-3px)" }} />
          <span><Fig>{t}</Fig></span>
        </div>
      ))}
    </div>
  );
}

function Band3({ items }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(" + items.length + ",1fr)", borderTop: "1px solid var(--ink-hair)", marginTop: 20 }}>
      {items.map((m, i) => (
        <div key={m.k} style={{ padding: i === 0 ? "16px 12px 0 0" : "16px 12px 0", borderLeft: i ? "1px solid var(--ink-hair)" : "none", minWidth: 0 }}>
          <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 8.5, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--ink-dim)", whiteSpace: "nowrap" }}>{m.k}</div>
          <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 17, fontWeight: 400, letterSpacing: "-.02em", marginTop: 10, color: "var(--ink-text)" }}><Roll delay={120}>{m.v}</Roll></div>
        </div>
      ))}
    </div>
  );
}

/* the highlighted bottom zone — canvas inset under the card surface */
function Foot({ sm, flat, h, children }) {
  return (
    <div className="cardfoot" style={{ background: "transparent", borderTop: flat ? "none" : "1px solid var(--ink-hair)", padding: sm ? "14px 18px" : "18px 22px", height: h || (sm ? 96 : 132), boxSizing: "border-box", display: "flex", flexDirection: "column", justifyContent: "center", gap: sm ? 10 : 14 }}>
      {children}
    </div>
  );
}

function Bars({ leftK, leftV, rightK, rightV, net, hue }) {
  const max = Math.max(leftV, rightV, 1);
  const t = useTween(900, 140);
  const line = (k, v, strong) => (
    <div key={k} style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <span style={{ flex: "0 0 62px", fontFamily: "var(--ink-font-mono)", fontSize: 8.5, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--ink-dim)" }}>{k}</span>
      <span style={{ flex: 1, minWidth: 0, height: 7, borderRadius: 4, background: "var(--ink-hair)", position: "relative" }}>
        <b style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: (v / max) * 100 * t + "%", borderRadius: 4, background: strong ? "var(--ink-dim)" : hue }} />
      </span>
      <span style={{ flex: "0 0 auto", minWidth: 74, textAlign: "right", whiteSpace: "nowrap", fontFamily: "var(--ink-font-mono)", fontSize: 12, color: strong ? "var(--ink-text)" : hue }}><Roll delay={140}>{usd(v)}</Roll></span>
    </div>
  );
  return (
    <React.Fragment>
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 10 }}>
        <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>{leftK} vs {rightK}</span>
        <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 17, fontWeight: 500, letterSpacing: "-.02em", color: "var(--ink-text)" }}>{net}</span>      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 11 }}>
        {line(leftK, leftV, true)}
        {line(rightK, rightV, false)}
      </div>
    </React.Fragment>
  );
}

/* three-line variant — where the capital sits, one bar a sleeve.
   Credit (premium collected) takes the up hue: it comes back to you. */
function Bars3({ label, rows, net }) {
  const max = Math.max(...rows.map((r) => r.v), 1);
  const t = useTween(900, 140);
  return (
    <React.Fragment>
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 10 }}>
        <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>{label}</span>
        <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 17, fontWeight: 500, letterSpacing: "-.02em", color: "var(--ink-text)" }}>{net}</span>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        {rows.map((r) => (
          <div key={r.k} style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span style={{ flex: "0 0 86px", fontFamily: "var(--ink-font-mono)", fontSize: 8.5, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--ink-dim)", whiteSpace: "nowrap" }}>{r.k}</span>
            <span style={{ flex: 1, minWidth: 0, height: 7, borderRadius: 4, background: "var(--ink-hair)", position: "relative" }}>
              <b style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: Math.max(2, (r.v / max) * 100) * t + "%", borderRadius: 4, background: r.credit ? HUE.up : "var(--ink-dim)" }} />
            </span>
            <span style={{ flex: "0 0 auto", minWidth: 66, textAlign: "right", whiteSpace: "nowrap", fontFamily: "var(--ink-font-mono)", fontSize: 12, color: r.credit ? HUE.up : "var(--ink-text)" }}><Roll delay={140}>{(r.credit ? "+" : "") + usd(r.v)}</Roll></span>
          </div>
        ))}
      </div>
    </React.Fragment>
  );
}

/* freshness stamp — Ink's data-freshness pattern: pulsing fire dot = live,
   amber = delayed with a next-update time, hollow dim ring = stale. */
function Stamp({ state, text, sm, flat }) {
  const dot = state === "live"
    ? { background: "var(--ink-peril-fire)", animation: "ink-pulse 2.5s infinite" }
    : state === "delayed"
    ? { background: "var(--ink-peril-severe)" }
    : { border: "1.5px solid var(--ink-dim)" };
  return (
    <div className="cardfoot" style={{ background: "transparent", borderTop: flat ? "none" : "1px solid var(--ink-hair)", padding: sm ? "0 18px" : "0 22px", height: 30, flex: "none", display: "flex", alignItems: "center", gap: 8 }}>
      <span style={{ width: 6, height: 6, borderRadius: "50%", flex: "none", boxSizing: "border-box", ...dot }} />
      <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 8.5, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--ink-dim)", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>{text}</span>
    </div>
  );
}

function Card({ rank, spine, sm, h, children }) {
  const edge = spine === "short" ? { borderLeft: "2px solid var(--ink-text)" } : spine === "long" ? { borderLeft: "2px dashed var(--ink-dim)" } : {};
  return (
    <section data-relevance={rank} style={{ flex: "none", width: sm ? 306 : 348, height: h || (sm ? 374 : 530), scrollSnapAlign: "start", display: "flex", flexDirection: "column", background: "var(--ink-surface)", border: "1px solid var(--ink-hair)", ...edge, borderRadius: "var(--ink-radius-card)", overflow: "hidden" }}>
      {children}
    </section>
  );
}

function Body({ sm, children }) {
  return <div style={{ flex: 1, minHeight: 0, padding: sm ? "20px 18px 22px" : "22px 22px 24px", display: "flex", flexDirection: "column" }}>{children}</div>;
}

/* ---------- section 2 · how it has performed ---------- */

function Split({ av, bv }) {
  const rows = [["Realized", av], ["Unrealized", bv]];
  return (
    <React.Fragment>
      {rows.map(([k, v]) => (
        <div key={k} style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 10 }}>
          <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>{k}</span>
          <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 15, color: v < 0 ? HUE.down : "var(--ink-text)" }}><Roll delay={120}>{(v < 0 ? "−" : "") + usd(Math.abs(v))}</Roll></span>
        </div>
      ))}
    </React.Fragment>
  );
}

function ProfitCard() {
  const p = window.perf;
  return (
    <Card rank="r1" sm>
      <Body sm>
        <Eyebrow n="01" cat="Total profit" right={<Band severity="mod">Lifetime</Band>} />
        <div style={{ marginTop: 22 }}>
          <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 38, fontWeight: 300, letterSpacing: "-.04em", lineHeight: 1 }}><Roll>{usd(p.realized)}</Roll></div>
          <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)", marginTop: 11 }}>Realized · options &amp; shares</div>
        </div>
        <Bullets items={[usd(p.lifetime) + " with open premium · " + p.perShare + " a share (" + p.perSharePct + ")", "Cost basis $" + p.costBasis.toFixed(2) + " → break-even $" + p.breakEven.toFixed(2)]} />
        <div style={{ flex: 1 }} />
      </Body>
      <Foot sm>
        <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>Cushion · spot over break-even</div>
        <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 12 }}>
          <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 28, fontWeight: 300, letterSpacing: "-.035em" }}><Dir up size={28}>{p.cushion}</Dir></span>
          <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 11.5, color: "var(--ink-dim)" }}>{p.cushionPct}</span>
        </div>
      </Foot>
      <Stamp state="delayed" text="Updated 16:00 · next at close" sm />
    </Card>
  );
}

function SleevePerfCard({ s, n }) {
  const net = s.realized + s.unrealized;
  return (
    <Card rank={s.empty ? "r3" : "r1"} spine={s.side} sm>
      <Body sm>
        <Eyebrow
          n={n}
          mark={<span style={{ fontSize: 12, lineHeight: 1, flex: "none" }}>{mark(s.kind, s.side)}</span>}
          cat={s.name}
          right={<Band severity="low">{s.total}</Band>}
        />
        <div style={{ marginTop: 22 }}>
          <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 38, fontWeight: 300, letterSpacing: "-.04em", lineHeight: 1 }}>
            {s.empty ? "—" : <Dir up={net >= 0} size={38}>{usd(Math.abs(net))}</Dir>}
          </div>
          <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)", marginTop: 11 }}>{s.empty ? "never written" : "realized + open"}</div>
        </div>
        <div style={{ flex: 1 }} />
        <Band3 items={[{ k: "Contracts", v: s.empty ? "0" : s.total }, { k: s.basisK, v: s.empty ? "—" : usd(s.basis) }]} />
      </Body>
      <Foot sm>
        {s.empty
          ? <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--ink-dim)" }}>No puts written to date</div>
          : <Split av={s.realized} bv={s.unrealized} />}
      </Foot>
      <Stamp state="delayed" text="Updated 16:00 · next at close" sm />
    </Card>
  );
}

/* ---------- the eleven cards ---------- */

function SummaryCard({ px, onPlan }) {
  const s = window.summary;
  return (
    <Card rank="r1">
      <Body>
        <Eyebrow n="01" cat="Summary" right={<Band severity="mod">Net long</Band>} />        <Hero v={s.delta} unit={s.deltaUnit} />
        <Bullets items={["Calls + puts hedge most of 5,001 sh", "Theta drops sharply after Jul 27"]} />
        <div style={{ flex: 1 }} />
        <Band3 items={[{ k: "Gamma", v: s.gamma }, { k: "Theta", v: s.theta }, { k: "Spot", v: "$" + px.toFixed(2) }]} />
      </Body>
      <Foot>
        <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", gap: 14 }}>
          <div>
            <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>Current P&amp;L · unrealized</div>
            <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 30, fontWeight: 300, letterSpacing: "-.035em", marginTop: 10 }}><Dir size={30}>{s.pnl.replace("−", "")}</Dir></div>
            <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 10, letterSpacing: ".04em", color: "var(--ink-dim)", marginTop: 9 }}>Shares $11,709 · options $6,194</div>
          </div>
          <button title="Plan" onClick={onPlan} style={{ flex: "none", width: 44, height: 44, display: "flex", alignItems: "center", justifyContent: "center", borderRadius: "var(--ink-radius-element)", background: "var(--ink-invert-bg)", color: "var(--ink-invert-text)", border: "none", cursor: "pointer" }}>
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M8 4v13M8 4L5 7M8 4l3 3" /><path d="M16 20V7M16 20l3-3M16 20l-3-3" /></svg>
          </button>
        </div>
      </Foot>
      <Stamp state="live" text="Updated now · streaming" />
    </Card>
  );
}

function SleeveCard() {
  const s = window.summary;
  return (
    <Card rank="r1">
      <Body>
        <Eyebrow n="02" cat="Total position" right={<Band severity="low">4 sleeves</Band>} />        <Hero v="5,001" unit="shares held · 111 contracts open" />
        <div style={{ flex: 1 }} />
        <div style={{ display: "flex", flexDirection: "column" }}>
          {s.sleeves.map((x) => (
            <div key={x.name} style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 12, padding: "13px 0", borderTop: "1px solid var(--ink-hair)" }}>
              <span style={{ display: "flex", alignItems: "center", gap: 9, fontSize: 13.5, fontWeight: 300 }}>
                <span style={{ fontSize: 11, lineHeight: 1, flex: "none" }}>{x.name === "Shares" ? "○" : mark(x.name.startsWith("Calls") ? "call" : "put", x.side)}</span>
                {x.name}
              </span>
              <span style={{ display: "flex", alignItems: "baseline", gap: 12, fontFamily: "var(--ink-font-mono)", fontSize: 12 }}>
                <span style={{ color: "var(--ink-dim)" }}><Roll delay={100}>{x.qty}</Roll></span>
                <span style={{ minWidth: 84, textAlign: "right", whiteSpace: "nowrap" }}><Roll delay={100}>{x.basis}</Roll></span>
              </span>
            </div>
          ))}
        </div>
      </Body>
      <Foot>
        <Bars3
          label="Where the capital sits"
          rows={[
            { k: "Shares", v: 1046116 },
            { k: "Options bought", v: 35600 + 541989 },
            { k: "Options sold", v: 10600, credit: true },
          ]}
          net={<Dir>$1,613,105</Dir>}
        />
      </Foot>
      <Stamp state="live" text="Updated now · streaming" />
    </Card>
  );
}

function SharesCard({ px }) {
  const h = window.shares;
  return (
    <Card rank="r1">
      <Body>
        <Eyebrow n="03" cat="Shares · long" right={<Band hue={HUE.down}>1.12% vs avg</Band>} />
        <Hero v={"$" + px.toFixed(2)} unit="live spot · nvda" />
        <Bullets items={["Break-even $207.06 after premium", "$2.12 a share collected, calls only"]} />
        <div style={{ flex: 1 }} />
        <Band3 items={[{ k: "Average buy", v: "$" + h.avgBuy.toFixed(2) }, { k: "New average", v: "$" + h.newAvg.toFixed(2) }, { k: "Quantity", v: h.qty }]} />
      </Body>
      <Foot>
        <Bars leftK="Paid" leftV={h.paid} rightK="Value now" rightV={h.value} net={<Dir>$11,709</Dir>} hue={HUE.down} />
      </Foot>
      <Stamp state="live" text="Updated now · streaming" />
    </Card>
  );
}

/* The strike is the contract's name, not its state — it sits on the identity line, underlined.
   The hero is the number that streams: the live mark, per contract. The gap between what you
   collected and what it costs to close already lives in the footer bars — one number per zone. */
function LiveHero({ s, short, glyph }) {
  const entry = s.basis / (s.ct * 100);
  const now = parseFloat(s.mark);
  const pct = entry ? ((now - entry) / entry) * 100 : 0;
  const good = short ? now <= entry : now >= entry;
  const flat = Math.abs(pct) < 0.05;
  return (
    <div style={{ marginTop: 20 }}>
      <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--ink-dim)", whiteSpace: "nowrap" }}>
        <span style={{ color: "var(--ink-text)", textDecoration: "underline", textDecorationColor: "var(--ink-hair)", textUnderlineOffset: 4 }}>${s.strike}</span> · {s.expiry} · {s.dte}
      </div>
      <div style={{ marginTop: 16, display: "flex", alignItems: "center", gap: 14, minHeight: 44 }}>
        <span style={{ fontSize: 22, lineHeight: 1, flex: "none" }}>{glyph}</span>
        <div style={{ minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
            <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 44, fontWeight: 300, letterSpacing: "-.04em", lineHeight: 1 }}>$<Roll>{s.mark}</Roll></span>
            <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 12, color: flat ? HUE.flat : good ? HUE.up : HUE.down, whiteSpace: "nowrap" }}>{flat ? "·" : (pct > 0 ? "+" : "−") + Math.abs(pct).toFixed(1) + "%"}</span>
          </div>
          <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)", marginTop: 12 }}>
            {"Mark now · " + (short ? "sold at " : "paid ") + "$" + entry.toFixed(2)}
          </div>
        </div>
      </div>
    </div>
  );
}

function StrikeCard({ leg, s, n, px, onRoll }) {
  const short = leg.side === "short";
  const expired = s.dte === "expired";
  const basisK = short ? "Collected" : "Paid";
  const curK = short ? "To close" : "Value now";
  const net = short ? s.basis - s.current : s.current - s.basis;
  const netStr = <Dir up={net >= 0}>{usd(Math.abs(net))}</Dir>;
  const days = expired ? 0 : parseInt(s.dte, 10);
  const rank = expired || days <= 7 ? "r1" : days <= 200 ? "r2" : "r3";
  const glyph = mark(leg.kind, short ? "short" : "long");
  const spot = px || parseFloat(window.SPOT);
  const gapToSpot = parseFloat(s.strike) - spot;
  const roll = window.rollFor(leg, s, spot);
  return (
    <div style={{ position: "relative", flex: "none" }}>
    <div style={{ position: "relative", zIndex: 1 }}>
    <Card rank={rank} spine={short ? "short" : "long"}>
      <Body>
        <Eyebrow
          n={n}
          mark={<span style={{ fontSize: 12, lineHeight: 1, flex: "none" }}>{glyph}</span>}
          cat={(leg.kind === "call" ? "Call" : "Put") + " " + (short ? "sold" : "bought")}
          right={<Band severity={expired ? undefined : s.moneyness === "ITM" ? "mod" : "low"} hue={expired ? HUE.down : null}>{expired ? "Expired ITM" : s.moneyness}</Band>}
        />
        {expired
          ? <div style={{ marginTop: 24, display: "flex", alignItems: "center", gap: 14 }}>
              <span style={{ fontSize: 22, lineHeight: 1, flex: "none" }}>{glyph}</span>
              <div>
                <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 44, fontWeight: 300, letterSpacing: "-.04em", lineHeight: 1 }}>$<Roll>{s.strike}</Roll></div>
                <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)", marginTop: 12 }}>{s.expiry} · {s.dte} · no live mark</div>
              </div>
            </div>
          : <LiveHero s={s} short={short} glyph={glyph} />}
        <Bullets items={expired
          ? ["Assigned in all likelihood", "Reconcile before it skews the sleeve"]
          : [
              "Spot $" + spot.toFixed(2) + " · $" + Math.abs(gapToSpot).toFixed(2) + (gapToSpot >= 0 ? " below" : " above") + " strike",
              s.ct + " ct × $" + s.mark + " = " + usd(s.current) + (short ? " to close" : " of value"),
            ]} />
        <div style={{ flex: 1 }} />
        <Band3 items={[{ k: "Contracts", v: s.ct }, { k: "Delta", v: s.delta }, { k: "Theta", v: s.theta }]} />
      </Body>
      <Foot>
        <Bars leftK={basisK} leftV={s.basis} rightK={curK} rightV={s.current} net={netStr} hue={net >= 0 ? HUE.up : HUE.down} />
      </Foot>
      {expired
        ? <Stamp state="stale" text="Stale · next at broker sync" />
        : <Stamp state="live" text="Updated now · streaming" />}
    </Card>
    </div>
    {roll ? <window.RollSlip r={roll} onOpen={() => onRoll && onRoll(roll)} /> : null}
    </div>
  );
}

/* ---------- section 3 · insights ---------- */

/* zone gauge — Ink's radial gauge: 9px arc, hair track, score centred in mono */
function Gauge({ value, suffix }) {
  const LEN = 314;
  const t = useTween(1000, 120);
  const v = value * t;
  return (
    <div style={{ position: "relative", width: 150, alignSelf: "center", marginTop: 14 }}>
      <svg viewBox="0 8 240 150" width="100%" style={{ display: "block" }}>
        <path d="M20 134 A100 100 0 0 1 220 134" fill="none" stroke="var(--ink-hair)" strokeWidth="9" strokeLinecap="round" />
        <path d="M20 134 A100 100 0 0 1 220 134" fill="none" stroke="var(--ink-text)" strokeWidth="9" strokeLinecap="round" strokeDasharray={(v / 100) * LEN + " 500"} />
      </svg>
      <span style={{ position: "absolute", left: 0, right: 0, bottom: 8, textAlign: "center", fontFamily: "var(--ink-font-mono)", fontSize: 34, fontWeight: 300, letterSpacing: "-.03em" }}>{Math.round(v)}{suffix || ""}</span>
    </div>
  );
}

function VolatilityCard() {
  const v = window.vol;
  return (
    <Card rank="r1" sm h={452}>
      <Body sm>
        <Eyebrow n="01" cat="Volatility" right={<Band severity="mod">{v.verdict}</Band>} />
        <Gauge value={v.score} />
        <div style={{ textAlign: "center", fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)", marginTop: 14 }}>Seller score · sell zone ≥ 70</div>
        <Bullets items={[
          "Implied " + v.iv + "% under realized " + v.hv30 + "%",
          "IV rank " + v.ivr + " · 52w range " + v.iv52Low + "–" + v.iv52High + "%",
        ]} />
        <div style={{ flex: 1 }} />
      </Body>
      <Foot sm h={132}>
        <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>Implied − realized</div>
        <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 24, fontWeight: 300, letterSpacing: "-.03em" }}><Dir size={24}>{Math.abs(v.spread) + " pts"}</Dir></div>
        <div style={{ fontSize: 12, fontWeight: 300, lineHeight: 1.4, color: "var(--ink-dim)", textWrap: "pretty" }}>Seller edge is negative — you are paid less than the stock has been moving.</div>
      </Foot>
      <Stamp state="delayed" text="Updated 3 min ago · next in 12 min" sm />
    </Card>
  );
}

function ProtectionCard() {
  const p = window.protection;
  return (
    <Card rank="r1" sm h={452}>
      <Body sm>
        <Eyebrow n="02" cat="Protection" right={<Band severity="mod">{p.putContracts} puts</Band>} />
        <Gauge value={parseFloat(p.coveredPct)} suffix="%" />
        <div style={{ textAlign: "center", fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)", marginTop: 14 }}>Shares floored by puts</div>
        <Bullets items={[
          p.covered.toLocaleString() + " of " + p.shares.toLocaleString() + " sh have a floor",
          "Strikes $" + p.floorLow + "–$" + p.floorHigh + " · " + p.uncovered + " sh open",
        ]} />
        <div style={{ flex: 1 }} />
      </Body>
      <Foot sm h={132}>
        <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>Cushion · spot over break-even</div>
        <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 24, fontWeight: 300, letterSpacing: "-.03em" }}><Dir up size={24}>{p.cushion}</Dir></div>
        <div style={{ fontSize: 12, fontWeight: 300, lineHeight: 1.4, color: "var(--ink-dim)", textWrap: "pretty" }}><Fig>{"Spot sits " + p.cushionPct + " over break-even — the puts floor the rest."}</Fig></div>
      </Foot>
      <Stamp state="delayed" text="Updated 16:00 · next at close" sm />
    </Card>
  );
}

/* ---------- section 4 · peers & ETFs ---------- */

function Spark({ closes, start }) {
  const all = [...closes, start];
  const lo = Math.min(...all), hi = Math.max(...all), span = hi - lo || 1;
  const W = 232, H = 52;
  const x = (i) => (i / (closes.length - 1)) * W;
  const y = (v) => H - ((v - lo) / span) * H;
  const pts = closes.map((c, i) => x(i) + "," + y(c)).join(" ");
  const area = "M" + pts.split(" ").join(" L") + " L" + W + "," + H + " L0," + H + " Z";
  return (
    <svg viewBox={"0 0 " + W + " " + H} width="100%" height={H} style={{ display: "block", marginTop: 16, overflow: "visible" }}>
      <line x1="0" y1={y(start)} x2={W} y2={y(start)} stroke="var(--ink-dim)" strokeWidth="1" strokeDasharray="2 4" />
      <path d={area} fill="var(--ink-text)" opacity=".1" />
      <polyline points={pts} fill="none" stroke="var(--ink-text)" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={x(closes.length - 1)} cy={y(closes[closes.length - 1])} r="3.5" fill="var(--ink-text)" />
    </svg>
  );
}

function TapeCard({ t, n }) {
  const down = t.net < 0;
  const [day, setDay] = useState(null);
  const d = day === null ? null : t.days[day];
  return (
    <Card rank="r1" sm h={392}>
      <Body sm>
        <Eyebrow n={n} cat={t.tk} right={<Band severity="low">{t.name}</Band>} />
        <div style={{ marginTop: 20, display: "flex", alignItems: "baseline", gap: 12, flexWrap: "wrap" }}>
          <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 32, fontWeight: 300, letterSpacing: "-.04em", lineHeight: 1 }}>$<Roll re>{(d ? d.close : t.last).toFixed(2)}</Roll></span>
          <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 17, fontWeight: 400 }}>
            <Dir up={d ? d.pct >= 0 : !down} size={17}>{Math.abs(d ? d.pct : t.net).toFixed(1) + "%"}</Dir>
          </span>
        </div>
        <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)", marginTop: 10, paddingBottom: 4 }}>{d ? d.d + " close" : "Last · five sessions"}</div>
        <div style={{ flex: 1 }} />
        <div style={{ display: "grid", gridTemplateColumns: "repeat(5,1fr)", paddingTop: 18, marginTop: 14, borderTop: "1px solid var(--ink-hair)" }}>
          {t.days.map((x, i) => (
            <button
              key={x.d}
              onClick={() => setDay(day === i ? null : i)}
              data-relevance={day === null || day === i ? "r1" : "r3"}
              style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10, padding: "2px 0", border: "none", background: "none", cursor: "pointer" }}
            >
              <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 8, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--ink-dim)" }}>{x.d}</span>
              <span style={{ width: 9, height: 9, borderRadius: "50%", boxSizing: "border-box", background: x.pct === 0 ? "transparent" : x.pct < 0 ? HUE.down : "var(--ink-text)", border: x.pct === 0 ? "1.5px solid var(--ink-dim)" : "none", boxShadow: day === i ? "0 0 0 3px var(--ink-hair)" : "none" }} />
              <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 10.5, color: x.pct < 0 ? HUE.down : "var(--ink-text)" }}>{(x.pct < 0 ? "−" : "+") + Math.abs(x.pct)}</span>
            </button>
          ))}
        </div>
      </Body>
      <Foot sm h={112}>
        <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>
          {t.group === "self" ? "Five sessions · your sleeve" : "Gap to NVDA"}
        </div>
        <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 12 }}>
          <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 24, fontWeight: 300, letterSpacing: "-.035em" }}>
            {t.group === "self" ? <Dir up={t.net >= 0} size={24}>{usd(Math.abs(5001 * t.last * (t.net / 100)))}</Dir> : <Dir up={t.vsNvda >= 0} size={24}>{Math.abs(t.vsNvda).toFixed(1) + " pts"}</Dir>}
          </span>
          <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 10.5, color: "var(--ink-dim)" }}>
            {t.group === "self" ? "5,001 shares" : t.vsNvda >= 0 ? "ahead of you" : "behind you"}
          </span>
        </div>
      </Foot>
      <Stamp state="live" text="Updated now · streaming" sm flat />
    </Card>
  );
}

/* ---------- section 5 · historical performance ---------- */

function HistoryCard() {
  const [mi, setMi] = useState(window.monthHistory.length - 2);
  const [pick, setPick] = useState(null);
  const [on, setOn] = useState({ shares: true, callsSold: true, callsBought: true, putsSold: false, putsBought: true });
  const m = window.monthHistory[mi];
  const S = window.SOURCES;
  const gain = (b) => S.reduce((a, s) => a + (on[s.key] && b.vals[s.key] > 0 ? b.vals[s.key] : 0), 0);
  const loss = (b) => S.reduce((a, s) => a + (on[s.key] && b.vals[s.key] < 0 ? b.vals[s.key] : 0), 0);
  const gains = m.bars.reduce((a, b) => a + gain(b), 0);
  const losses = m.bars.reduce((a, b) => a + loss(b), 0);
  const net = gains + losses;
  const peak = Math.max(
    ...window.monthHistory.flatMap((mm) => mm.bars.map((b) => Math.max(gain(b), -loss(b)))),
    1
  );
  const done = m.bars.filter((b) => !b.pending).length;
  const sel = pick === null ? null : m.bars[pick];
  const H = 52;
  return (
    <Card rank="r1" h={540}>
      <Body>
        <Eyebrow n="01" cat="Gains &amp; losses" right={<Band severity="mod">{m.label}</Band>} />
        <div style={{ marginTop: 16, fontFamily: "var(--ink-font-mono)", fontSize: 36, fontWeight: 300, letterSpacing: "-.04em", lineHeight: 1 }}>
          <Dir up={net >= 0} size={36}>{usd(Math.abs(net))}</Dir>
        </div>
        <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9.5, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)", marginTop: 9 }}>Net · {m.label} · {done} of {m.bars.length} sessions</div>

        <div style={{ marginTop: 16 }}>
          <div style={{ position: "relative", display: "flex", alignItems: "stretch", gap: 2, height: H * 2 }}>
            <span style={{ position: "absolute", left: 0, right: 0, top: H, height: 1, background: "var(--ink-hair)" }} />
            {m.bars.map((b, bi) => {
              const g = gain(b), l = -loss(b);
              const active = pick === bi;
              if (b.pending) {
                return (
                  <div key={b.label} title={b.sub + " · pending"} style={{ flex: "1 1 0", minWidth: 3, display: "flex", flexDirection: "column" }}>
                    <div style={{ height: H, display: "flex", alignItems: "flex-end", width: "100%" }}>
                      <i style={{ width: "100%", height: 3, background: "var(--ink-hair)", borderRadius: "2px 2px 0 0" }} />
                    </div>
                    <div style={{ height: H, width: "100%" }}>
                      <i style={{ display: "block", width: "100%", height: 3, background: "var(--ink-hair)", borderRadius: "0 0 2px 2px" }} />
                    </div>
                  </div>
                );
              }
              return (
                <button
                  key={b.label}
                  onClick={() => setPick(active ? null : bi)}
                  data-relevance={pick === null || active ? "r1" : "r3"}
                  style={{ flex: "1 1 0", minWidth: 3, display: "flex", flexDirection: "column", padding: 0, border: "none", background: "none", cursor: "pointer" }}
                >
                  <div style={{ height: H, display: "flex", alignItems: "flex-end", width: "100%" }}>
                    <i style={{ width: "100%", height: Math.max(1, (g / peak) * H) + "px", background: "var(--ink-text)", borderRadius: "2px 2px 0 0", transition: "height .45s var(--ink-ease)" }} />
                  </div>
                  <div style={{ height: H, width: "100%" }}>
                    <i style={{ display: "block", width: "100%", height: Math.max(1, (l / peak) * H) + "px", background: HUE.down, borderRadius: "0 0 2px 2px", transition: "height .45s var(--ink-ease)" }} />
                  </div>
                </button>
              );
            })}
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", fontFamily: "var(--ink-font-mono)", fontSize: 8, letterSpacing: ".1em", color: "var(--ink-dim)", marginTop: 8 }}>
            <span>{m.short} {m.bars[0].label}</span>
            <span>{m.short} {m.bars[m.bars.length - 1].label}</span>
          </div>
        </div>

        <div style={{ flex: 1 }} />
        <div className="mrail" style={{ flex: "none", display: "flex", flexWrap: "nowrap", alignItems: "center", gap: 6, overflowX: "auto", borderTop: "1px solid var(--ink-hair)", paddingTop: 14, paddingBottom: 4, marginTop: 12 }}>
          {window.monthHistory.map((h, i) => (
            <button key={h.short} onClick={() => { setMi(i); setPick(null); }} style={{ flex: "none", minHeight: 26, padding: "0 11px", borderRadius: "var(--ink-radius-element)", cursor: "pointer", fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".14em", textTransform: "uppercase", border: "1px solid " + (i === mi ? "var(--ink-invert-bg)" : "var(--ink-hair)"), background: i === mi ? "var(--ink-invert-bg)" : "transparent", color: i === mi ? "var(--ink-invert-text)" : "var(--ink-dim)" }}>{h.short}</button>
          ))}
        </div>
        <div className="mrail" style={{ flex: "none", display: "flex", flexWrap: "nowrap", alignItems: "center", gap: 6, overflowX: "auto", paddingTop: 4, paddingBottom: 4, marginTop: 4 }}>
          {(() => {
            const live = S.filter((s) => !s.empty);
            const all = live.every((s) => on[s.key]);
            return (
              <button
                onClick={() => setOn(Object.fromEntries(S.map((s) => [s.key, s.empty ? false : !all])))}
                style={{ display: "flex", alignItems: "center", minHeight: 26, padding: "0 11px", flex: "none", whiteSpace: "nowrap", borderRadius: "var(--ink-radius-element)", cursor: "pointer", fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".08em", textTransform: "uppercase", border: "1px solid " + (all ? "var(--ink-invert-bg)" : "var(--ink-hair)"), background: all ? "var(--ink-invert-bg)" : "transparent", color: all ? "var(--ink-invert-text)" : "var(--ink-dim)" }}
              >All</button>
            );
          })()}
          <span style={{ flex: "none", width: 1, height: 18, background: "var(--ink-hair)", margin: "0 2px" }} />
          {[...S].sort((a, b) => (a.empty ? 1 : 0) - (b.empty ? 1 : 0)).map((s) => (
            <button
              key={s.key}
              disabled={s.empty}
              onClick={() => setOn((o) => ({ ...o, [s.key]: !o[s.key] }))}
              style={{ display: "flex", alignItems: "center", gap: 5, minHeight: 26, padding: "0 9px", flex: "none", whiteSpace: "nowrap", borderRadius: "var(--ink-radius-element)", cursor: s.empty ? "default" : "pointer", fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".08em", textTransform: "uppercase", borderWidth: 1, borderStyle: s.empty ? "dashed" : "solid", borderColor: on[s.key] && !s.empty ? "var(--ink-invert-bg)" : "var(--ink-hair)", background: on[s.key] && !s.empty ? "var(--ink-invert-bg)" : "transparent", color: on[s.key] && !s.empty ? "var(--ink-invert-text)" : "var(--ink-dim)" }}
            >
              <span style={{ fontSize: 9 }}>{s.m}</span>{s.label}
            </button>
          ))}
        </div>
      </Body>
      <Foot>
        {sel ? (
          <React.Fragment>
            <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 10 }}>
              <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-text)" }}>{sel.sub}</span>
              <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 16, fontWeight: 500 }}>
                <Dir up={gain(sel) + loss(sel) >= 0} size={16}>{usd(Math.abs(gain(sel) + loss(sel)))}</Dir>
              </span>
            </div>
            <div style={{ display: "flex", gap: 14, overflowX: "auto" }}>
              {S.filter((s) => on[s.key] && sel.vals[s.key] !== 0).map((s) => (
                <div key={s.key} style={{ flex: "none" }}>
                  <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 8, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--ink-dim)", whiteSpace: "nowrap" }}>{s.m} {s.label}</div>
                  <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 15, marginTop: 7, color: sel.vals[s.key] < 0 ? HUE.down : "var(--ink-text)" }}>{(sel.vals[s.key] < 0 ? "−" : "+") + usd(Math.abs(sel.vals[s.key]))}</div>
                </div>
              ))}
            </div>
          </React.Fragment>
        ) : (
          <React.Fragment>
            <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 10 }}>
              <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>Gains vs losses</span>
              <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 10, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--ink-dim)" }}>Tap a session</span>
            </div>
            <div style={{ display: "flex", gap: 22 }}>
              <div>
                <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 8.5, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--ink-dim)" }}>Gains</div>
                <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 22, fontWeight: 300, marginTop: 8 }}><Roll re>{usd(gains)}</Roll></div>
              </div>
              <div>
                <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 8.5, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--ink-dim)" }}>Losses</div>
                <div style={{ fontFamily: "var(--ink-font-mono)", fontSize: 22, fontWeight: 300, marginTop: 8, color: HUE.down }}><Roll re>{usd(Math.abs(losses))}</Roll></div>
              </div>
            </div>
          </React.Fragment>
        )}
      </Foot>
      <Stamp state="delayed" text="Updated 16:00 · next at close" />
    </Card>
  );
}

/* ---------- shell ---------- */

/* Icons are Ink library glyphs (24px grid, 1.5px outline, chrome stays ink):
   Book → portfolio · History → events · Compare → the plan/roll action.
   Ink ships no person glyph, so Profile is Lucide's user at the same weight — flagged substitution. */
const TabIco = {
  portfolio: ["M4 8h16a1 1 0 0 1 1 1v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a1 1 0 0 1 1-1z", "M9 8V6.2A2.2 2.2 0 0 1 11.2 4h1.6A2.2 2.2 0 0 1 15 6.2V8", "M3 13h18"],
  events: ["M3 12a9 9 0 1 0 3-6.7L3 8", "M3 4v4h4", "M12 8v4l3 2"],
  profile: ["M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2", "M12 3a4 4 0 1 1 0 8 4 4 0 0 1 0-8z"],
};

function Tab({ id, on, onClick }) {
  return (
    <button onClick={onClick} aria-label={id} style={{ flex: "0 0 38px", width: 38, height: 38, padding: 0, border: "none", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", borderRadius: 100, background: on ? "var(--ink-invert-bg)" : "transparent", color: on ? "var(--ink-invert-text)" : "var(--ink-dim)", transition: "background .18s var(--ink-ease), color .18s var(--ink-ease)" }}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        {TabIco[id].map((d) => <path key={d} d={d} />)}
      </svg>
    </button>
  );
}

/* Ticker paging — a horizontal swipe on the screen moves one name: left → next, right → previous.
   Gestures that begin inside a horizontal scroller (card rails, chip rails) are left alone, so
   paging never fights the rails. Pointer events cover both touch and trackpad drag. */
function useTickerSwipe(onNext, onPrev) {
  const ref = useRef(null);
  useEffect(() => {
    const el = ref.current;
    if (!el || window.__SHOT) return;
    const SCROLLERS = ".rail, .mrail, .pl-rail, .ev-filters, .ev-week, .nav";
    let x = 0, y = 0, live = false, lock = false;
    const down = (e) => { live = !(e.target.closest && e.target.closest(SCROLLERS)); x = e.clientX; y = e.clientY; };
    const up = (e) => {
      if (!live || lock) return;
      live = false;
      const dx = e.clientX - x, dy = e.clientY - y;
      if (Math.abs(dx) < 56 || Math.abs(dx) < Math.abs(dy) * 1.6) return;
      lock = true;
      setTimeout(() => { lock = false; }, 500);
      dx < 0 ? onNext() : onPrev();
    };
    const cancel = () => { live = false; };
    el.addEventListener("pointerdown", down);
    el.addEventListener("pointerup", up);
    el.addEventListener("pointercancel", cancel);
    return () => { el.removeEventListener("pointerdown", down); el.removeEventListener("pointerup", up); el.removeEventListener("pointercancel", cancel); };
  }, [onNext, onPrev]);
  return ref;
}

function TailHint({ next }) {
  return (
    <div className="tailpad" style={{ display: "flex", alignItems: "flex-start", justifyContent: "center", paddingTop: 10 }}>
      <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 9, letterSpacing: ".18em", textTransform: "uppercase", color: "var(--ink-dim)" }}>Swipe left · {next}</span>
    </div>
  );
}

function PortfolioScreen({ px, onPlan, onRoll, next }) {
  const rolls = [];
  const groups = [
    { label: "Overview", m: "", cards: [<SummaryCard key="sum" px={px} onPlan={onPlan} />, <SleeveCard key="sleeve" />] },
    { label: "Shares", m: "○", cards: [<SharesCard key="shares" px={px} />] },
  ];
  let n = 3;
  window.legs.forEach((leg) => {
    const side = leg.side === "short" ? "short" : "long";
    groups.push({
      label: leg.group,
      m: mark(leg.kind, side),
      cards: leg.strikes.map((s, i) => {
        n += 1;
        const r = window.rollFor(leg, s, px);
        if (r) rolls.push({ leg, s, r });
        return <StrikeCard key={leg.group + s.strike + i} leg={leg} s={s} n={String(n).padStart(2, "0")} px={px} onRoll={onRoll} />;
      }),
    });
  });
  const total = groups.reduce((a, g) => a + g.cards.length, 0);
  const live = rolls.filter((x) => x.r.state === "live");
  /* capture harness: narrow to one group / one card / one section without touching layout */
  const shown = SHOT && SHOT.group != null
    ? [SHOT.card != null ? { ...groups[SHOT.group], cards: groups[SHOT.group].cards.slice(SHOT.card, SHOT.card + 1) } : groups[SHOT.group]]
    : groups;
  const sec = (i, node) => (SHOT && SHOT.section != null && SHOT.section !== i ? null : node);

  return (
    <div className="scroll">
      {sec(0, <React.Fragment>
      <div className="secthead">
        <h1>Current position</h1>
        <span className="count"><span>{total} cards</span>{live.length ? <button className="count-roll" onClick={() => onRoll && onRoll(live[0].r)}>{live.length} to roll</button> : null}</span>
      </div>
      <div className={"rail" + (rolls.length ? " slip" : "")}>
        {shown.map((g) => (
          <div className="grp" key={g.label}>
            <div className="grp-h">
              {g.m ? <span className="grp-m">{g.m}</span> : null}
              <span>{g.label}</span>
              <span className="grp-n">{g.cards.length}</span>
            </div>
            <div className="grp-cards">{g.cards}</div>
          </div>
        ))}
      </div>
      </React.Fragment>)}

      {sec(1, <React.Fragment>
      <div className="secthead">
        <h1>How it has performed</h1>
        <span className="count"><span>{window.perf.sleeves.length + 1} cards</span></span>
      </div>
      <div className="rail">
        <div className="grp-cards">
          <ProfitCard />
          {[...window.perf.sleeves].sort((a, b) => (a.empty ? 1 : 0) - (b.empty ? 1 : 0)).map((s, i) => <SleevePerfCard key={s.name} s={s} n={String(i + 2).padStart(2, "0")} />)}
        </div>
      </div>
      </React.Fragment>)}

      {sec(2, <React.Fragment>
      <div className="secthead">
        <h1>Insights</h1>
        <span className="count"><span>2 cards</span></span>
      </div>
      <div className="rail sm">
        <div className="grp-cards">
          <VolatilityCard />
          <ProtectionCard />
        </div>
      </div>
      </React.Fragment>)}

      {sec(3, <React.Fragment>
      <div className="secthead">
        <h1>Peers &amp; ETFs</h1>
        <span className="count"><span>{window.tapes.length} cards</span></span>
      </div>
      <div className="rail sm">
        {["self", "ETFs", "Peers"].map((g) => {
          const list = window.tapes.filter((t) => t.group === g);
          return (
            <div className="grp" key={g}>
              <div className="grp-h">
                <span>{g === "self" ? "NVDA" : g}</span>
                <span className="grp-n">{list.length}</span>
              </div>
              <div className="grp-cards">
                {list.map((t) => <TapeCard key={t.tk} t={t} n={String(window.tapes.indexOf(t) + 1).padStart(2, "0")} />)}
              </div>
            </div>
          );
        })}
      </div>
      </React.Fragment>)}
      {sec(4, <React.Fragment>
      <div className="secthead">
        <h1>Historical performance</h1>
        <span className="count"><span>1 card</span></span>
      </div>
      <div className="rail">
        <div className="grp-cards"><HistoryCard /></div>
      </div>
      </React.Fragment>)}
      {SHOT && SHOT.section != null ? null : <TailHint next={next} />}
    </div>
  );
}

/* Only NVDA is modelled. A ticker with no book gets an honest quiet state, never invented data. */
const SYMS = ["Nvidia", "Google", "Tesla"];

function NoPosition({ sym, next }) {
  return (
    <div className="scroll">
      <div className="ev-quiet" style={{ marginTop: 120 }}>
        <span style={{ fontFamily: "var(--ink-font-mono)", fontSize: 10, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--ink-dim)" }}>No position</span>
        <span style={{ fontSize: 13, fontWeight: 300, color: "var(--ink-dim)", marginTop: 10 }}>Nothing held or written in {sym} — watchlist only.</span>
      </div>
      <div style={{ flex: 1 }} />
      <TailHint next={next} />
    </div>
  );
}

/* Capture hook — a handoff/QA harness page may set window.__SHOT = {theme,tab,sym,plan,roll}
   before mount to pin one deterministic state. Inert in the app itself. */
const SHOT = window.__SHOT || null;

function App() {
  const [tw, setTweak] = useTweaks({ theme: "dark", live: true, fade: true });
  const [tab, setTab] = useState((SHOT && SHOT.tab) || "portfolio");
  const [sym, setSym] = useState((SHOT && SHOT.sym) || "Nvidia");
  const nextSym = SYMS[(SYMS.indexOf(sym) + 1) % SYMS.length];
  const goNext = React.useCallback(() => setSym((s) => SYMS[(SYMS.indexOf(s) + 1) % SYMS.length]), []);
  const goPrev = React.useCallback(() => setSym((s) => SYMS[(SYMS.indexOf(s) + SYMS.length - 1) % SYMS.length]), []);
  const pageRef = useTickerSwipe(goNext, goPrev);
  const [plan, setPlan] = useState(!!(SHOT && SHOT.plan));
  const [roll, setRoll] = useState(SHOT && SHOT.roll ? window.rollFor(window.legs[0], window.legs[0].strikes[0], window.SPOT) : null);
  const [px, setPx] = useState(window.SPOT);
  const base = useRef(window.SPOT);

  useEffect(() => {
    if (!tw.live || SHOT) return;
    const t = setInterval(() => {
      setPx((p) => Math.max(base.current - 0.4, Math.min(base.current + 0.4, p + (Math.random() - 0.5) * 0.11)));
    }, 3400);
    return () => clearInterval(t);
  }, [tw.live]);

  return (
    <React.Fragment>
      <TweaksPanel title="NVDA one page">
        <TweakSection label="Appearance" />
        <TweakRadio label="Theme" value={tw.theme} options={["dark", "light"]} onChange={(v) => setTweak("theme", v)} />
        <TweakToggle label="Fade by relevance" value={tw.fade} onChange={(v) => setTweak("fade", v)} />
        <TweakSection label="Data" />
        <TweakToggle label="Live spot ticking" value={tw.live} onChange={(v) => setTweak("live", v)} />
      </TweaksPanel>
      <div data-theme={(SHOT && SHOT.theme) || tw.theme} className={"device" + (tw.fade ? "" : " nofade")}>
      <div className="screen" ref={pageRef}>
        <div className="ios-status">
          <span>9:41</span>
          <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
            5G
            <svg width="17" height="11" viewBox="0 0 17 11" fill="currentColor"><rect x="0" y="2" width="14" height="7" rx="2" fillOpacity=".3" /><rect x="1.4" y="3.4" width="9.6" height="4.2" rx="1.2" /><rect x="15.2" y="4" width="1.6" height="3" rx=".8" fillOpacity=".45" /></svg>
          </span>
        </div>

        <div className="nav">
          <div className="tickerline">
            {SYMS.map((s) => (
              <button key={s} className="tk" data-relevance={s === sym ? "r1" : "r3"} onClick={() => setSym(s)}>{s}</button>
            ))}
          </div>
          <span className="live"><i /> live</span>
        </div>

        {tab === "portfolio" ? (sym === "Nvidia" ? <PortfolioScreen key={sym} px={px} onPlan={() => setPlan(true)} onRoll={setRoll} next={nextSym} /> : <NoPosition key={sym} sym={sym} next={nextSym} />) : tab === "events" ? <window.EventsScreen /> : <window.ProfileScreen />}

        {plan ? <window.PlanSheet px={px} onClose={() => setPlan(false)} /> : null}
        {roll ? <window.RollSheet r={roll} onClose={() => setRoll(null)} /> : null}

        <div className="tabbar">
          <Tab id="portfolio" on={tab === "portfolio"} onClick={() => setTab("portfolio")} />
          <Tab id="events" on={tab === "events"} onClick={() => setTab("events")} />
          <Tab id="profile" on={tab === "profile"} onClick={() => setTab("profile")} />
        </div>
      </div>
      </div>
    </React.Fragment>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
