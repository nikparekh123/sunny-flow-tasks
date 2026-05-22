/**
 * Math — hi-fi shell primitives.
 *
 * Ported from hifi-parts.jsx. These are the reusable bits every calculator
 * page composes:
 *   <SunnyfiShell>        — wraps everything (topbar + stage + dock)
 *   <Topbar> / <Brand>    — header chrome
 *   <Palette>             — Cmd-K search overlay
 *   <PickHero>            — landing empty state
 *   <CalcShell>           — the universal calc box (any real calc fills children)
 *   <CalcEmpty>           — placeholder body
 *   <SnapTag>             — "● unsaved" / "● <name>" pill in the calc header
 *   <Modal>               — used by History + Share screens
 *   <Chip> <Segmented> <Field> — small bits
 */
import {
  useEffect,
  useRef,
  type ReactNode,
  type CSSProperties,
  type ChangeEvent,
} from "react";

// ── Shell ──────────────────────────────────────────────────────────
export interface SunnyfiShellProps {
  children: ReactNode;
  route?: string;
  searchOpen?: boolean;
  onSearchClick?: () => void;
  onSearchClose?: () => void;
  dim?: boolean;
  dockActive?: DockKey | null;
  onDockClick?: (key: DockKey) => void;
  showSave?: boolean;
  showShare?: boolean;
  hideDock?: boolean;
  onSave?: () => void;
  onShare?: () => void;
  onBrandClick?: () => void;
  canSave?: boolean;
  canCompare?: boolean;
}

export type DockKey = "snapshot" | "history" | "compare" | "share";

export function SunnyfiShell({
  children,
  route = "Math",
  searchOpen = false,
  onSearchClick,
  onSearchClose,
  dim = false,
  dockActive = null,
  onDockClick,
  showSave = true,
  showShare = true,
  hideDock = false,
  onSave,
  onShare,
  onBrandClick,
  canSave = true,
  canCompare = false,
}: SunnyfiShellProps) {
  const cls = [
    "hf-shell",
    dim && "hf-shell-dim",
    searchOpen && "search-open",
  ].filter(Boolean).join(" ");
  return (
    <div className={cls}>
      <Topbar
        route={route}
        searchOpen={searchOpen}
        onSearchClick={onSearchClick}
        onSearchClose={onSearchClose}
        onSave={onSave}
        onShare={onShare}
        showSave={showSave}
        showShare={showShare}
        onBrandClick={onBrandClick}
        canSave={canSave}
      />
      <div className="hf-stage">{children}</div>
      {!hideDock && (
        <Dock active={dockActive} onClick={onDockClick} canCompare={canCompare} canSave={canSave} />
      )}
    </div>
  );
}

interface TopbarProps {
  route: string;
  searchOpen: boolean;
  onSearchClick?: () => void;
  onSearchClose?: () => void;
  onSave?: () => void;
  onShare?: () => void;
  showSave: boolean;
  showShare: boolean;
  onBrandClick?: () => void;
  canSave: boolean;
}

function Topbar({ route, searchOpen, onSearchClick, onSearchClose, onSave, onShare, showSave, showShare, onBrandClick, canSave }: TopbarProps) {
  return (
    <div className={`hf-top${searchOpen ? " search-open" : ""}`}>
      <Brand route={route} onClick={onBrandClick} />
      <span className="hf-top-spacer" aria-hidden />
      <div className="hf-actions">
        {searchOpen ? (
          <button className="hf-search-close" onClick={onSearchClose} aria-label="Close search">
            <span className="x">✕</span>
            <span className="esc">esc</span>
          </button>
        ) : (
          <>
            <button className="hf-search-trigger" onClick={onSearchClick} title="Find a calculator (⌘K)" aria-label="Find a calculator">
              <SpotlightGlass />
              <span className="kbd">⌘K</span>
            </button>
            {showShare && (
              <button className="hf-icon-btn" title="Share" aria-label="Share" onClick={onShare} disabled={!canSave}>
                <ShareGlyph />
              </button>
            )}
            {showSave && (
              <button className="hf-btn neon" onClick={onSave} disabled={!canSave}>
                ✓ Save
              </button>
            )}
          </>
        )}
      </div>
    </div>
  );
}

export function Brand({ route, onClick }: { route: string; onClick?: () => void }) {
  return (
    <button
      className="hf-brand"
      onClick={onClick}
      style={{ background: "transparent", border: 0, cursor: onClick ? "pointer" : "default", padding: 0 }}
    >
      <span className="brand-mark">sunnyfi<span className="hf-cursor" /></span>
      <span className="brand-slash">/</span>
      <span className="brand-route">{route}</span>
    </button>
  );
}

function SpotlightGlass() {
  return (
    <svg className="hf-glass" viewBox="0 0 16 16" width="16" height="16" aria-hidden>
      <circle cx="7" cy="7" r="4.5" fill="none" stroke="currentColor" strokeWidth="1.4" />
      <line x1="10.2" y1="10.2" x2="14" y2="14" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}

function ShareGlyph() {
  return (
    <svg viewBox="0 0 16 16" width="14" height="14" aria-hidden>
      <path d="M8 2 L8 11" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
      <path d="M4.5 5.5 L8 2 L11.5 5.5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" fill="none" />
      <path d="M3 9 L3 13 L13 13 L13 9" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" fill="none" />
    </svg>
  );
}

// ── Dock ──────────────────────────────────────────────────────────
interface DockProps {
  active: DockKey | null;
  onClick?: (k: DockKey) => void;
  canCompare: boolean;
  canSave: boolean;
}

function Dock({ active, onClick, canCompare, canSave }: DockProps) {
  const items: { id: DockKey; label: string; disabled?: boolean }[] = [
    { id: "snapshot", label: "+ Snapshot", disabled: !canSave },
    { id: "history",  label: "History" },
    { id: "compare",  label: "Compare",   disabled: !canCompare },
    { id: "share",    label: "↗ Share",   disabled: !canSave },
  ];
  return (
    <div className="hf-dock">
      {items.map((it) => (
        <button
          key={it.id}
          className={`hf-dock-btn ${active === it.id ? "active" : ""}`}
          onClick={() => onClick?.(it.id)}
          disabled={it.disabled}
        >
          {it.label}
        </button>
      ))}
    </div>
  );
}

// ── PickHero (resting / empty) ────────────────────────────────────
export function PickHero({
  available,
  open,
  popular,
  onPickPopular,
  onPressCmdK,
}: {
  available: number;
  open: number;
  popular: { key: string; name: string }[];
  onPickPopular: (key: string) => void;
  onPressCmdK?: () => void;
}) {
  return (
    <div className="hf-pick">
      <div className="hf-eyebrow">Calculators · {available} available · {open} open</div>
      <h1 className="hf-pick-headline">
        Pick a<br />calculator<span className="hf-pick-period">.</span>
      </h1>
      <div className="hf-pick-sub">
        Press <kbd>⌘K</kbd> · or click the bar above ↑
      </div>
      {popular.length > 0 && (
        <div className="hf-pick-rail">
          <div className="hf-section">Popular this week</div>
          <div className="hf-pick-pop">
            {popular.map((p, i) => (
              <span key={p.key} style={{ display: "inline-flex", alignItems: "center", gap: 14 }}>
                {i > 0 && <span className="pop-sep">·</span>}
                <button className="pop-item" onClick={() => onPickPopular(p.key)}>{p.name}</button>
              </span>
            ))}
          </div>
        </div>
      )}
      {/* Hidden Cmd-K helper so this prop is meaningful even when not visibly bound */}
      <span style={{ display: "none" }} aria-hidden onClick={onPressCmdK} />
    </div>
  );
}

// ── CalcShell ─────────────────────────────────────────────────────
export interface CalcShellProps {
  crumbs?: ReactNode;
  title?: ReactNode;
  snapTag?: ReactNode;
  actions?: ReactNode;
  footer?: ReactNode;
  children?: ReactNode;
  style?: CSSProperties;
  accent?: boolean;
  tint?: boolean;
  dim?: boolean;
}

export function CalcShell({ crumbs, title, snapTag, actions, footer, children, style, accent, tint, dim }: CalcShellProps) {
  const cls = ["hf-calcbox", tint && "tinted", accent && "accent", dim && "dim"].filter(Boolean).join(" ");
  return (
    <div className={cls} style={style}>
      {(crumbs || title || snapTag || actions) && (
        <div className="hf-calc-head">
          <div className="left">
            {crumbs && <div className="hf-eyebrow">{crumbs}</div>}
            {title && <div className="hf-calc-title">{title}</div>}
          </div>
          <div className="right">
            {snapTag}
            {actions}
          </div>
        </div>
      )}
      <div className="hf-calc-body">{children ?? <CalcEmpty />}</div>
      {footer && <div className="hf-calc-foot">{footer}</div>}
    </div>
  );
}

export function CalcEmpty({ label = "Calculator · content area" }: { label?: string }) {
  return (
    <div className="hf-calc-empty">
      <div className="hf-section">{label}</div>
      <div className="hf-empty-grid">
        {Array.from({ length: 8 }).map((_, i) => <div key={i} className="hf-grid-cell" />)}
      </div>
      <div className="hf-empty-foot">— body unique to each calculator —</div>
    </div>
  );
}

// ── SnapTag ───────────────────────────────────────────────────────
export function SnapTag({ tone = "neutral", children }: { tone?: "neutral" | "pos" | "warn"; children: ReactNode }) {
  return <span className={`hf-snaptag ${tone}`}>{children}</span>;
}

// ── Modal ─────────────────────────────────────────────────────────
export interface ModalProps {
  title: ReactNode;
  subtitle?: ReactNode;
  eyebrow?: ReactNode;
  width?: number;
  children: ReactNode;
  footer?: ReactNode;
  onClose?: () => void;
}

export function Modal({ title, subtitle, eyebrow, width = 720, children, footer, onClose }: ModalProps) {
  // Esc / backdrop click close
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose?.(); };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div className="hf-modal-scrim" onClick={onClose}>
      <div
        className="hf-modal"
        style={{ width }}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
      >
        <div className="hf-modal-head">
          <div className="left">
            {eyebrow && <div className="hf-eyebrow">{eyebrow}</div>}
            <div className="hf-modal-title">{title}</div>
            {subtitle && <div className="hf-modal-sub">{subtitle}</div>}
          </div>
          <button className="hf-modal-x" aria-label="close" onClick={onClose}>✕</button>
        </div>
        <div className="hf-modal-body">{children}</div>
        {footer && <div className="hf-modal-foot">{footer}</div>}
      </div>
    </div>
  );
}

// ── Palette ───────────────────────────────────────────────────────
export function Palette({ children, searchBar }: { children: ReactNode; searchBar: ReactNode }) {
  return (
    <div className="hf-palette">
      <div className="hf-palette-inner">
        {searchBar}
        <div className="hf-palette-pad">{children}</div>
        <div className="hf-palette-foot">
          <span><kbd>↑</kbd><kbd>↓</kbd> move</span>
          <span><kbd>↵</kbd> open</span>
          <span><kbd>esc</kbd> close</span>
        </div>
      </div>
    </div>
  );
}

export function OverlaySearch({
  value = "",
  onChange,
  autoFocus = true,
}: {
  value?: string;
  onChange?: (v: string) => void;
  autoFocus?: boolean;
}) {
  const ref = useRef<HTMLInputElement | null>(null);
  useEffect(() => {
    if (autoFocus && ref.current) {
      const id = requestAnimationFrame(() => ref.current?.focus());
      return () => cancelAnimationFrame(id);
    }
  }, [autoFocus]);
  return (
    <div className="hf-overlay-search">
      <span className="hf-overlay-glass"><SpotlightGlass /></span>
      <input
        ref={ref}
        className="hf-overlay-input"
        type="text"
        placeholder="Find a calculator…"
        value={value}
        onChange={(e: ChangeEvent<HTMLInputElement>) => onChange?.(e.target.value)}
        spellCheck={false}
        autoComplete="off"
        aria-label="Find a calculator"
      />
      <span className="hf-overlay-kbd">⌘K</span>
    </div>
  );
}

export function CatHead({ children, count }: { children: ReactNode; count?: number }) {
  return (
    <div className="hf-cathead">
      <span className="hf-section">{children}</span>
      {count != null && <span className="hf-cathead-count">{count}</span>}
    </div>
  );
}

export function CalcOption({
  name,
  hint,
  active = false,
  match,
  kbd,
  meta,
  onClick,
}: {
  name: string;
  hint?: string;
  active?: boolean;
  match?: string;
  kbd?: string;
  meta?: string;
  onClick?: () => void;
}) {
  return (
    <button className={`hf-calcopt ${active ? "active" : ""}`} onClick={onClick}>
      <div className="hf-calcopt-name">
        {match ? <Highlight text={name} match={match} /> : name}
        {meta && <span className="hf-calcopt-meta"> · {meta}</span>}
      </div>
      <div className="hf-calcopt-right">
        {hint && <span className="hf-calcopt-hint">{hint}</span>}
        {kbd && <kbd>{kbd}</kbd>}
      </div>
    </button>
  );
}

export function Highlight({ text, match }: { text: string; match: string }) {
  const i = text.toLowerCase().indexOf(match.toLowerCase());
  if (i < 0) return <>{text}</>;
  return (
    <>
      {text.slice(0, i)}
      <mark>{text.slice(i, i + match.length)}</mark>
      {text.slice(i + match.length)}
    </>
  );
}

// ── Small bits ────────────────────────────────────────────────────
export function Chip({ tone = "neutral", children, active = false }: { tone?: "neutral" | "neon" | "warn"; children: ReactNode; active?: boolean }) {
  return <span className={`hf-chip ${tone} ${active ? "active" : ""}`}>{children}</span>;
}

export function Segmented<T extends string>({
  options,
  value,
  onChange,
}: {
  options: T[];
  value: T;
  onChange?: (v: T) => void;
}) {
  return (
    <div className="hf-seg">
      {options.map((o) => (
        <button
          key={o}
          className={`hf-seg-opt ${o === value ? "active" : ""}`}
          onClick={() => onChange?.(o)}
        >
          {o}
        </button>
      ))}
    </div>
  );
}

export function Field({ label, value, mono = false, hl = false, sub }: { label: string; value: ReactNode; mono?: boolean; hl?: boolean; sub?: ReactNode }) {
  return (
    <div className="hf-field">
      <div className="hf-label">{label}</div>
      <div className={`hf-field-val ${mono ? "mono" : ""} ${hl ? "hl" : ""}`}>{value}</div>
      {sub && <div className="hf-field-sub">{sub}</div>}
    </div>
  );
}
