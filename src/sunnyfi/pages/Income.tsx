/**
 * Income — Sunnyfi premium-income view.
 *
 * Tesla-energy-style diverging chart (Collected ↑ = Calls + Puts + Shares
 * stacked; Bought-back ↓ = buy-to-close debits), Day/Week/Month/Quarter/Year
 * switcher, and a weighted-recent-trend projection. Ported from the Claude
 * design handoff and wired to live option_trades + share_sells.
 *
 * The body (IncomeScreen) owns its own `.dash` shell + BrandBar; this wrapper
 * just pulls in the stylesheets and the auth gate is applied at the route.
 */
import "./dashboard.css";
import "./income-v2.css";
import { IncomeScreen } from "@/sunnyfi/dashboard/incomeChart";

export default function Income() {
  return <IncomeScreen />;
}
