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
import { useSnapshots, useLiveState, relTime, type Snapshot } from "../math/store";
import { CALC_MODULES, type CalcModule } from "../math/calcs";
import { VariantsStrip, type SweepOption } from "../math/VariantsStrip";
import { FREQ_DEFS, PUT_FREQ_DEFS } from "../math/cycle";

const DASHBOARD_URL = "https://www.sunnyfi.co/dashboard";

// ── Page ───────────────────────────────────────────────────────────
export default function MathPage() {
  const { snaps, create, update, remove } = useSnapshots();

  const [selectedCalc, setSelectedCalc] = useState<string | null>(null);
  const [searchOpen, setSearchOpen]     = useState(false);
  const [searchValue, setSearchValue]   = useState("");
  const [modal, setModal]               = useState<"history" | "share" | null>(null);
  const [compareMode, setCompareMode]   = useState(false);

  // Current working snapshot (untitled until saved). Going back to resting
  // resets it.
  const [snapName, setSnapName]       = useState("untitled snapshot");
  const [savedSnapId, setSavedSnapId] = useState<string | null>(null);
  const [renaming, setRenaming]       = useState(false);
  const [toast, setToast]             = useState<string>("");

  // Selected row in History modal.
  const [historySelected, setHistorySelected] = useState<string | null>(null);
  const [historyFilter, setHistoryFilter]     = useState<"All" | "This calculator" | "Tagged">("All");

  // ── derived ──
  const calc       = findCalc(selectedCalc);
  const calcModule = calc ? (CALC_MODULES[calc.key] as CalcModule | undefined) : undefined;
  const route      = compareMode ? "Compare" : calc ? calc.name : "Math";
  const canSave    = !!calc;
  const canCompare = snaps.length >= 2;

  // Per-calc live state (persisted to localStorage). When no calc is selected
  // we pass null + an empty initial — useLiveState becomes a no-op.
  const [liveState, setLiveState] = useLiveState<Record<string, unknown>>(
    calcModule ? (selectedCalc as string) : null,
    calcModule?.initial ?? {},
  );

  // Dirty = liveState diverges from the saved snapshot's payload.
  const snapDirty = useMemo(() => {
    if (!calcModule || !savedSnapId) return true;
    const snap = snaps.find((s) => s.id === savedSnapId);
    if (!snap) return true;
    return JSON.stringify(liveState) !== JSON.stringify(snap.payload);
  }, [calcModule, savedSnapId, snaps, liveState]);

  // Brief toast for Reset / Copy / Save confirmations.
  const flash = (msg: string) => {
    setToast(msg);
    window.clearTimeout((window as unknown as { __mathToastT?: number }).__mathToastT);
    (window as unknown as { __mathToastT?: number }).__mathToastT = window.setTimeout(() => setToast(""), 2400);
  };
  const dockActive: DockKey | null =
    modal === "history" ? "history" :
    modal === "share"   ? "share"   :
    compareMode         ? "compare" :
    null;

  // Reset working snap when calc changes (or unselects). The live inputs
  // restore from localStorage inside useLiveState — we only clear the snap
  // pointer here.
  useEffect(() => {
    setSnapName("untitled snapshot");
    setSavedSnapId(null);
    setRenaming(false);
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

  const saveSnap = async () => {
    if (!calc) return;
    const payload = calcModule ? { ...liveState } : {};
    // Upsert by the calc's identity key (e.g. ticker) — re-saving the same
    // ticker for the same calc overwrites the existing snapshot rather than
    // stacking duplicates. Calcs that don't have a meaningful identity key
    // (e.g. Percentage Difference) always create new rows.
    const upsertKey = calcModule?.upsertKey?.(liveState) ?? null;
    const existing = upsertKey
      ? snaps.find((s) => s.calcKey === calc.key && (calcModule?.upsertKey?.(s.payload) ?? null) === upsertKey)
      : null;

    // Auto-name uses the ticker when available, otherwise a timestamp.
    const t = new Date();
    const stamp = `${String(t.getHours()).padStart(2, "0")}:${String(t.getMinutes()).padStart(2, "0")}`;
    const autoName = upsertKey
      ? `${calc.name} · ${upsertKey}`
      : `Snapshot · ${stamp}`;
    const name =
      snapName === "untitled snapshot"
        ? (existing?.name ?? autoName)
        : snapName;

    try {
      if (existing) {
        const snap = await update({ id: existing.id, name, payload });
        setSavedSnapId(snap.id);
        setSnapName(snap.name);
        flash(`✓ Updated "${snap.name}"`);
      } else {
        const snap = await create({ calcKey: calc.key, name, payload });
        setSavedSnapId(snap.id);
        setSnapName(snap.name);
        flash(`✓ Saved as "${snap.name}"`);
      }
    } catch (e) {
      flash(`Save failed: ${(e as Error).message}`);
    }
  };

  const resetCalc = () => {
    if (!calcModule) return;
    setLiveState({ ...calcModule.initial });
    setSavedSnapId(null);
    setSnapName("untitled snapshot");
    flash("↻ Reset to defaults");
  };

  const copyAsText = async () => {
    if (!calcModule?.copyText) return;
    const text = calcModule.copyText(liveState);
    try {
      await navigator.clipboard.writeText(text);
      flash(`⧉ Copied: ${text}`);
    } catch {
      flash("Couldn't access clipboard — try selecting text manually");
    }
  };

  const handleDock = (k: DockKey) => {
    if (k === "snapshot") { saveSnap(); return; }
    if (k === "history")  { setModal((m) => m === "history" ? null : "history"); return; }
    if (k === "compare")  {
      if (!canCompare) return;
      setCompareMode((v) => !v);
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
      {/* ── Compare mode: card grid + Analyze ── */}
      {compareMode ? (
        <CompareGrid
          snaps={snaps}
          onExit={() => setCompareMode(false)}
          onRestore={(snap) => {
            setSelectedCalc(snap.calcKey);
            setLiveState({ ...(CALC_MODULES[snap.calcKey]?.initial ?? {}), ...snap.payload });
            setSnapName(snap.name);
            setSavedSnapId(snap.id);
            setCompareMode(false);
            flash(`⤺ Loaded "${snap.name}"`);
          }}
          onDelete={(id) => remove(id)}
        />
      ) : (
        <>
          {selectedCalc && calc ? (
            <div className="hf-calc-stage">
              <div className="hf-calc-stack">
                <CalcTabs current={calc.key} onPick={pickCalc} />
                {calcModule && sweepsForCalc(calc.key).length > 0 && (
                  <VariantsStrip
                    calcKey={calc.key}
                    calcModule={calcModule}
                    state={liveState}
                    onLoad={(next) => {
                      setLiveState(next);
                      flash("⤺ Variant loaded");
                    }}
                    sweeps={sweepsForCalc(calc.key)}
                  />
                )}
                <CalcShell
                crumbs={<>{categoryLabel(calc.category)} <span className="sep">›</span> {calc.name}</>}
                title={
                  renaming ? (
                    <RenameInput
                      defaultValue={snapName}
                      onCommit={(v) => { setSnapName(v.trim() || "untitled snapshot"); setRenaming(false); }}
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
                footer={
                  calcModule ? (
                    <div className="hf-calc-foot-inner">
                      <button className="hf-btn ghost" onClick={resetCalc}>↻ Reset</button>
                      <div className="foot-right">
                        {calcModule.copyText && (
                          <button className="hf-btn tinted" onClick={copyAsText}>⧉ Copy as text</button>
                        )}
                        <button className="hf-btn neon" onClick={saveSnap}>✓ Save calculation</button>
                      </div>
                    </div>
                  ) : null
                }
              >
                {calcModule ? (
                  <calcModule.component state={liveState} setState={setLiveState} />
                ) : (
                  <CalcEmpty label={`${calc.name.toUpperCase()} · content area`} />
                )}
              </CalcShell>
              </div>
            </div>
          ) : (
            <div className="hf-pick-stage">
              <PickHero
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
            onRestore={(snap) => {
              setSelectedCalc(snap.calcKey);
              setLiveState({ ...(CALC_MODULES[snap.calcKey]?.initial ?? {}), ...snap.payload });
              setSnapName(snap.name);
              setSavedSnapId(snap.id);
              setModal(null);
              flash(`⤺ Restored "${snap.name}"`);
            }}
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

      {toast && <div className="pdc-toast">{toast}</div>}
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
  onRestore,
}: {
  snaps: Snapshot[];
  currentCalcKey: string | null;
  filter: "All" | "This calculator" | "Tagged";
  onFilter: (v: "All" | "This calculator" | "Tagged") => void;
  selected: string | null;
  onSelect: (id: string | null) => void;
  onDelete: (id: string) => void;
  onRestore: (snap: Snapshot) => void;
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
              Open a calculator and hit <kbd>✓ Save calculation</kbd> in the footer.
            </div>
          </div>
        ) : (
          <div className="hf-hist-list">
            {filtered.map((s) => {
              const c = findCalc(s.calcKey);
              const mod = CALC_MODULES[s.calcKey];
              const disp = mod?.display ? mod.display(s.payload) : { value: "—", tone: "muted" as const };
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
                    <div className={`hf-snaprow-val ${disp.tone}`}>{disp.value}</div>
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
        ) : (() => {
          const mod  = CALC_MODULES[selectedSnap.calcKey];
          const disp = mod?.display ? mod.display(selectedSnap.payload) : { value: "—", tone: "muted" as const };
          const flds = mod?.payloadFields ? mod.payloadFields(selectedSnap.payload) : [];
          return (
            <>
              <div className="hf-preview-head">
                <div className="hf-eyebrow">Snapshot · {selectedSnap.name}</div>
                <div className="hf-preview-title">{selectedCalc?.name ?? selectedSnap.calcKey}</div>
                <div className="hf-preview-meta">
                  saved {relTime(selectedSnap.createdAt)} · by you · {new Date(selectedSnap.createdAt).toLocaleString()}
                </div>
              </div>

              <div className="hf-preview-stat">
                <div className={`hf-preview-num ${disp.tone === "muted" ? "muted" : ""}`}
                     style={disp.tone === "pos" ? { color: "var(--navi-positive)" }
                          : disp.tone === "neg" ? { color: "var(--navi-negative)" }
                          : undefined}>
                  {disp.value}
                </div>
                <div className="hf-preview-delta">
                  {selectedCalc?.name ?? "result"} · {categoryLabel(selectedCalc?.category ?? "pre-trade")}
                </div>
              </div>

              {flds.length > 0 && (
                <div className="hf-preview-grid">
                  {flds.map((f) => (
                    <Field key={f.label} label={f.label} value={f.value} mono={f.mono} />
                  ))}
                </div>
              )}

              <div className="hf-preview-actions">
                <button className="hf-btn neon" onClick={() => onRestore(selectedSnap)}>⤺ Restore into calc</button>
                <button className="hf-btn ghost" disabled>⇆ Compare with…</button>
                <button className="hf-btn ghost" disabled>↗ Share</button>
                <button className="hf-btn danger" onClick={() => onDelete(selectedSnap.id)}>✕ Delete</button>
              </div>
            </>
          );
        })()}
      </div>
    </div>
  );
}

// ── Compare grid ─────────────────────────────────────────────────
// Card view across saved snapshots grouped by calculator. Default sort is
// "newest first"; clicking Analyze sorts each group by the calc's own rank
// metric and surfaces the #1 with a "BEST" treatment. Click any card to
// restore that snapshot into the calc.
function CompareGrid({
  snaps,
  onExit,
  onRestore,
  onDelete,
}: {
  snaps: Snapshot[];
  onExit: () => void;
  onRestore: (snap: Snapshot) => void;
  onDelete: (id: string) => void;
}) {
  const [analyze, setAnalyze] = useState(false);

  const groups = useMemo(() => {
    // Group by calc key, preserve catalog order.
    const byCalc = new Map<string, Snapshot[]>();
    for (const s of snaps) {
      const arr = byCalc.get(s.calcKey) ?? [];
      arr.push(s);
      byCalc.set(s.calcKey, arr);
    }
    return CALCS
      .map((c) => ({ calc: c, items: byCalc.get(c.key) ?? [] }))
      .filter((g) => g.items.length > 0);
  }, [snaps]);

  const totalSnaps = snaps.length;
  const canAnalyze = totalSnaps >= 2;

  if (totalSnaps === 0) {
    return (
      <div className="math-compare-stage">
        <div className="math-compare-empty">
          <div style={{ marginBottom: 12, color: "var(--navi-fg2)", fontSize: 16 }}>
            No saved snapshots yet.
          </div>
          <div style={{ color: "var(--navi-fg4)", fontSize: 13, marginBottom: 18 }}>
            Save a calculation in any calc (✓ Save in the footer) to start comparing.
          </div>
          <button className="hf-btn ghost" onClick={onExit}>← Back</button>
        </div>
      </div>
    );
  }

  return (
    <div className="math-compare-stage">
      <div className="math-compare-head">
        <div>
          <div className="hf-eyebrow">Compare · {totalSnaps} saved</div>
          <div className="math-compare-title">
            {analyze ? "Ranked by best trade" : "All saved snapshots"}
          </div>
        </div>
        <div className="math-compare-actions">
          <button
            className={`hf-btn ${analyze ? "neon" : "ghost"}`}
            onClick={() => setAnalyze((v) => !v)}
            disabled={!canAnalyze}
            title={canAnalyze ? "Rank cards by each calc's best-trade metric" : "Save at least 2 snapshots to analyze"}
          >
            {analyze ? "✓ Analyzing" : "Analyze"}
          </button>
          <button className="hf-btn ghost" onClick={onExit}>✕ Exit</button>
        </div>
      </div>

      {groups.map((g) => (
        <CompareGroup
          key={g.calc.key}
          calc={g.calc}
          items={g.items}
          analyze={analyze}
          onRestore={onRestore}
          onDelete={onDelete}
        />
      ))}
    </div>
  );
}

function CompareGroup({
  calc,
  items,
  analyze,
  onRestore,
  onDelete,
}: {
  calc: CalcMeta;
  items: Snapshot[];
  analyze: boolean;
  onRestore: (snap: Snapshot) => void;
  onDelete: (id: string) => void;
}) {
  const mod = CALC_MODULES[calc.key];

  const ordered = useMemo(() => {
    // Score each snapshot, then either rank-sort (analyze) or time-sort.
    const scored = items.map((s) => {
      const r = mod?.rank?.(s.payload);
      return { snap: s, score: r?.score, label: r?.label };
    });
    if (analyze) {
      // Highest score first; snapshots with no rank (NaN/null) sink to the
      // bottom but stay in time order among themselves.
      return [...scored].sort((a, b) => {
        const aS = isFiniteScore(a.score);
        const bS = isFiniteScore(b.score);
        if (aS && bS) return (b.score as number) - (a.score as number);
        if (aS) return -1;
        if (bS) return 1;
        return b.snap.createdAt - a.snap.createdAt;
      });
    }
    return [...scored].sort((a, b) => b.snap.createdAt - a.snap.createdAt);
  }, [items, analyze, mod]);

  return (
    <div className="math-compare-group">
      <div className="math-compare-group-hd">
        <span className="hf-section">{calc.name}</span>
        <span className="math-compare-group-count">{items.length}</span>
        {analyze && ordered[0]?.label && (
          <span className="math-compare-group-axis">ranked by {ordered[0].label}</span>
        )}
      </div>
      <div className="math-compare-cards">
        {ordered.map(({ snap, score }, i) => {
          const disp = mod?.display ? mod.display(snap.payload) : { value: "—", tone: "muted" as const };
          const line = mod?.cardLine ? mod.cardLine(snap.payload) : "";
          const rankNum = analyze && isFiniteScore(score) ? i + 1 : null;
          const isBest = rankNum === 1;
          return (
            <button
              key={snap.id}
              className={`math-card ${isBest ? "best" : ""} ${rankNum != null ? "ranked" : ""}`}
              onClick={() => onRestore(snap)}
              title="Load this snapshot into the calculator"
            >
              {rankNum != null && (
                <span className={`math-card-rank ${isBest ? "best" : ""}`}>
                  {isBest ? "BEST" : `#${rankNum}`}
                </span>
              )}
              <span
                className="math-card-x"
                role="button"
                aria-label="Delete snapshot"
                onClick={(e) => { e.stopPropagation(); onDelete(snap.id); }}
              >
                ✕
              </span>
              <div className="math-card-hd">
                <div className="math-card-name">{snap.name}</div>
                <div className="math-card-time">{relTime(snap.createdAt)}</div>
              </div>
              <div className={`math-card-hero ${disp.tone}`}>{disp.value}</div>
              {analyze && isFiniteScore(score) && (
                <div className="math-card-metric">
                  {formatScore(calc.key, score as number)}
                </div>
              )}
              {line && <div className="math-card-line">{line}</div>}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function isFiniteScore(n: number | undefined): boolean {
  return typeof n === "number" && isFinite(n);
}

function formatScore(calcKey: string, score: number): string {
  // Put Cost rank negates the cost % so "higher score = cheaper". Flip the
  // sign back when displaying so the user sees the actual cost percentage.
  if (calcKey === "put-cost") return `${(-score).toFixed(2)}% cost`;
  // EI and IvC both rank by a yield %, positive = better.
  return `${score.toFixed(2)}%`;
}


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

// ── Sweep options per calc ───────────────────────────────────────
// Each calc declares which dimensions are interesting to fan out. Frequency
// sweeps on the put side pull real Polygon quotes per cadence's nearest
// expiry — without that, long-dated puts would be priced at the same
// premium as short-dated and the cost numbers would all collide.
function sweepsForCalc(calcKey: string): SweepOption[] {
  const putValues = PUT_FREQ_DEFS.map((f) => ({ id: f.id, label: f.label, calDays: f.calDays }));
  const callValues = FREQ_DEFS.map((f) => ({ id: f.id, label: f.label, calDays: f.calDays }));

  // Income vs Cost owns its own variant grid (5 horizon variants computed
  // inline) — the generic VariantsStrip + sweep flow doesn't apply.
  if (calcKey === "income-vs-cost") return [];

  if (calcKey === "put-cost") {
    return [
      {
        label: "Put frequency",
        stateKey: "frequency",
        values: putValues,
        quote: {
          type: "put",
          strikeFrom: { strikeKey: "strike" },
          premiumKey: "premium",
        },
      },
    ];
  }
  if (calcKey === "expected-income") {
    return [
      {
        label: "Call frequency",
        stateKey: "frequency",
        values: callValues,
        quote: {
          type: "call",
          strikeFrom: { spotKey: "price", distanceKey: "callDistance" },
          premiumKey: "premium",
        },
      },
    ];
  }
  return [];
}

// ── CalcTabs ─────────────────────────────────────────────────────
// Always-visible pill chips above the calc shell, one per calculator.
// Picking switches calcs in one click — no dropdown, no palette needed.
function CalcTabs({ current, onPick }: { current: string; onPick: (key: string) => void }) {
  return (
    <div className="math-tabs" role="tablist" aria-label="Switch calculator">
      {CALCS.map((c) => (
        <button
          key={c.key}
          role="tab"
          aria-selected={c.key === current}
          className={`math-tab${c.key === current ? " on" : ""}`}
          onClick={() => onPick(c.key)}
        >
          {c.name}
        </button>
      ))}
    </div>
  );
}
