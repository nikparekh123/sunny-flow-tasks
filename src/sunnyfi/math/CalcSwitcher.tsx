/**
 * CalcSwitcher — turns the calc name in the CalcShell header into a one-click
 * dropdown for switching between calculators without leaving the canvas.
 *
 * Visually shares its CSS with PageSwitcher (ps-* classes) so the dropdown
 * panel matches that pattern; the trigger inherits font/size/weight from the
 * surrounding <CalcShell> title, so the calc name still reads as the title.
 */
import { useEffect, useRef, useState } from "react";
import { CALCS } from "./data";
import "../components/PageSwitcher.css";

export function CalcSwitcher({
  current,
  onPick,
}: {
  current: string;
  onPick: (key: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement | null>(null);

  // Close on outside click / Esc.
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

  const currentCalc = CALCS.find((c) => c.key === current);
  return (
    <div className={`ps-wrap ps-hf${open ? " open" : ""}`} ref={wrapRef}>
      <button
        type="button"
        className="ps-trigger"
        onClick={() => setOpen((v) => !v)}
        aria-haspopup="menu"
        aria-expanded={open}
        title="Switch calculator"
      >
        <span className="ps-current">{currentCalc?.name ?? "—"}</span>
        <svg className="ps-chev" width="10" height="10" viewBox="0 0 10 10" aria-hidden>
          <path d="M2 4l3 3 3-3" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open && (
        <div className="ps-menu" role="menu">
          {CALCS.map((c) => {
            const active = c.key === current;
            return (
              <button
                key={c.key}
                role="menuitem"
                className={`ps-item ${active ? "active" : ""}`}
                onClick={() => { setOpen(false); onPick(c.key); }}
                style={{ background: "transparent", border: 0, font: "inherit", cursor: "pointer", textAlign: "left" }}
              >
                <span className="ps-item-label">{c.name}</span>
                {active
                  ? <span className="ps-item-tag">current</span>
                  : <span style={{ fontFamily: "var(--navi-font-mono)", fontSize: 10, color: "var(--navi-fg4)" }}>{c.hint}</span>}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
