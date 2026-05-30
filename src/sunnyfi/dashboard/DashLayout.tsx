/**
 * DashLayout — the persistent app shell for every in-app page.
 *
 * Renders the `.dash` / `.dash-inner` wrapper and the BrandBar ONCE, with an
 * <Outlet/> for the routed page content. Because the layout element stays
 * mounted across child-route navigations, the header never unmounts/reloads —
 * only the content below the Outlet swaps. routeLabel + active highlight are
 * derived from the current path.
 *
 * Pages mounted under this layout render ONLY their content (no .dash shell,
 * no BrandBar of their own).
 */
import { Outlet, useLocation, useNavigate } from "react-router-dom";
import { BrandBar } from "./blocks";
import { useNow, fmtBrandDate } from "./time";
import "@/sunnyfi/pages/dashboard.css";

type Active = "positions" | "income" | "strategy" | "math" | "portfolio";
const ROUTE_META: Record<string, { label: string; active?: Active }> = {
  "/dashboard": { label: "Morning brief" },
  "/income": { label: "Income", active: "income" },
  "/portfolio": { label: "Portfolio", active: "portfolio" },
  "/new-strategy": { label: "New Strategy", active: "strategy" },
  "/positions": { label: "Positions", active: "positions" },
  "/math": { label: "Math", active: "math" },
};

export function DashLayout() {
  const { pathname } = useLocation();
  const navigate = useNavigate();
  const dateLabel = fmtBrandDate(useNow(60_000));
  const meta = ROUTE_META[pathname] ?? { label: "Morning brief" };
  // Portfolio's master table needs ~1420px just for its column grid; the
  // standard 1440px max-width with 56px L/R padding squeezes it. Apply a
  // wider shell on /portfolio so the table fits without horizontal scroll.
  const wide = pathname === "/portfolio";
  return (
    <div className={"dash" + (wide ? " dash-wide" : "")}>
      <div className="dash-inner">
        <BrandBar
          routeLabel={meta.label}
          active={meta.active}
          dateLabel={dateLabel}
          onLogo={() => navigate("/dashboard")}
          onPortfolio={() => navigate("/portfolio")}
          onPositions={() => navigate("/positions")}
          onIncome={() => navigate("/income")}
          onStrategy={() => navigate("/new-strategy")}
          onMath={() => navigate("/math")}
        />
        <Outlet />
      </div>
    </div>
  );
}
