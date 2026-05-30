/**
 * Portfolio — master positions page (source of truth).
 *
 * **PD-0**: design-only scaffold with hardcoded sample data. Lives
 * under DashLayout so it inherits the persistent brand bar + nav.
 * PD-1+2 wire it to live Massive.com data via a new persistence layer.
 */
import "./dashboard.css";
import { MasterPositions } from "@/portfolio/MasterPositions";

export default function Portfolio() {
  return <MasterPositions defaultView="table" />;
}
