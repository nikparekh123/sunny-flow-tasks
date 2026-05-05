/**
 * Placeholder for the Snowball DCF/valuation dashboard. Full build (port of
 * the design_handoff_snowball_dashboard hi-fi prototype) ships in a follow-up
 * commit. This page exists now so the dashboard tile lands on a real route
 * instead of 404'ing.
 */
import { useNavigate } from "react-router-dom";
import "@/sunnyfi/research.css";

const DASHBOARD_URL = "https://www.sunnyfi.co/dashboard";

export default function Snowball() {
  const navigate = useNavigate();

  return (
    <div>
      <header className="np-top">
        <div className="np-brand-row">
          <a className="np-brand" href={DASHBOARD_URL} title="Back to dashboard">
            Sunnyfi<span className="cursor" />
          </a>
          <span className="np-crumb-sep">/</span>
          <span className="np-crumb">SNOWBALL</span>
        </div>
        <div className="np-actions">
          <button className="np-btn ghost" onClick={() => navigate(-1)}>
            ← Back
          </button>
        </div>
      </header>

      <main
        style={{
          maxWidth: 720,
          margin: "0 auto",
          padding: "120px 32px",
          textAlign: "center",
        }}
      >
        <div
          style={{
            fontSize: 11,
            fontWeight: 500,
            letterSpacing: "2px",
            textTransform: "uppercase",
            color: "var(--navi-fg4, #468278)",
            marginBottom: 16,
          }}
        >
          Coming soon
        </div>
        <h1
          style={{
            fontSize: 64,
            fontWeight: 300,
            letterSpacing: "-2px",
            lineHeight: 1.05,
            color: "var(--navi-neon, #d2e632)",
            margin: "0 0 24px",
          }}
        >
          Snowball
        </h1>
        <p
          style={{
            fontSize: 16,
            lineHeight: 1.6,
            color: "var(--navi-fg2, #a8c4c0)",
            maxWidth: 560,
            margin: "0 auto",
          }}
        >
          DCF + P/E + EV/EBITDA valuation across the universe. Ranked by
          margin of safety, watchlist always in view.
        </p>
        <p
          style={{
            fontSize: 12,
            fontFamily: "var(--navi-font-mono, monospace)",
            color: "var(--navi-fg4, #468278)",
            marginTop: 48,
            letterSpacing: 0.5,
          }}
        >
          Hi-fi build in progress.
        </p>
      </main>
    </div>
  );
}
