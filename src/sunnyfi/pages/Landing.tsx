import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { sendMagicLink, getCurrentSession, checkMemberEmail } from "@/sunnyfi/lib/auth";

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

type Stage = "idle" | "sending" | "sent" | "error";
type Recognized = "unknown" | "checking" | "yes" | "no";

export default function Landing() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [email, setEmail] = useState("");
  const [recognized, setRecognized] = useState<Recognized>("unknown");
  const [stage, setStage] = useState<Stage>("idle");
  const [msg, setMsg] = useState<string | null>(() => {
    if (params.get("denied") === "1") return "That email isn't on the allowlist. Ask Niket for access.";
    if (params.get("expired") === "1") return "That link expired. Send yourself a new one.";
    return null;
  });
  const now = useNow();
  const nyc = formatClock(now, -4);

  // Already signed in? Skip straight to the dashboard.
  useEffect(() => {
    getCurrentSession().then((s) => { if (s?.user) navigate("/dashboard", { replace: true }); });
  }, [navigate]);

  // Debounced allowlist probe as the user types.
  useEffect(() => {
    const trimmed = email.trim().toLowerCase();
    if (!trimmed) { setRecognized("unknown"); return; }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) { setRecognized("unknown"); return; }
    setRecognized("checking");
    let cancelled = false;
    const t = window.setTimeout(async () => {
      const ok = await checkMemberEmail(trimmed);
      if (!cancelled) setRecognized(ok ? "yes" : "no");
    }, 350);
    return () => { cancelled = true; window.clearTimeout(t); };
  }, [email]);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (stage === "sending") return;
    setStage("sending");
    setMsg(null);
    const res = await sendMagicLink(email);
    if (res.ok) {
      setStage("sent");
      setMsg(`Check ${email.trim().toLowerCase()} — we sent you a sign-in link.`);
      return;
    }
    setStage("error");
    if (res.reason === "invalid_email") setMsg("That doesn't look like a valid email.");
    else if (res.reason === "rate_limited") setMsg("Too many requests. Wait a minute and try again.");
    else if (res.reason === "network") setMsg("Couldn't reach the server. Check your connection.");
    else setMsg(res.message || "Something went wrong. Try again.");
  };

  return (
    <div className="app">
      <div className="landing">
        <div className="landing-top">
          <div className="wordmark">Sunnyfi<span className="cursor" /></div>
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
              <div className="signin-input-wrap" data-state={recognized}>
                <input
                  className="signin-input"
                  type="email"
                  inputMode="email"
                  autoComplete="email"
                  placeholder="you@sunnyfi.co"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  disabled={stage === "sending" || stage === "sent"}
                  required
                />
                <span className="signin-mark" aria-hidden>
                  {recognized === "yes" && "✓"}
                  {recognized === "no"  && "✕"}
                </span>
              </div>
              <button
                className="signin-btn"
                type="submit"
                disabled={
                  stage === "sending" || stage === "sent" ||
                  !email.trim() || recognized !== "yes"
                }
              >
                {stage === "sending" ? "Sending…" : stage === "sent" ? "Sent ↵" : "Send link ↵"}
              </button>
            </div>
            <div className="signin-hint">
              {msg
                ? msg
                : recognized === "no"
                  ? "That email isn't on the allowlist. Ask Niket for access."
                  : recognized === "checking"
                    ? "Checking…"
                    : recognized === "yes"
                      ? "Recognized — send yourself a sign-in link."
                      : "We'll email you a one-tap sign-in link."}
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
