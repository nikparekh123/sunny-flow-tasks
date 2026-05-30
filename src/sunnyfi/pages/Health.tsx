/**
 * Health — diagnostic route. URL-only (no nav link).
 *
 * The body owns its own .dash shell so we get the standard page
 * background + the brand bar through DashLayout.
 */
import "./dashboard.css";
import { HealthPage } from "@/health/HealthPage";

export default function Health() {
  return <HealthPage />;
}
