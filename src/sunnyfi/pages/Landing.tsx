import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { signInWithCode, getCurrentSession } from "@/sunnyfi/lib/auth";

function useNow() {
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);
  return now;
}

function formatClock(date: Date, offsetHours: number) {
  const utcMs = date.getTime() + date.getTimezoneOffset() * 60_000;
  const local = new Date(utcMs + offsetHours * 3_600_000);
  const h = local.getHours().toString().padStart(2, "0");
  const m = local.getMinutes().toString().padStart(2, "0");
  return `${h}:${m}`;
}

type Stage = "idle" | "signing" | "error";

export default function Landing() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [code, setCode] = useState("");
  const [stage, setStage] = useState<Stage>("idle");
  const [msg, setMsg] = useState<string | null>(() => {
    if (params.get("denied") === "1") return "Wrong code. Ask Niket for the current one.";
    return null;
  });
  const now = useNow();
  const nyc = formatClock(now, -4);

  // Already signed in? Skip straight to the dashboard.
  useEffect(() => {
    getCurrentSession().then((s) => {
      if (s?.user) navigate("/dashboard", { replace: true });
    });
  }, [navigate]);

  const trimmed = code.replace(/\s+/g, "");
  const validShape = /^\d{10}$/.test(trimmed);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (stage === "signing") return;
    setStage("signing");
    setMsg(null);
    const res = await signInWithCode(trimmed);
    if (res.ok) {
      navigate("/dashboard", { replace: true });
      return;
    }
    setStage("error");
    if (res.reason === "invalid_code") setMsg("That should be a 10-digit number.");
    else if (res.reason === "wrong_code") setMsg("Wrong code — try again.");
    else if (res.reason === "network") setMsg("Couldn't reach the server.");
    else setMsg(res.message || "Something went wrong.");
  };

  return (
    <div className="app">
      <div className="landing">
        <div className="landing-top">
          <div className="wordmark">
            Sunnyfi<span className="cursor" />
          </div>
          <div className="landing-meta">
            <span className="mono">{nyc}</span>
            <span className="meta-sep">·</span>
            <span>NYC</span>
          </div>
        </div>

        <div className="landing-hero">
          <div className="welcome-big">
            Welcome to<br />
            Sunny Wealth<br />
            Management.
          </div>
        </div>

        <div className="landing-foot">
          <form className="signin" onSubmit={onSubmit}>
            <label className="signin-label">Sign in</label>
            <div className="signin-row">
              <div
                className="signin-input-wrap"
                data-state={validShape ? "yes" : "unknown"}
              >
                <input
                  className="signin-input"
                  type="text"
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  pattern="[0-9]*"
                  maxLength={10}
                  placeholder="10-digit code"
                  value={code}
                  onChange={(e) => setCode(e.target.value.replace(/[^\d]/g, ""))}
                  disabled={stage === "signing"}
                  required
                  style={{ letterSpacing: "0.3em" }}
                />
                <span className="signin-mark" aria-hidden>
                  {validShape && "✓"}
                </span>
              </div>
              <button
                className="signin-btn"
                type="submit"
                disabled={stage === "signing" || !validShape}
              >
                {stage === "signing" ? "Signing in…" : "Sign in ↵"}
              </button>
            </div>
            <div className="signin-hint">
              {msg ? msg : "Enter the 10-digit access code."}
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
