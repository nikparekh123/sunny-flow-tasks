/* Planner as full-bleed snap pages, one decision each.
   One layout law across every page: content stacks from the top, and the page's number sits at
   the bottom left with its unit beside it, its receipts under it. If a page has more to say the
   content pushes up from the top; the number never moves.
   Every figure comes from window.PLAN2. */
const pnum = (n) => n.toLocaleString("en-US");
const psgn = (n, d) => (n < 0 ? "\u2212" : "+") + Math.abs(n).toFixed(d === undefined ? 2 : d);

const Kicker = ({ children, s }) => <div className="pg-kick" style={{ fontSize: s(11) }}>{children}</div>;
/* the number, always bottom left, unit on its baseline */
const Num = ({ v, u, s, size, hue }) => (
  <div className="nb">
    <span className="v" style={{ fontSize: s(size || 110), color: hue }}>{v}</span>
    {u ? <span className="u" style={{ fontSize: s(24) }}>{u}</span> : null}
  </div>
);
const Say = ({ children, s }) => <p className="say" style={{ fontSize: s(16) }}>{children}</p>;
const Fine = ({ children, s }) => <p className="fine" style={{ fontSize: s(13) }}>{children}</p>;

/* The sale is the only thing in the planner the user CREATES, so it is the only thing that
   survives a reload. One record: which tier, at what price, on what date. */
const CK = "nvda-planner-pages-commit-v1";
const useCommit = () => {
  const [c, setC] = React.useState(() => {
    try { return JSON.parse(localStorage.getItem(CK) || "null"); } catch (e) { return null; }
  });
  const write = (v) => {
    setC(v);
    try { v ? localStorage.setItem(CK, JSON.stringify(v)) : localStorage.removeItem(CK); } catch (e) {}
  };
  return [c, write];
};

/* ── 0 · conviction as eight equal circles. Size says nothing: every family gets the same disc,
      and WEIGHT is carried by colour depth. Solid adds conviction, hollow takes it away.
      Tap a disc and the number below becomes its own. ── */
const wOf = (f) => Math.min(1, Math.abs(f.today) / Math.max(Math.abs(f.min), Math.abs(f.max)));
const strength = (w) => Math.round(26 + 74 * w) + "%";
/* the tap-revealed name has to read on whatever that mix produced, so the label colour comes
   from the fill's measured luminance, never from the weight that made it */
const hexRgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const lum = (rgb) => {
  const f = (c) => { c /= 255; return c <= .03928 ? c / 12.92 : Math.pow((c + .055) / 1.055, 2.4); };
  return .2126 * f(rgb[0]) + .7152 * f(rgb[1]) + .0722 * f(rgb[2]);
};
const rgbCss = (a) => "rgb(" + a.map(Math.round).join(",") + ")";
const labelOn = (hue, w, filled) => {
  const base = hexRgb(hue);
  if (!filled) return rgbCss(base.map((c) => c * .72));
  const p = (26 + 74 * w) / 100;
  return lum(base.map((c) => c * p + 255 * (1 - p))) < .185 ? "#FFFFFF" : "#050505";
};

const Disc = ({ f, s, sel, tap }) => {
  const off = f.computed === false;
  const w = wOf(f);
  const kind = off ? "off" : f.today < 0 ? "neg" : f.today === 0 ? "zero" : "pos";
  return (
    <button className={"cw " + kind + (sel ? " sel" : "")} onClick={tap} aria-label={f.key}
      style={{ "--c": f.hue, "--p": strength(w), "--fg": labelOn(f.hue, w, kind === "pos") }}>
      <span className="nm" style={{ fontSize: s(10) }}>{f.key}</span>
    </button>
  );
};

const PgScore = ({ s }) => {
  const P = window.PLAN2, p = P.plan, F = P.factors;
  const [sel, setSel] = React.useState(null);
  const f = F.find((x) => x.key === sel);
  const movers = F.filter((x) => x.today !== x.yest).sort((a, b) => Math.abs(b.today - b.yest) - Math.abs(a.today - a.yest));
  const say = (movers.length
    ? movers.slice(0, 2).map((x) => x.key + (x.today > x.yest ? " added " : " took back ") + Math.abs(x.today - x.yest)).join(", ") + "."
    : "Nothing moved since yesterday.").replace(/^./, (c) => c.toUpperCase());
  const mv = f ? f.today - f.yest : 0;
  /* biggest mover first, so the disc you read first is the one that changed the most */
  const ordered = F.slice().sort((x, y) => Math.abs(y.today - y.yest) - Math.abs(x.today - x.yest));
  return (
    <section className="pg t0" data-screen-label="00 conviction">
      <div className="pg-in">
        <div className="pg-head">
          <div className="pg-date" style={{ fontSize: s(12) }}>{P.asOf.dow}, {P.asOf.label}</div>
          <div className="sc-field">
            {ordered.map((x) => <Disc key={x.key} f={x} s={s} sel={sel === x.key} tap={() => setSel(sel === x.key ? null : x.key)} />)}
          </div>
        </div>
        <div className="pg-base">
          <Num s={s} size={f ? 96 : 110} hue={f ? f.hue : undefined}
            v={f ? (f.computed === false ? "\u2014" : psgn(f.today, 0)) : p.conviction}
            u={f ? "of " + Math.max(Math.abs(f.min), Math.abs(f.max)) : "of 100"} />
          <div className="trail" style={{ fontSize: s(11.5) }}>
            {(f ? [f.d2, f.yest, f.today] : p.convictionTrail).map((v, i, a) => (
              <React.Fragment key={i}>{i ? <i>→</i> : null}<b className={i === a.length - 1 ? "on" : ""}>{f ? psgn(v, 0) : v}</b></React.Fragment>
            ))}
          </div>
          {f ? (
            <React.Fragment>
              <Say s={s}>{mv === 0 ? "Flat for two days." : (mv > 0 ? "Added " : "Took back ") + Math.abs(mv) + " on yesterday."}</Say>
              <Fine s={s}>{f.reads}</Fine>
            </React.Fragment>
          ) : <Say s={s}>{say}</Say>}
        </div>
      </div>
    </section>
  );
};

/* ── 1 · the decision ─────────────────────────────────────────────────── */
const PgDecision = ({ s, toGrade }) => {
  const P = window.PLAN2, p = P.plan;
  /* read the grade family off the same table the score page draws, never a constant */
  const gradeFamily = (P.factors || []).find((x) => x.key === "grade");
  /* the load comes from the server already cased ("5 sold for Aug 10") — never flatten it, or
     the month goes with it */
  const open = P.expiries.map((e) => e.load + ", " + e.verdict).join(". ") + ".";
  return (
    <section className="pg t1" data-screen-label="01 decision">
      <div className="pg-in">
        <div className="pg-head">
          <Kicker s={s}>the decision</Kicker>
          <Fine s={s}>{open}</Fine>
        </div>
        <div className="pg-base">
          <Num s={s} v={p.size.sold} u={"of " + p.size.full + " contracts"} />
          <Say s={s}>Conviction {p.conviction} shrinks the sale: {p.size.sold}, not {p.size.full}, at {p.size.strike.toFixed(2)}. Keep {p.keepPct}%, {pnum(p.keepDelta)} of {pnum(p.totalDelta)} delta.</Say>
          <Fine s={s}>{p.event.replace(/^./, (c) => c.toUpperCase())}, {p.price}. Paid {psgn(p.paidVsNormal, 0) + "%"} against normal. {p.why}</Fine>
          <button className="foot" onClick={toGrade || undefined} disabled={!toGrade} style={{ fontSize: s(11) }}>
            <span>baseline {p.baseline}</span>
            <span>your grade {psgn(gradeFamily ? gradeFamily.today : 0, 0)}</span>
          </button>
        </div>
      </div>
    </section>
  );
};

/* ── 2 · what matters, what won't ─────────────────────────────────────── */
const PgWeek = ({ s }) => {
  const o = window.PLAN2.observations;
  const Items = ({ rows, dim }) => (
    <ol className={"pg-items" + (dim ? " quiet" : "")}>
      {rows.map((x, i) => (
        <li key={i}>
          <span className="n" style={{ fontSize: s(12) }}>{i + 1}</span>
          <p style={{ fontSize: s(dim ? 15 : 16) }}><span className="lead">{x.lede}</span><span className="d"> {x.text}</span></p>
        </li>
      ))}
    </ol>
  );
  return (
    <section className="pg t2" data-screen-label="02 the week">
      <div className="pg-in">
        <div className="pg-head">
          <Kicker s={s}>what matters this week</Kicker>
          <Items rows={o.matters} />
          <div className="pg-sub"><Kicker s={s}>what won't matter</Kicker></div>
          <Items rows={o.quiet} dim />
        </div>
      </div>
    </section>
  );
};

/* ── 3 · put floor ────────────────────────────────────────────────────── */
const PgFloor = ({ s }) => {
  const f = window.PLAN2.floorAdvice;
  return (
    <section className="pg t3" data-screen-label="03 put floor">
      <div className="pg-in">
        <div className="pg-head"><Kicker s={s}>put floor</Kicker></div>
        <div className="pg-base">
          <Num s={s} v={f.floor} u={f.gapPct + "% under spot"} />
          <Say s={s}>{f.head}.</Say>
          <Fine s={s}>The floor is rolled first, as its own decision. Nothing gets written against an unprotected book.</Fine>
        </div>
      </div>
    </section>
  );
};

/* The whole position from today: the shares plus the call being sold. It rises with the stock
   until the strike, then flattens to whatever shares are left uncovered — that kink IS the cap.
   The faint line is the option leg on its own, for scale. Geometry only, no new figures. */
const Payoff = ({ c, spot, em, s }) => {
  const B = window.PLAN2.book;
  const W = 338, H = 150;
  const lo = spot - em, hi = spot + em;
  const covered = c.ct * 100;
  /* change from here: the shares move with the stock, the call pays its credit and then gives it back */
  const pos = (v) => B.shares * (v - spot) + c.income - Math.max(0, v - c.strike) * covered;
  const vals = [pos(lo), pos(c.strike), pos(hi)];
  const top = Math.max(...vals) * 1.15, bot = Math.min(...vals) * 1.15;
  const X = (v) => ((v - lo) / (hi - lo)) * W;
  const Y = (v) => H - ((v - bot) / (top - bot)) * H;
  const y0 = Y(0), P = (v) => X(v) + "," + Y(pos(v));
  return (
    <svg className="pl" viewBox={"0 0 " + W + " " + H} width="100%" height={H} aria-hidden="true">
      <polygon className="neg" points={X(lo) + "," + y0 + " " + P(lo) + " " + X(c.posBe) + "," + y0} />
      <line className="zero" x1="0" y1={y0} x2={W} y2={y0} />
      <line className="now" x1={X(spot)} y1="16" x2={X(spot)} y2={H} />
      <polyline className="line" points={P(lo) + " " + P(c.strike) + " " + P(hi)} />
      <circle className="dot" cx={X(c.strike)} cy={Y(pos(c.strike))} r="3.5" />
      <circle className="dot hollow" cx={X(c.posBe)} cy={y0} r="3.5" />
      <text className="tx" x={Math.max(28, Math.min(W - 30, X(spot)))} y="10" textAnchor="middle" style={{ fontSize: s(9) }}>now {spot.toFixed(2)}</text>
      <text className="tx" x={X(c.strike) + 7} y={Y(pos(c.strike)) + 17} style={{ fontSize: s(9) }}>capped {c.strike.toFixed(2)}</text>
      <text className="tx" x={Math.max(0, X(c.posBe) - 12)} y={y0 + 15} style={{ fontSize: s(9) }}>{c.posBe.toFixed(2)}</text>
    </svg>
  );
};

/* ── 4 · what to sell, and what it does to the book. One page, because the chain and the
      outcome are one story: the chain is the choice, the axis is the room it leaves, and the
      three figures at the bottom are what the choice is worth. ── */
const PgSell = ({ s, commit, onCommit }) => {
  const P = window.PLAN2, p = P.plan;
  /* the rail opens on what conviction sized to, never on the biggest credit */
  const recIdx = Math.max(0, p.picks.findIndex((x) => x.rec));
  const [sel, setSel] = React.useState(commit ? commit.i : recIdx);
  const [ok, setOk] = React.useState(false);
  const pick = (i) => { setSel(i); setOk(false); };
  const c = p.picks[sel];
  /* furthest strike first: at high conviction the top of the rail is the consistent end of it.
     A strike inside the put floor is refused outright and sits last, priced but unpickable. */
  const ladder = p.picks.map((x, i) => ({ x, i }))
    .sort((a, b) => (a.x.blocked ? 1 : 0) - (b.x.blocked ? 1 : 0) || b.x.strike - a.x.strike);
  const spot = P.asOf.spot, em = p.expectedMove;
  return (
    <section className="pg t4" data-screen-label="04 what to sell">
      <div className="pg-in">
        <div className="pg-head">
          <div className="pg-row2">
            <Kicker s={s}>what to sell</Kicker>
            <span className="meta" style={{ fontSize: s(10.5) }}>{P.asOf.label} → {p.expiry} · {p.expDays}d</span>
          </div>
          <div className="srail">
            {ladder.map(({ x, i }) => (
              <button key={i} className={"scard" + (sel === i ? " on" : "") + (x.blocked ? " no" : "") + (x.rec ? " rec" : "")}
                onClick={x.blocked ? undefined : () => pick(i)} disabled={!!x.blocked}>
                <span className="tier" style={{ fontSize: s(9) }}>{x.tier}</span>
                <span className="k" style={{ fontSize: s(24) }}>{x.strike.toFixed(2)}</span>
                <span className="ct" style={{ fontSize: s(9.5) }}>{x.blocked ? x.blocked : x.ct + " contracts · " + x.otm.toFixed(2) + "% out"}</span>
                <span className="gk">
                  <i style={{ fontSize: s(9.5) }}>iv</i><b style={{ fontSize: s(12.5) }}>{x.iv.toFixed(1)}</b>
                  <i style={{ fontSize: s(9.5) }}>Δ</i><b style={{ fontSize: s(12.5) }}>{x.delta}</b>
                  <i style={{ fontSize: s(9.5) }}>Γ</i><b style={{ fontSize: s(12.5) }}>{x.gamma.toFixed(3)}</b>
                </span>
                <span className="cr" style={{ fontSize: s(19) }}>{x.label}</span>
              </button>
            ))}
          </div>
          <div className="be">
            <div className="be-top" style={{ fontSize: s(9.5) }}>
              <span>{pnum(window.PLAN2.book.shares)} shares + call</span>
              <span className="hi">{pnum(c.uncovered)} uncapped</span>
            </div>
            <Payoff c={c} spot={spot} em={em} s={s} />
          </div>
        </div>
        <div className="pg-base">
          <Num s={s} v={c.label} u={"credit at " + c.strike.toFixed(2)} size={84} />
          <Fine s={s}>
            {c.tier.replace(/^./, (x) => x.toUpperCase())}, {c.prem.toFixed(2)} a share on {c.ct} contracts.
            {c.was ? " At a neutral 50 this tier was " + c.was + "." : ""} {c.rec ? p.hedgeNote + "." : p.tierNote}
          </Fine>
          <Fine s={s}>Breakeven {c.breakeven.toFixed(2)}: the {c.strike.toFixed(2)} strike plus the {c.prem.toFixed(2)} you were paid, {c.beBasisPct.toFixed(1)}% above your {P.book.buyAvg.toFixed(2)} basis.</Fine>
          {commit && commit.i === sel ? (
            <label className="chk done" style={{ fontSize: s(12.5) }}>
              <input type="checkbox" checked readOnly />
              <span>Executed {c.ct} at {c.strike.toFixed(2)}, {p.expCode}. Logged {commit.on}.</span>
            </label>
          ) : (
            <React.Fragment>
              <label className="chk" style={{ fontSize: s(12.5) }}>
                <input type="checkbox" checked={ok} onChange={(e) => setOk(e.target.checked)} />
                <span>This is what is executed: {c.ct} at {c.strike.toFixed(2)}, {p.expCode}.</span>
              </label>
              <button className="cbar" style={{ fontSize: s(12) }} disabled={!ok}
                onClick={() => onCommit({ i: sel, at: P.asOf.iso, on: P.asOf.short, spot: P.asOf.spot })}>
                <span>{commit ? "replace the position" : "start monitoring"}</span>
                <span className="tk">{c.tier}</span>
              </button>
            </React.Fragment>
          )}
        </div>
      </div>
    </section>
  );
};

/* ── 5 · the position you are running. Nothing here is a new feed: it is the sale you confirmed,
      read against today's spot. The bar is the room left before the cap bites. ── */
const PgMonitor = ({ s, commit, onCommit }) => {
  const P = window.PLAN2, p = P.plan;
  const c = p.picks[commit.i];
  const spot = P.asOf.spot;
  const room = c.strike - commit.spot;
  const used = Math.max(0, Math.min(1, (spot - commit.spot) / (room || 1)));
  const left = ((c.strike - spot) / spot) * 100;
  const moved = spot - commit.spot;
  return (
    <section className="pg t5" data-screen-label="05 monitoring">
      <div className="pg-in">
        <div className="pg-head">
          <div className="pg-row2">
            <Kicker s={s}>the position you are running</Kicker>
            <span className="meta" style={{ fontSize: s(10.5) }}>sold {commit.on}</span>
          </div>
          <div className="tick" style={{ fontSize: s(13) }}>{c.ct} {P.ticker} {p.expiry} {c.strike.toFixed(2)} C at {c.prem.toFixed(2)}</div>
          <div className="room">
            <div className="room-r" style={{ fontSize: s(9.5) }}>
              <span>sold at {commit.spot.toFixed(2)}</span>
              <span>cap {c.strike.toFixed(2)}</span>
            </div>
            <div className="room-bar"><i style={{ width: used * 100 + "%" }} /></div>
            <div className="room-r" style={{ fontSize: s(9.5) }}>
              <span>now {spot.toFixed(2)} · {moved === 0 ? "unchanged" : psgn(moved, 2)}</span>
              <span>{pnum(c.uncovered)} uncapped</span>
            </div>
          </div>
          <Fine s={s}>The credit is yours either way. What is still open is the {left.toFixed(2)}% of upside between here and the cap, on {pnum(c.ct * 100)} of your {pnum(P.book.shares)} shares.</Fine>
        </div>
        <div className="pg-base">
          <Num s={s} v={left.toFixed(2) + "%"} u="of room left" />
          <Say s={s}>{c.called}% odds it gets called. {p.expDays} sessions to run.</Say>
          <div className="trio" style={{ fontSize: s(10) }}>
            <span><b style={{ fontSize: s(17) }}>{c.out.prem}</b>collected</span>
            <span><b style={{ fontSize: s(17) }}>{c.out.shares}</b>{"if called at " + c.strike.toFixed(2)}</span>
            <span><b style={{ fontSize: s(17) }}>{c.kept + "%"}</b>delta kept</span>
          </div>
          <div className="cbar on" style={{ fontSize: s(11), marginTop: s(14) }}>
            <span>{c.tier} · conviction {p.conviction} at the sale</span>
            <button onClick={() => onCommit(null)}>stand down</button>
          </div>
        </div>
      </div>
    </section>
  );
};

/* ── 6 · the earnings grade. The only input no feed provides, so it names the quarter it is
      asking about and keeps every grade given since the first one. ── */
const PgGrade = ({ s }) => {
  const p = window.PLAN2.plan;
  const q = p.gradeQuarter;
  const hist = p.gradeHistory;
  const [g, setG] = React.useState(p.grade);
  return (
    <section className="pg t6" data-screen-label="06 earnings grade">
      <div className="pg-in">
        <div className="pg-head">
          <div className="pg-row2">
            <Kicker s={s}>earnings grade</Kicker>
            <span className="meta" style={{ fontSize: s(10.5) }}>reported {q.reported}</span>
          </div>
          <Say s={s}>How was {q.label}?</Say>
          <Fine s={s}>{q.sessionsAgo} sessions ago. It fades out over 60, and the next one opens after the {q.nextPrint} print.</Fine>
        </div>
        <div className="pg-base">
          <Num s={s} v={g} u="of 10" />
          <div className="pg-grade">
            <button className="pg-step" onClick={() => setG(Math.max(0, g - 1))} aria-label="lower">−</button>
            <button className="pg-step" onClick={() => setG(Math.min(10, g + 1))} aria-label="raise">+</button>
          </div>
          <div className="gh">
            {hist.map((x) => (
              <span key={x.q} className={x.current ? "on" : ""}>
                <b style={{ fontSize: s(14) }}>{x.current ? g : x.g}</b>
                <i style={{ width: (x.current ? g : x.g) * 10 + "%" }} />
                <em style={{ fontSize: s(9) }}>{x.q}</em>
              </span>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};

/* ── the stack ────────────────────────────────────────────────────────── */
const PlannerPages = ({ textScale = 1, gradeOn = true }) => {
  const s = (n) => Math.round(n * textScale * 10) / 10;
  const [commit, setCommit] = useCommit();
  const ref = React.useRef(null);
  const [i, setI] = React.useState(0);
  const go = (n) => {
    const el = ref.current;
    if (el) el.scrollTo({ top: n * el.clientHeight, behavior: "smooth" });
  };
  const onScroll = () => {
    const el = ref.current;
    if (el) setI(Math.round(el.scrollTop / el.clientHeight));
  };
  const pages = [
    <PgScore key="c" s={s} />,
    <PgDecision key="d" s={s} toGrade={gradeOn ? () => go(5) : null} />,
    <PgWeek key="w" s={s} />,
    <PgFloor key="f" s={s} />,
    <PgSell key="s" s={s} commit={commit} onCommit={setCommit} />,
  ];
  if (commit && commit.i != null && window.PLAN2.plan.picks[commit.i]) {
    pages.push(<PgMonitor key="m" s={s} commit={commit} onCommit={setCommit} />);
  }
  if (gradeOn) pages.push(<PgGrade key="g" s={s} />);
  return (
    <div className="pgs-wrap">
      <div className="pgs" ref={ref} onScroll={onScroll}>{pages}</div>
      <div className="pg-dots">
        {pages.map((x, n) => <button key={n} className={n === i ? "on" : ""} onClick={() => go(n)} aria-label={"page " + (n + 1)} />)}
      </div>
    </div>
  );
};

window.PlannerPages = PlannerPages;
