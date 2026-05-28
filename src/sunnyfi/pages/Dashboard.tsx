/**
 * Dashboard — Sunnyfi morning brief.
 *
 * Renders the Cockpit layout from the Claude design handoff. This shell
 * file owns the auth + routing concerns (signed-in user fetch, log-out,
 * navigation handlers); the visual blocks live under
 * src/sunnyfi/dashboard/.
 *
 * Subsequent commits (CD-4 … CD-9) replace the blocks' hardcoded sample
 * data with live queries. The visual lands first so the shape is fixed.
 */
import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { signOut } from "@/sunnyfi/lib/auth";
import { CockpitLayout } from "@/sunnyfi/dashboard/CockpitLayout";
import "./dashboard.css";

export default function Dashboard() {
  const navigate = useNavigate();

  // Esc → log out, ⌘1..3 → tool nav. Same shortcuts the old dashboard
  // exposed; the ToolsRail handlers do the same routes.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        (async () => {
          await signOut();
          navigate("/", { replace: true });
        })();
        return;
      }
      if (!(e.metaKey || e.ctrlKey)) return;
      if (e.key === "1") { e.preventDefault(); window.location.href = "https://positions.sunnyfi.co"; }
      else if (e.key === "2") { e.preventDefault(); navigate("/new-strategy"); }
      else if (e.key === "3") { e.preventDefault(); navigate("/math"); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [navigate]);

  return (
    <CockpitLayout
      formalGreeting={true}
      heroSize={120}
      todayHighlight="neon"
      areaFill={true}
      showNews={true}
      onPositions={() => { window.location.href = "https://positions.sunnyfi.co"; }}
      onStrategy={() => navigate("/new-strategy")}
      onMath={() => navigate("/math")}
    />
  );
}
