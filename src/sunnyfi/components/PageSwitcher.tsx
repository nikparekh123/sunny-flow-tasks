/**
 * PageSwitcher — drop-in replacement for the static route name in a brand
 * wordmark. Click → menu listing the discoverable Sunnyfi pages (the live
 * dashboard tiles). Lives in two contexts:
 *
 *   - Math (`sunnyfi.co/math`)     — under .hf-shell, lowercase brand
 *   - Positions (`positions.sunnyfi.co`) — under .np-app, UPPERCASE brand
 *
 * The component's own font/color inherit from its parent so each surface
 * styles it naturally; only the dropdown panel has its own surface styling.
 */
import { useEffect, useRef, useState } from "react";
import "./PageSwitcher.css";

export interface PageItem {
  key: string;
  label: string;
  /** Full URL — supports cross-subdomain links (positions.sunnyfi.co). */
  href: string;
}

/**
 * The pages that appear in the switcher. Mirrors the live Dashboard tiles —
 * adding a tile back to /dashboard's TOOLS list should also add it here.
 */
export const SWITCHER_PAGES: PageItem[] = [
  { key: "dashboard", label: "Dashboard", href: "https://www.sunnyfi.co/dashboard" },
  { key: "positions", label: "Positions", href: "https://positions.sunnyfi.co" },
  { key: "math",      label: "Math",      href: "https://www.sunnyfi.co/math" },
];

export function PageSwitcher({
  current,
  variant = "hf",
}: {
  /** Page key for the active highlight; if no match, just shows the chevron. */
  current: string;
  /** "hf" — hifi-shell pages (lowercase brand). "np" — positions (UPPERCASE). */
  variant?: "hf" | "np";
}) {
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement | null>(null);

  // Close on outside click or Esc.
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const currentItem = SWITCHER_PAGES.find((p) => p.key === current);
  const currentLabel = currentItem?.label ?? "—";

  return (
    <div className={`ps-wrap ps-${variant}`} ref={wrapRef}>
      <button
        type="button"
        className="ps-trigger"
        onClick={() => setOpen((v) => !v)}
        aria-haspopup="menu"
        aria-expanded={open}
        title="Switch pages"
      >
        <span className="ps-current">{currentLabel}</span>
        <svg className="ps-chev" width="10" height="10" viewBox="0 0 10 10" aria-hidden>
          <path d="M2 4l3 3 3-3" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open && (
        <div className="ps-menu" role="menu">
          {SWITCHER_PAGES.map((p) => {
            const active = p.key === current;
            return (
              <a
                key={p.key}
                role="menuitem"
                className={`ps-item ${active ? "active" : ""}`}
                href={p.href}
                onClick={() => setOpen(false)}
              >
                <span className="ps-item-label">{p.label}</span>
                {active && <span className="ps-item-tag">current</span>}
              </a>
            );
          })}
        </div>
      )}
    </div>
  );
}
