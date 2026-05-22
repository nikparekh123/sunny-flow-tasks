/**
 * Calculators — canvas shell only.
 *
 * Three zones: left rail (~56px) + sliding drawer (~280px) + centered canvas
 * (720×600). Selecting a calculator just sets state; no math is wired in yet.
 *
 * Tokens come from sunnyfi.css (--navi-*). All surfaces and typography follow
 * the design system: transparent cards with hairline borders, Work Sans body,
 * DM Mono for numbers, neon (#d2e632) for active and primary actions.
 */
import { useState } from "react";
import { useNavigate } from "react-router-dom";

type CalcKey =
  | "pct-diff" | "expected-income" | "put-cost" | "income-vs-cost"
  | "scenario" | "stress";

interface CalcItem {
  key: CalcKey;
  name: string;
  desc: string;
}

interface CalcGroup {
  name: string;
  comingSoon?: boolean;
  items: CalcItem[];
}

const GROUPS: CalcGroup[] = [
  {
    name: "Pre-Trade Planning",
    items: [
      { key: "pct-diff",        name: "Percentage Difference", desc: "Strike vs spot, distance to the line" },
      { key: "expected-income", name: "Expected Income",       desc: "Premium yield against capital at risk" },
      { key: "put-cost",        name: "Put Cost",              desc: "Hedge spend vs portfolio exposure" },
      { key: "income-vs-cost",  name: "Income vs Cost",        desc: "Net carry after protection" },
    ],
  },
  {
    name: "Scenario & Risk",
    items: [
      { key: "scenario", name: "Scenario Calculator", desc: "Project P&L across price paths" },
      { key: "stress",   name: "Stress Calculator",   desc: "Tail-risk drawdown by shock factor" },
    ],
  },
  { name: "Macro",             comingSoon: true, items: [] },
  { name: "Post-Trade Review", comingSoon: true, items: [] },
];

const CATEGORY_BY_KEY: Record<CalcKey, string> = {
  "pct-diff":        "Pre-Trade Planning",
  "expected-income": "Pre-Trade Planning",
  "put-cost":        "Pre-Trade Planning",
  "income-vs-cost":  "Pre-Trade Planning",
  "scenario":        "Scenario & Risk",
  "stress":          "Scenario & Risk",
};

// ── icons ───────────────────────────────────────────────────────────
const ICON = { fill: "none", stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
const Icon = ({ children, size = 18 }: { children: React.ReactNode; size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" {...ICON} aria-hidden>{children}</svg>
);
const Hamburger  = () => <Icon><path d="M4 7h16M4 12h16M4 17h16" /></Icon>;
const Dashboard  = () => <Icon><rect x="3" y="3" width="8" height="8" /><rect x="13" y="3" width="8" height="5" /><rect x="3" y="13" width="8" height="8" /><rect x="13" y="10" width="8" height="11" /></Icon>;
const Positions  = () => <Icon><rect x="3" y="3" width="8" height="13" /><rect x="13" y="3" width="8" height="8" /><rect x="3" y="18" width="8" height="3" /><rect x="13" y="13" width="8" height="8" /></Icon>;
const Strategy   = () => <Icon><rect x="3" y="4" width="18" height="4" /><rect x="3" y="10" width="18" height="4" /><rect x="3" y="16" width="18" height="4" /></Icon>;
const Research   = () => <Icon><path d="M4 4h12a4 4 0 0 1 4 4v12H8a4 4 0 0 1-4-4V4z" /><path d="M8 9h8M8 13h8M8 17h5" /></Icon>;
const Snowball   = () => <Icon><circle cx="12" cy="17" r="4" /><circle cx="12" cy="9" r="2.5" /><circle cx="12" cy="4" r="1.4" /></Icon>;
const HistoryIco = () => <Icon><path d="M3 12a9 9 0 1 0 3-6.7L3 8" /><path d="M3 3v5h5" /><path d="M12 7v5l3 2" /></Icon>;
const InfoIco    = () => <Icon size={14}><circle cx="12" cy="12" r="9" /><path d="M12 11v5M12 7.5v.01" /></Icon>;
const CloseIco   = () => <Icon size={16}><path d="M6 6l12 12M18 6L6 18" /></Icon>;

// ── styles ──────────────────────────────────────────────────────────
const RAIL_W   = 56;
const DRAWER_W = 280;
const CANVAS_W = 720;

const sx = {
  page: {
    minHeight: "100vh",
    background: "var(--navi-dash-page, #061a10)",
    color: "var(--navi-fg2, #a8c4c0)",
    fontFamily: "var(--navi-font-sans, 'Work Sans', system-ui)",
    fontSize: 13,
    lineHeight: 1.6,
    display: "flex",
    position: "relative" as const,
  },
  rail: {
    width: RAIL_W,
    minWidth: RAIL_W,
    background: "var(--navi-surface, #0f3333)",
    borderRight: "1px solid rgba(30,90,80,.35)",
    display: "flex",
    flexDirection: "column" as const,
    alignItems: "center",
    padding: "16px 0",
    gap: 6,
    position: "sticky" as const,
    top: 0,
    height: "100vh",
    zIndex: 30,
  },
  railBtn: (active: boolean) => ({
    width: 36, height: 36,
    display: "flex", alignItems: "center", justifyContent: "center",
    background: active ? "var(--navi-tint-neon, rgba(210,230,50,.10))" : "transparent",
    color: active ? "var(--navi-neon, #d2e632)" : "var(--navi-fg3, #7ab0a5)",
    border: "none",
    borderRadius: 6,
    cursor: "pointer",
    transition: "background 120ms, color 120ms",
  }),
  drawer: (open: boolean) => ({
    position: "fixed" as const,
    top: 0, left: RAIL_W,
    width: DRAWER_W,
    height: "100vh",
    background: "var(--navi-surface, #0f3333)",
    borderRight: "1px solid rgba(30,90,80,.35)",
    transform: open ? "translateX(0)" : `translateX(-${DRAWER_W + 8}px)`,
    transition: "transform 180ms ease",
    zIndex: 25,
    overflowY: "auto" as const,
    boxShadow: open ? "8px 0 24px rgba(0,0,0,.35)" : "none",
  }),
  drawerHead: {
    display: "flex", alignItems: "center", justifyContent: "space-between",
    padding: "20px 18px 14px",
    borderBottom: "1px solid rgba(30,90,80,.25)",
  },
  drawerTitle: {
    fontFamily: "var(--navi-font-sans)",
    fontSize: 14, fontWeight: 500,
    color: "var(--navi-fg1, #faf5f0)",
    letterSpacing: 0,
  },
  groupHead: {
    padding: "18px 18px 8px",
    fontSize: 9, fontWeight: 600, letterSpacing: 2,
    textTransform: "uppercase" as const,
    color: "var(--navi-fg4, #5a8680)",
    display: "flex", alignItems: "center", justifyContent: "space-between",
  },
  soonPill: {
    fontSize: 8, letterSpacing: 1.5,
    color: "var(--navi-fg5, #1e5a50)",
    fontWeight: 500,
  },
  calcItem: (active: boolean) => ({
    display: "block", width: "100%",
    background: active ? "var(--navi-tint-neon, rgba(210,230,50,.10))" : "transparent",
    border: "none",
    borderLeft: active ? "2px solid var(--navi-neon, #d2e632)" : "2px solid transparent",
    padding: "8px 16px",
    textAlign: "left" as const,
    cursor: "pointer",
    fontFamily: "inherit",
    transition: "background 100ms",
  }),
  calcName: (active: boolean) => ({
    fontSize: 13, fontWeight: 500,
    color: active ? "var(--navi-neon, #d2e632)" : "var(--navi-fg1, #faf5f0)",
    marginBottom: 2,
  }),
  calcDesc: {
    fontSize: 11,
    color: "var(--navi-fg4, #5a8680)",
    lineHeight: 1.4,
  },
  iconBtn: {
    background: "transparent", border: "none", padding: 6,
    color: "var(--navi-fg3, #7ab0a5)",
    cursor: "pointer", borderRadius: 4,
    display: "flex", alignItems: "center", justifyContent: "center",
  },
  main: {
    flex: 1, minWidth: 0,
    padding: "48px 32px",
    display: "flex", justifyContent: "center",
    position: "relative" as const,
  },
  canvas: {
    width: CANVAS_W,
    minHeight: 600,
    background: "var(--navi-page, #0a2828)",
    border: "1px solid rgba(30,90,80,.35)",
    borderRadius: 4,
    display: "flex", flexDirection: "column" as const,
    overflow: "hidden",
    position: "relative" as const,
  },
  canvasHead: {
    display: "flex", alignItems: "flex-start", justifyContent: "space-between",
    padding: "22px 28px 14px",
    borderBottom: "1px solid rgba(30,90,80,.25)",
  },
  catLabel: {
    fontSize: 8, fontWeight: 600, letterSpacing: 2,
    textTransform: "uppercase" as const,
    color: "var(--navi-fg4, #5a8680)",
    marginBottom: 6,
  },
  calcTitleRow: { display: "flex", alignItems: "center", gap: 8 },
  calcTitle: {
    fontSize: 22, fontWeight: 500, letterSpacing: -0.3,
    color: "var(--navi-fg1, #faf5f0)",
  },
  description: {
    padding: "14px 28px 4px",
    fontSize: 13,
    color: "var(--navi-fg3, #7ab0a5)",
    lineHeight: 1.6,
  },
  placeholder: {
    margin: "18px 28px",
    border: "1px dashed rgba(50,110,100,.45)",
    borderRadius: 4,
    padding: "32px 20px",
    fontSize: 12,
    color: "var(--navi-fg4, #5a8680)",
    textAlign: "center" as const,
    fontFamily: "var(--navi-font-mono)",
  },
  resultsPlaceholder: {
    margin: "0 28px 18px",
    border: "1px dashed rgba(50,110,100,.45)",
    borderRadius: 4,
    padding: "32px 20px",
    fontSize: 12,
    color: "var(--navi-fg4, #5a8680)",
    textAlign: "center" as const,
    fontFamily: "var(--navi-font-mono)",
  },
  footer: {
    marginTop: "auto",
    display: "flex", alignItems: "center", justifyContent: "space-between",
    padding: "18px 28px 22px",
    borderTop: "1px solid rgba(30,90,80,.25)",
  },
  textBtn: {
    background: "transparent", border: "none",
    color: "var(--navi-fg3, #7ab0a5)",
    fontSize: 13, fontWeight: 500,
    fontFamily: "var(--navi-font-sans)",
    cursor: "pointer", padding: 0,
  },
  primaryBtn: {
    background: "transparent", border: "none",
    color: "var(--navi-neon, #d2e632)",
    fontSize: 13, fontWeight: 600,
    fontFamily: "var(--navi-font-sans)",
    letterSpacing: 0.2,
    cursor: "pointer", padding: 0,
  },
  empty: {
    flex: 1,
    display: "flex", alignItems: "center", justifyContent: "center",
    fontSize: 13,
    color: "var(--navi-fg4, #5a8680)",
    fontFamily: "var(--navi-font-mono)",
  },
  // History side panel — slides in within the canvas frame
  historyPanel: (open: boolean) => ({
    position: "absolute" as const,
    top: 0, right: 0,
    width: 320, height: "100%",
    background: "var(--navi-surface, #0f3333)",
    borderLeft: "1px solid rgba(30,90,80,.35)",
    transform: open ? "translateX(0)" : "translateX(100%)",
    transition: "transform 180ms ease",
    display: "flex", flexDirection: "column" as const,
  }),
  historyHead: {
    display: "flex", alignItems: "center", justifyContent: "space-between",
    padding: "18px 18px 14px",
    borderBottom: "1px solid rgba(30,90,80,.25)",
    fontSize: 8, fontWeight: 600, letterSpacing: 2,
    textTransform: "uppercase" as const,
    color: "var(--navi-fg4, #5a8680)",
  },
  // Save modal
  modalBackdrop: {
    position: "fixed" as const, inset: 0,
    background: "rgba(6,26,16,.72)",
    backdropFilter: "blur(2px)",
    display: "flex", alignItems: "center", justifyContent: "center",
    zIndex: 100,
  },
  modal: {
    width: 460,
    background: "var(--navi-surface, #0f3333)",
    border: "1px solid rgba(50,110,100,.35)",
    borderRadius: 4,
    padding: 24,
  },
  modalTitle: {
    fontSize: 16, fontWeight: 500,
    color: "var(--navi-fg1, #faf5f0)",
    marginBottom: 18,
  },
  field: { marginBottom: 14 },
  fieldLabel: {
    fontSize: 8, fontWeight: 600, letterSpacing: 2,
    textTransform: "uppercase" as const,
    color: "var(--navi-fg4, #5a8680)",
    marginBottom: 6,
    display: "block",
  },
  input: {
    width: "100%",
    background: "var(--navi-page, #0a2828)",
    border: "1px solid rgba(30,90,80,.35)",
    borderRadius: 3,
    padding: "8px 10px",
    color: "var(--navi-fg1, #faf5f0)",
    fontFamily: "var(--navi-font-sans)",
    fontSize: 13,
    outline: "none",
    boxSizing: "border-box" as const,
  },
  metaRow: {
    display: "grid", gridTemplateColumns: "repeat(3, 1fr)",
    gap: 12,
    padding: "12px 0",
    borderTop: "1px solid rgba(30,90,80,.25)",
    borderBottom: "1px solid rgba(30,90,80,.25)",
    margin: "14px 0 18px",
  },
  metaLabel: {
    fontSize: 8, fontWeight: 600, letterSpacing: 2,
    textTransform: "uppercase" as const,
    color: "var(--navi-fg4, #5a8680)",
    marginBottom: 4,
  },
  metaValue: {
    fontFamily: "var(--navi-font-mono)",
    fontSize: 12,
    color: "var(--navi-fg2, #a8c4c0)",
  },
  modalActions: {
    display: "flex", justifyContent: "flex-end", gap: 24,
    marginTop: 4,
  },
};

// ── component ───────────────────────────────────────────────────────
export default function Calculators() {
  const navigate = useNavigate();
  const [drawerOpen, setDrawerOpen] = useState(true);
  const [selected, setSelected]     = useState<CalcKey | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [saveOpen, setSaveOpen]     = useState(false);

  const selectedItem = selected
    ? GROUPS.flatMap((g) => g.items).find((i) => i.key === selected) || null
    : null;
  const selectedCategory = selected ? CATEGORY_BY_KEY[selected] : null;

  const onPick = (key: CalcKey) => {
    setSelected(key);
    setDrawerOpen(false);
    setHistoryOpen(false);
  };

  const onReset = () => {
    // Placeholder — calculators will own their own reset
  };

  return (
    <div style={sx.page}>
      {/* Left rail */}
      <nav style={sx.rail} aria-label="Sunnyfi navigation">
        <button
          style={sx.railBtn(drawerOpen)}
          onClick={() => setDrawerOpen((v) => !v)}
          title="Calculators"
          aria-label="Toggle calculator drawer"
        >
          <Hamburger />
        </button>
        <div style={{ height: 12 }} />
        <button style={sx.railBtn(false)} onClick={() => navigate("/dashboard")} title="Dashboard"><Dashboard /></button>
        <button style={sx.railBtn(false)} onClick={() => window.location.assign("https://positions.sunnyfi.co")} title="Positions"><Positions /></button>
        <button style={sx.railBtn(false)} onClick={() => navigate("/strategy")} title="Strategy"><Strategy /></button>
        <button style={sx.railBtn(false)} onClick={() => navigate("/research")} title="Research"><Research /></button>
        <button style={sx.railBtn(false)} onClick={() => navigate("/snowball")} title="Snowball"><Snowball /></button>
      </nav>

      {/* Drawer */}
      <aside style={sx.drawer(drawerOpen)} aria-hidden={!drawerOpen}>
        <div style={sx.drawerHead}>
          <div style={sx.drawerTitle}>Calculators</div>
          <button style={sx.iconBtn} onClick={() => setDrawerOpen(false)} aria-label="Close drawer">
            <CloseIco />
          </button>
        </div>

        {GROUPS.map((group) => (
          <div key={group.name}>
            <div style={sx.groupHead}>
              <span>{group.name}</span>
              {group.comingSoon && <span style={sx.soonPill}>Coming soon</span>}
            </div>
            {group.items.map((item) => {
              const active = selected === item.key;
              return (
                <button
                  key={item.key}
                  style={sx.calcItem(active)}
                  onClick={() => onPick(item.key)}
                >
                  <div style={sx.calcName(active)}>{item.name}</div>
                  <div style={sx.calcDesc}>{item.desc}</div>
                </button>
              );
            })}
          </div>
        ))}
        <div style={{ height: 24 }} />
      </aside>

      {/* Main: canvas */}
      <main style={sx.main}>
        <div style={sx.canvas}>
          {!selectedItem ? (
            <div style={sx.empty}>Select a calculator from the left to begin</div>
          ) : (
            <>
              <div style={sx.canvasHead}>
                <div>
                  <div style={sx.catLabel}>{selectedCategory}</div>
                  <div style={sx.calcTitleRow}>
                    <span style={sx.calcTitle}>{selectedItem.name}</span>
                    <button style={sx.iconBtn} title="About this calculator" aria-label="About">
                      <InfoIco />
                    </button>
                  </div>
                </div>
                <button
                  style={sx.iconBtn}
                  onClick={() => setHistoryOpen((v) => !v)}
                  title="Saved calculations"
                  aria-label="Open history"
                >
                  <HistoryIco />
                </button>
              </div>

              <div style={sx.description}>{selectedItem.desc}.</div>

              <div style={sx.placeholder}>Inputs render here</div>
              <div style={sx.resultsPlaceholder}>Results render here</div>

              <div style={sx.footer}>
                <button style={sx.textBtn} onClick={onReset}>Reset</button>
                <button style={sx.primaryBtn} onClick={() => setSaveOpen(true)}>Save Calculation</button>
              </div>

              {/* History panel (within canvas frame) */}
              <aside style={sx.historyPanel(historyOpen)} aria-hidden={!historyOpen}>
                <div style={sx.historyHead}>
                  <span>Saved Calculations</span>
                  <button style={sx.iconBtn} onClick={() => setHistoryOpen(false)} aria-label="Close history">
                    <CloseIco />
                  </button>
                </div>
                <div style={{ ...sx.empty, padding: 24 }}>No saved calculations yet</div>
              </aside>
            </>
          )}
        </div>
      </main>

      {/* Save modal */}
      {saveOpen && selectedItem && (
        <div style={sx.modalBackdrop} onClick={() => setSaveOpen(false)}>
          <div style={sx.modal} onClick={(e) => e.stopPropagation()}>
            <div style={sx.modalTitle}>Save Calculation</div>

            <div style={sx.field}>
              <label style={sx.fieldLabel}>Name</label>
              <input style={sx.input} placeholder="e.g. AAPL Jan 220p hedge" autoFocus />
            </div>

            <div style={sx.field}>
              <label style={sx.fieldLabel}>Purpose</label>
              <textarea
                style={{ ...sx.input, height: 64, resize: "vertical", fontFamily: "var(--navi-font-sans)" }}
                placeholder="What this scenario is for (optional)"
              />
            </div>

            <div style={sx.metaRow}>
              <div>
                <div style={sx.metaLabel}>Calculator</div>
                <div style={sx.metaValue}>{selectedItem.name}</div>
              </div>
              <div>
                <div style={sx.metaLabel}>Category</div>
                <div style={sx.metaValue}>{selectedCategory}</div>
              </div>
              <div>
                <div style={sx.metaLabel}>Timestamp</div>
                <div style={sx.metaValue}>{new Date().toISOString().slice(0, 16).replace("T", " ")}</div>
              </div>
            </div>

            <div style={sx.modalActions}>
              <button style={sx.textBtn} onClick={() => setSaveOpen(false)}>Cancel</button>
              <button style={sx.primaryBtn} onClick={() => setSaveOpen(false)}>Save</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
