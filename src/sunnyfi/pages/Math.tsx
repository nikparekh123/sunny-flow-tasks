/**
 * Math — page route.
 *
 * Hosts the runtime state machine for the six hi-fi screens:
 *   1. Resting        — selectedCalc == null && !searchOpen
 *   2. Palette open   — searchOpen
 *   3. Calc loaded    — selectedCalc set, no modal/compare
 *   4. History modal  — modal === "history"
 *   5. Compare mode   — compareMode (full-stage replacement)
 *   6. Share modal    — modal === "share"
 *
 * Snapshots persist to localStorage via useSnapshots(). The calculator body
 * itself is a CalcEmpty placeholder until per-calc components are wired in
 * (next PR).
 */
import { useEffect, useMemo, useRef, useState } from "react";
import "../math/math.css";
import {
  SunnyfiShell,
  PickHero,
  CalcShell,
  CalcEmpty,
  SnapTag,
  Modal,
  Palette,
  OverlaySearch,
  CatHead,
  CalcOption,
  Chip,
  Segmented,
  Field,
  type DockKey,
} from "../math/shell";
import {
  CALCS,
  CATEGORIES,
  type CalcCategory,
  findCalc,
  categoryLabel,
  popularCalcs,
  type CalcMeta,
} from "../math/data";
import { useSnapshots, relTime, type Snapshot } from "../math/store";

const DASHBOARD_URL = "https://www.sunnyfi.co/dashboard";

// ── Page ───────────────────────────────────────────────────────────
export default function MathPage() {
  const { snaps, create, remove } = useSnapshots();

  const [selectedCalc, setSelectedCalc] = useState<string | null>(null);
  const [searchOpen, setSearchOpen]     = useState(false);
  const [searchValue, setSearchValue]   = useState("");
  const [modal, setModal]               = useState<"history" | "share" | null>(null);
  const [compareMode, setCompareMode]   = useState(false);
  const [compareA, setCompareA]         = useState<string | null>(null);
  const [compareB, setCompareB]         = useState<string | null>(null);

  // Current working snapshot (untitled until saved). Going back to resting
  // resets it.
  const [snapName, setSnapName]       = useState("untitled snapshot");
  const [snapDirty, setSnapDirty]     = useState(true);
  const [savedSnapId, setSavedSnapId] = useState<string | null>(null);
  const [renaming, setRenaming]       = useState(false);

  // Selected row in History modal.
  const [historySelected, setHistorySelected] = useState<string | null>(null);
  const [historyFilter, setHistoryFilter]     = useState<"All" | "This calculator" | "Tagged">("All");

  // ── derived ──
  const calc       = findCalc(selectedCalc);
  const route      = compareMode ? "Compare" : calc ? calc.name : "Math";
  const canSave    = !!calc;
  const canCompare = snaps.length >= 2;
  const dockActive: DockKey | null =
    modal === "history" ? "history" :
    modal === "share"   ? "share"   :
    compareMode         ? "compare" :
    null;

  // Reset working snap when calc changes (or unselects).
  useEffect(() => {
    if (!selectedCalc) {
      setSnapName("untitled snapshot");
      setSnapDirty(true);
      setSavedSnapId(null);
      setRenaming(false);
    } else {
      setSnapName("untitled snapshot");
      setSnapDirty(true);
      setSavedSnapId(null);
    }
  }, [selectedCalc]);

  // ── global keys: Cmd-K toggles search, Esc cascades ──
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const cmd = e.metaKey || e.ctrlKey;
      if (cmd && (e.key === "k" || e.key === "K")) {
        e.preventDefault();
        setSearchOpen((v) => !v);
        return;
      }
      if (e.key === "Escape") {
        if (searchOpen)     { setSearchOpen(false);  return; }
        if (modal)          { setModal(null);        return; }
        if (compareMode)    { setCompareMode(false); return; }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [searchOpen, modal, compareMode]);

  // ── actions ──
  const pickCalc = (key: string) => {
    setSelectedCalc(key);
    setSearchOpen(false);
    setSearchValue("");
    setModal(null);
    setCompareMode(false);
  };

  const saveSnap = () => {
    if (!calc) return;
    const snap = create({
      calcKey: calc.key,
      name: snapName === "untitled snapshot" ? `${calc.name} · ${new Date().toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })}` : snapName,
    });
    setSavedSnapId(snap.id);
    setSnapName(snap.name);
    setSnapDirty(false);
  };

  const handleDock = (k: DockKey) => {
    if (k === "snapshot") { saveSnap(); return; }
    if (k === "history")  { setModal((m) => m === "history" ? null : "history"); return; }
    if (k === "compare")  {
      if (!canCompare) return;
      setCompareMode((v) => !v);
      // Default to two most recent snapshots
      if (!compareA) setCompareA(snaps[0]?.id ?? null);
      if (!compareB) setCompareB(snaps[1]?.id ?? null);
      return;
    }
    if (k === "share")    { setModal((m) => m === "share" ? null : "share"); return; }
  };

  // ── render branches ──
  return (
    <SunnyfiShell
      route={route}
      searchOpen={searchOpen}
      onSearchClick={() => setSearchOpen(true)}
      onSearchClose={() => setSearchOpen(false)}
      dim={modal !== null}
      dockActive={dockActive}
      onDockClick={handleDock}
      onSave={saveSnap}
      onShare={() => setModal("share")}
      onBrandClick={() => {
        if (compareMode || selectedCalc || modal || searchOpen) {
          // First click backs out of the current mode.
          setModal(null);
          setCompareMode(false);
          setSearchOpen(false);
          setSelectedCalc(null);
        } else {
          window.location.assign(DASHBOARD_URL);
        }
      }}
      canSave={canSave}
      canCompare={canCompare}
      showShare={!compareMode}
      hideDock={searchOpen}
    >
      {/* ── Compare mode: full-stage takeover ── */}
      {compareMode ? (
        <CompareStage
          snaps={snaps}
          aId={compareA}
          bId={compareB}
          onPickA={setCompareA}
          onPickB={setCompareB}
          onExit={() => setCompareMode(false)}
        />
      ) : (
        <>
          {selectedCalc && calc ? (
            <div className="hf-calc-stage">
              <CalcShell
                crumbs={<>{categoryLabel(calc.category)} <span className="sep">›</span> {calc.name}</>}
                title={
                  renaming ? (
                    <RenameInput
                      defaultValue={snapName}
                      onCommit={(v) => { setSnapName(v.trim() || "untitled snapshot"); setRenaming(false); setSnapDirty(true); }}
                      onCancel={() => setRenaming(false)}
                    />
                  ) : (
                    <>
                      {calc.name}
                      <span className="dim">·</span>
                      <span className="snap-name">{snapName}</span>
                    </>
                  )
                }
                snapTag={
                  snapDirty
                    ? <SnapTag tone="warn">● unsaved</SnapTag>
                    : <SnapTag tone="pos">● {snapName}</SnapTag>
                }
                actions={
                  <>
                    <button className="hf-btn ghost tiny" onClick={() => setRenaming(true)}>Rename</button>
                    <button className="hf-btn ghost tiny" title="More">⋯</button>
                  </>
                }
              >
                <CalcEmpty label={`${calc.name.toUpperCase()} · content area`} />
              </CalcShell>
            </div>
          ) : (
            <div className="hf-pick-stage">
              <PickHero
                available={CALCS.length}
                open={selectedCalc ? 1 : 0}
                popular={popularCalcs().map((c) => ({ key: c.key, name: c.name }))}
                onPickPopular={pickCalc}
              />
            </div>
          )}
        </>
      )}

      {/* ── Palette overlay (search open) ── */}
      {searchOpen && (
        <Palette
          searchBar={
            <OverlaySearch
              value={searchValue}
              onChange={setSearchValue}
              autoFocus
            />
          }
        >
          <PaletteResults
            query={searchValue}
            onPick={pickCalc}
            recents={snaps.slice(0, 3)}
          />
        </Palette>
      )}

      {/* ── History modal ── */}
      {modal === "history" && (
        <Modal
          eyebrow={`Snapshots · ${snaps.length} saved · ${historySelected ? 1 : 0} selected`}
          title="History"
          subtitle="Restore, share, compare — any saved state across every calculator."
          width={1020}
          onClose={() => setModal(null)}
          footer={
            <div className="hf-foot-row">
              <div className="hf-foot-hint">⇧↑↓ to multi-select · esc to close</div>
              <div className="hf-foot-actions">
                <button className="hf-btn ghost" disabled={!historySelected}>↗ Share selected</button>
                <button className="hf-btn neon" disabled={!canCompare}>⇆ Compare 2</button>
              </div>
            </div>
          }
        >
          <HistoryBody
            snaps={snaps}
            currentCalcKey={calc?.key ?? null}
            filter={historyFilter}
            onFilter={setHistoryFilter}
            selected={historySelected}
            onSelect={setHistorySelected}
            onDelete={(id) => { remove(id); if (historySelected === id) setHistorySelected(null); }}
          />
        </Modal>
      )}

      {/* ── Share modal ── */}
      {modal === "share" && (
        <Modal
          eyebrow={`Snapshot · ${snapName}`}
          title="Share snapshot"
          subtitle="One link. View-only by default. Permissions and contents are configurable."
          width={900}
          onClose={() => setModal(null)}
          footer={
            <div className="hf-foot-row">
              <div className="hf-foot-hint">
                Want to share a comparison instead?{" "}
                <a className="hf-link" href="#" onClick={(e) => { e.preventDefault(); }}>
                  Switch to comparison share →
                </a>
              </div>
              <div className="hf-foot-actions">
                <button className="hf-btn ghost">↓ Export JSON</button>
                <button className="hf-btn neon" onClick={() => setModal(null)}>Done</button>
              </div>
            </div>
          }
        >
          <ShareBody calc={calc} snapName={snapName} savedSnap={savedSnapId ? snaps.find((s) => s.id === savedSnapId) ?? null : null} />
        </Modal>
      )}
    </SunnyfiShell>
  );
}

// ── Rename input ─────────────────────────────────────────────────
function RenameInput({
  defaultValue,
  onCommit,
  onCancel,
}: {
  defaultValue: string;
  onCommit: (v: string) => void;
  onCancel: () => void;
}) {
  const ref = useRef<HTMLInputElement | null>(null);
  useEffect(() => { ref.current?.focus(); ref.current?.select(); }, []);
  return (
    <input
      ref={ref}
      className="hf-rename-input"
      defaultValue={defaultValue}
      onKeyDown={(e) => {
        if (e.key === "Enter") onCommit((e.target as HTMLInputElement).value);
        if (e.key === "Escape") onCancel();
      }}
      onBlur={(e) => onCommit(e.target.value)}
    />
  );
}

// ── Palette results ──────────────────────────────────────────────
function PaletteResults({
  query,
  onPick,
  recents,
}: {
  query: string;
  onPick: (key: string) => void;
  recents: Snapshot[];
}) {
  const q = query.trim().toLowerCase();
  const matches = q
    ? CALCS.filter((c) => c.name.toLowerCase().includes(q))
    : [];
  const recentCalcs = useMemo(() => {
    const seen = new Set<string>();
    const out: CalcMeta[] = [];
    for (const r of recents) {
      if (seen.has(r.calcKey)) continue;
      const c = findCalc(r.calcKey);
      if (c) { out.push(c); seen.add(r.calcKey); }
    }
    return out;
  }, [recents]);

  // Group all calcs by category for the "All" section.
  const groups: { cat: CalcCategory; items: CalcMeta[] }[] = (Object.keys(CATEGORIES) as CalcCategory[])
    .map((cat) => ({ cat, items: CALCS.filter((c) => c.category === cat) }))
    .filter((g) => g.items.length > 0);

  return (
    <>
      {q && (
        <>
          <CatHead count={matches.length}>Matches · "{query}"</CatHead>
          {matches.length === 0 ? (
            <div style={{ padding: "12px 4px", color: "var(--navi-fg4)", fontSize: 13 }}>
              No calculators match.
            </div>
          ) : (
            matches.map((c, i) => (
              <CalcOption
                key={c.key}
                name={c.name}
                hint={c.hint}
                match={query}
                kbd={i === 0 ? "↵" : undefined}
                active={i === 0}
                onClick={() => onPick(c.key)}
              />
            ))
          )}
        </>
      )}

      {recentCalcs.length > 0 && (
        <>
          <CatHead count={recentCalcs.length}>Recent</CatHead>
          {recentCalcs.map((c) => {
            const r = recents.find((s) => s.calcKey === c.key);
            return (
              <CalcOption
                key={c.key}
                name={c.name}
                hint={c.hint}
                meta={r ? `opened ${relTime(r.createdAt)}` : undefined}
                onClick={() => onPick(c.key)}
              />
            );
          })}
        </>
      )}

      {groups.map((g) => (
        <div key={g.cat}>
          <CatHead count={g.items.length}>All · {categoryLabel(g.cat)}</CatHead>
          {g.items.map((c) => (
            <CalcOption
              key={c.key}
              name={c.name}
              hint={c.hint}
              onClick={() => onPick(c.key)}
            />
          ))}
        </div>
      ))}
    </>
  );
}

// ── History body ─────────────────────────────────────────────────
function HistoryBody({
  snaps,
  currentCalcKey,
  filter,
  onFilter,
  selected,
  onSelect,
  onDelete,
}: {
  snaps: Snapshot[];
  currentCalcKey: string | null;
  filter: "All" | "This calculator" | "Tagged";
  onFilter: (v: "All" | "This calculator" | "Tagged") => void;
  selected: string | null;
  onSelect: (id: string | null) => void;
  onDelete: (id: string) => void;
}) {
  const [search, setSearch] = useState("");
  const filtered = useMemo(() => {
    let list = snaps;
    if (filter === "This calculator" && currentCalcKey) {
      list = list.filter((s) => s.calcKey === currentCalcKey);
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      list = list.filter((s) => s.name.toLowerCase().includes(q));
    }
    return list;
  }, [snaps, filter, currentCalcKey, search]);

  const selectedSnap = selected ? snaps.find((s) => s.id === selected) ?? null : null;
  const selectedCalc = selectedSnap ? findCalc(selectedSnap.calcKey) : null;

  return (
    <div className="hf-history">
      <div className="hf-history-left">
        <div className="hf-history-controls">
          <Segmented<"All" | "This calculator" | "Tagged">
            options={["All", "This calculator", "Tagged"]}
            value={filter}
            onChange={onFilter}
          />
          <div className="hf-mini-search">
            <span className="hf-glass-wrap">
              <svg viewBox="0 0 16 16" width="13" height="13"><circle cx="7" cy="7" r="4.5" fill="none" stroke="currentColor" strokeWidth="1.4"/><line x1="10.2" y1="10.2" x2="14" y2="14" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/></svg>
            </span>
            <input
              placeholder="search snapshots…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        </div>

        {filtered.length === 0 ? (
          <div className="hf-hist-empty">
            <div>No saved calculations yet</div>
            <div style={{ fontSize: 11, color: "var(--navi-fg5)" }}>
              Open a calculator and hit <kbd>✓ Save</kbd> in the top bar.
            </div>
          </div>
        ) : (
          <div className="hf-hist-list">
            {filtered.map((s) => {
              const c = findCalc(s.calcKey);
              return (
                <button
                  key={s.id}
                  className={`hf-snaprow ${selected === s.id ? "selected" : ""}`}
                  onClick={() => onSelect(s.id)}
                >
                  <div>
                    <div className="hf-snaprow-name">{s.name}</div>
                    <div className="hf-snaprow-meta">
                      <span className="calc">{c?.name ?? s.calcKey}</span>
                      {s.purpose && <><span className="dot">·</span><span>{s.purpose}</span></>}
                    </div>
                  </div>
                  <div className="hf-snaprow-side">
                    <div className="hf-snaprow-val muted">—</div>
                    <div className="hf-snaprow-time">{relTime(s.createdAt)}</div>
                  </div>
                </button>
              );
            })}
          </div>
        )}
      </div>

      <div className={`hf-history-right ${selectedSnap ? "" : "empty"}`}>
        {!selectedSnap ? (
          <div>Select a snapshot on the left to preview.</div>
        ) : (
          <>
            <div className="hf-preview-head">
              <div className="hf-eyebrow">Snapshot · {selectedSnap.name}</div>
              <div className="hf-preview-title">{selectedCalc?.name ?? selectedSnap.calcKey}</div>
              <div className="hf-preview-meta">
                saved {relTime(selectedSnap.createdAt)} · by you
              </div>
            </div>

            <div className="hf-preview-stat">
              <div className="hf-preview-num muted">—</div>
              <div className="hf-preview-delta">
                result · calculator body not wired yet
              </div>
            </div>

            <div className="hf-preview-grid">
              <Field label="Calculator" value={selectedCalc?.name ?? selectedSnap.calcKey} mono />
              <Field label="Category"   value={selectedCalc ? categoryLabel(selectedCalc.category) : "—"} mono />
              <Field label="Created"    value={new Date(selectedSnap.createdAt).toLocaleString()} mono />
              <Field label="Purpose"    value={selectedSnap.purpose || "—"} mono />
            </div>

            <div className="hf-preview-actions">
              <button className="hf-btn neon">⤺ Restore into calc</button>
              <button className="hf-btn ghost">⇆ Compare with…</button>
              <button className="hf-btn ghost">↗ Share</button>
              <button className="hf-btn danger" onClick={() => onDelete(selectedSnap.id)}>✕ Delete</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

// ── Compare stage ────────────────────────────────────────────────
function CompareStage({
  snaps,
  aId,
  bId,
  onPickA,
  onPickB,
  onExit,
}: {
  snaps: Snapshot[];
  aId: string | null;
  bId: string | null;
  onPickA: (id: string | null) => void;
  onPickB: (id: string | null) => void;
  onExit: () => void;
}) {
  const a = aId ? snaps.find((s) => s.id === aId) ?? null : null;
  const b = bId ? snaps.find((s) => s.id === bId) ?? null : null;
  const aCalc = a ? findCalc(a.calcKey) : null;
  const bCalc = b ? findCalc(b.calcKey) : null;

  return (
    <>
      <div className="hf-cmp-bar">
        <div className="left">
          <span className="hf-eyebrow">Comparing</span>
          <Chip tone="neon" active>A · {a?.name ?? "pick snapshot"}</Chip>
          <span className="vs">vs</span>
          <Chip tone="warn" active>B · {b?.name ?? "pick snapshot"}</Chip>
        </div>
        <div className="right">
          <label className="hf-check"><input type="checkbox" defaultChecked /> Lock A</label>
          <label className="hf-check"><input type="checkbox" /> Link inputs</label>
          <button className="hf-btn tinted" disabled>↗ Share comparison</button>
          <button className="hf-btn danger" onClick={onExit}>✕ Exit compare</button>
        </div>
      </div>

      {a && b ? (
        <>
          <div className="hf-cmp-headline">
            <div className="hf-eyebrow">Result · A → B</div>
            <div className="hf-cmp-bignum">
              <span className="a">—</span>
              <span className="arr">→</span>
              <span className="b">—</span>
            </div>
            <div className="hf-cmp-delta">
              <span className="hf-eyebrow soft">delta will appear when calculators are wired</span>
            </div>
          </div>

          <div className="hf-cmp-grid">
            <div className="hf-cmp-col">
              <div className="hf-cmp-colhead a">
                <div className="hf-eyebrow">A · locked</div>
                <div className="title">{a.name}</div>
                <div className="meta">{aCalc?.name ?? a.calcKey} · saved {relTime(a.createdAt)}</div>
              </div>
              <CalcShell accent style={{ flex: 1 }}>
                <CalcEmpty label="Calculator A · content area" />
              </CalcShell>
            </div>

            <div className="hf-cmp-diff">
              <div className="hf-section">Δ Per-input diff</div>
              <div style={{ color: "var(--navi-fg4)", fontSize: 12, fontFamily: "var(--navi-font-mono)" }}>
                Diff rows will populate once both calculators expose their inputs.
              </div>
            </div>

            <div className="hf-cmp-col">
              <div className="hf-cmp-colhead b">
                <div className="hf-eyebrow">B</div>
                <div className="title">{b.name}</div>
                <div className="meta">{bCalc?.name ?? b.calcKey} · saved {relTime(b.createdAt)}</div>
              </div>
              <CalcShell tint style={{ flex: 1 }}>
                <CalcEmpty label="Calculator B · content area" />
              </CalcShell>
            </div>
          </div>
        </>
      ) : (
        <div className="hf-cmp-grid">
          <div className="hf-cmp-empty">
            <div>
              <div style={{ marginBottom: 12, color: "var(--navi-fg2)", fontFamily: "var(--navi-font-sans)", fontSize: 16 }}>
                Pick two snapshots to compare.
              </div>
              <div style={{ display: "flex", gap: 12, justifyContent: "center", flexWrap: "wrap" }}>
                <select
                  value={aId ?? ""}
                  onChange={(e) => onPickA(e.target.value || null)}
                  style={selectStyle}
                >
                  <option value="">A · pick a snapshot</option>
                  {snaps.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
                <select
                  value={bId ?? ""}
                  onChange={(e) => onPickB(e.target.value || null)}
                  style={selectStyle}
                >
                  <option value="">B · pick a snapshot</option>
                  {snaps.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

const selectStyle: React.CSSProperties = {
  background: "var(--navi-surface)",
  border: "1px solid rgba(50,110,100,.4)",
  borderRadius: 8,
  padding: "10px 14px",
  color: "var(--navi-fg1)",
  fontFamily: "var(--navi-font-mono)",
  fontSize: 13,
  outline: "none",
  cursor: "pointer",
};

// ── Share body ───────────────────────────────────────────────────
function ShareBody({
  calc,
  snapName,
  savedSnap,
}: {
  calc: CalcMeta | null;
  snapName: string;
  savedSnap: Snapshot | null;
}) {
  const url = `sunnyfi.co/s/${(savedSnap?.id ?? "draft").slice(0, 12)}`;
  return (
    <div className="hf-share">
      <div className="hf-share-card">
        <div className="hf-share-card-eyebrow">Preview · what they'll see</div>
        <div className="hf-share-card-body">
          <div className="hf-share-card-meta">
            {calc?.name ?? "Math"} · {savedSnap ? relTime(savedSnap.createdAt) : "draft"}
          </div>
          <div className="hf-share-card-title">{snapName}</div>
          <div className="hf-share-card-k">Result · unsaved</div>
          <div className="hf-share-card-v muted">—</div>
          <div className="hf-share-card-row">
            <Field label="Calculator" value={calc?.name ?? "—"} mono />
            <Field label="Category"   value={calc ? categoryLabel(calc.category) : "—"} mono />
            <Field label="Saved"      value={savedSnap ? relTime(savedSnap.createdAt) : "draft"} mono />
          </div>
          <div className="hf-share-card-tags">
            <Chip>#draft</Chip>
          </div>
          <div className="hf-share-card-foot">
            <span>shared by you</span>
            <span>sunnyfi</span>
          </div>
        </div>
      </div>

      <div className="hf-share-controls">
        <div className="hf-ctrl">
          <div className="hf-eyebrow">Link access</div>
          <Segmented<"View only" | "Copy & edit" | "Restricted">
            options={["View only", "Copy & edit", "Restricted"]}
            value="View only"
          />
        </div>

        <div className="hf-ctrl">
          <div className="hf-eyebrow">Include</div>
          <div className="hf-checks">
            <label><input type="checkbox" defaultChecked /> Inputs &amp; result</label>
            <label><input type="checkbox" defaultChecked /> Note &amp; tags</label>
            <label><input type="checkbox" /> Full snapshot history of this calc</label>
          </div>
        </div>

        <div className="hf-ctrl">
          <div className="hf-eyebrow">Link</div>
          <div className="hf-link-row">
            <div className="hf-link-url">{url}</div>
            <button
              className="hf-btn neon"
              onClick={() => { try { navigator.clipboard.writeText(`https://${url}`); } catch { /* ignore */ } }}
            >
              ⧉ Copy
            </button>
          </div>
          <div className="hf-link-hint">
            Anyone with this link can view ·{" "}
            <a className="hf-link" href="#" onClick={(e) => e.preventDefault()}>Revoke</a>
          </div>
        </div>
      </div>
    </div>
  );
}
