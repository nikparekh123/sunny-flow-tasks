/**
 * Math — empty shell.
 *
 * Cleared so the new design (provided separately) can be dropped in fresh
 * without any leftover Calculators markup mixing in.
 */
import "../../positions/positions.css";

const DASHBOARD_URL = "https://www.sunnyfi.co/dashboard";

export default function MathPage() {
  return (
    <div className="np-app">
      <header className="np-top">
        <div className="np-brand-row">
          <a className="np-brand" href={DASHBOARD_URL} title="Back to dashboard">
            Sunnyfi<span className="cursor" />
          </a>
          <span className="np-crumb-sep">/</span>
          <span className="np-crumb">Math</span>
        </div>
      </header>
    </div>
  );
}
