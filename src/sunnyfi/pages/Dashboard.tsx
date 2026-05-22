import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { signOut, getDisplayName } from "@/sunnyfi/lib/auth";
import { supabase } from "@/integrations/supabase/client";

type Status = "live" | "soon";
interface Tool {
  key: "tasks" | "research" | "positions" | "snowball" | "strategy" | "calendar";
  name: string;
  desc: string;
  status: Status;
  hotkey: string;
  href?: string;
  internal?: string; // react-router path
}

const TOOLS: Tool[] = [
  { key: "tasks",    name: "Tasks",        desc: "Daily workflow",   status: "live", hotkey: "1", href: "https://todos.sunnyfi.co" },
  { key: "positions", name: "Positions",   desc: "Holdings & P&L",   status: "live", hotkey: "2", href: "https://positions.sunnyfi.co" },
  { key: "calendar", name: "Calendar",     desc: "Events",           status: "soon", hotkey: "3" },
];

const ICON_STYLE = { fill: "none", stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
function ToolIcon({ name }: { name: Tool["key"] }) {
  const g = (inner: React.ReactNode) => <g {...ICON_STYLE}>{inner}</g>;
  const map: Record<Tool["key"], React.ReactNode> = {
    tasks:    g(<><rect x="3" y="4" width="18" height="16" rx="1" /><path d="M7 9h10M7 13h7M7 17h4" /></>),
    research: g(<><path d="M4 4h12a4 4 0 0 1 4 4v12H8a4 4 0 0 1-4-4V4z" /><path d="M8 9h8M8 13h8M8 17h5" /></>),
    positions: g(<><rect x="3" y="3" width="8" height="13" /><rect x="13" y="3" width="8" height="8" /><rect x="3" y="18" width="8" height="3" /><rect x="13" y="13" width="8" height="8" /></>),
    // Snowball icon: stacked spheres growing — value compounding metaphor.
    snowball: g(<><circle cx="12" cy="17" r="4" /><circle cx="12" cy="9" r="2.5" /><circle cx="12" cy="4" r="1.4" /></>),
    // Strategy icon: three stacked buckets — Income / Investment / Yield allocation.
    strategy: g(<><rect x="3" y="4" width="18" height="4" rx="0.5" /><rect x="3" y="10" width="18" height="4" rx="0.5" /><rect x="3" y="16" width="18" height="4" rx="0.5" /></>),
    calendar: g(<><rect x="3" y="5" width="18" height="16" rx="1" /><path d="M3 10h18M8 3v4M16 3v4" /></>),
  };
  return <svg width={22} height={22} viewBox="0 0 24 24" aria-hidden>{map[name]}</svg>;
}

function useNow() {
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);
  return now;
}

function clockAt(date: Date, offsetHours: number) {
  const utcMs = date.getTime() + date.getTimezoneOffset() * 60_000;
  const local = new Date(utcMs + offsetHours * 3_600_000);
  const h = local.getHours().toString().padStart(2, "0");
  const m = local.getMinutes().toString().padStart(2, "0");
  const s = local.getSeconds().toString().padStart(2, "0");
  return { hm: `${h}:${m}`, s };
}

function greeting(hour: number) {
  if (hour < 5) return "Late night";
  if (hour < 12) return "Morning";
  if (hour < 17) return "Afternoon";
  if (hour < 21) return "Evening";
  return "Late night";
}

function formatDate(d: Date) {
  const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${days[d.getDay()]} · ${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}

interface ToastState { msg: string; kind: "live" | "soon" }

export default function Dashboard() {
  const navigate = useNavigate();
  const now = useNow();
  const [toast, setToast] = useState<ToastState | null>(null);
  const [fading, setFading] = useState(false);
  const [name, setName] = useState<string>("there");

  useEffect(() => {
    let cancelled = false;
    supabase.auth.getUser().then(async ({ data }) => {
      if (cancelled || !data.user) return;
      const n = await getDisplayName(data.user);
      if (!cancelled) setName(n);
    });
    return () => { cancelled = true; };
  }, []);

  const clocks = [
    { city: "NYC", tz: "ET",  offset: -4 },
    { city: "LIS", tz: "WET", offset:  1 },
    { city: "TUN", tz: "CET", offset:  1 },
    { city: "BOM", tz: "IST", offset:  5.5 },
  ];

  const onOpen = (t: Tool) => {
    setToast({ msg: t.status === "live" ? `Opening ${t.name}…` : `${t.name} — coming soon`, kind: t.status });
    window.clearTimeout((window as unknown as { __sunnyfiToastT?: number }).__sunnyfiToastT);
    (window as unknown as { __sunnyfiToastT?: number }).__sunnyfiToastT = window.setTimeout(() => setToast(null), 1800);

    if (t.status !== "live") return;
    if (t.internal) { navigate(t.internal); return; }
    // External tools (Tasks on todos.sunnyfi.co, Positions on
    // positions.sunnyfi.co) live on different subdomains — same-tab nav
    // does a full document load to that origin.
    if (t.href)     { window.location.href = t.href; return; }
  };

  const onLogout = () => {
    setFading(true);
    setTimeout(async () => {
      await signOut();
      navigate("/", { replace: true });
    }, 400);
  };

  // Hotkeys: Cmd/Ctrl+1..6, Esc logout
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") { onLogout(); return; }
      if (!(e.metaKey || e.ctrlKey)) return;
      const idx = parseInt(e.key, 10);
      if (isNaN(idx) || idx < 1 || idx > 6) return;
      e.preventDefault();
      const t = TOOLS[idx - 1];
      if (t) onOpen(t);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className={"app" + (fading ? " fading" : "")}>
      <div className="dash">
        <div className="dash-top">
          <div className="dash-wordmark">Sunny Wealth Management<span className="cursor neon" /></div>
          <div className="dash-meta">
            <span className="meta-greet">{greeting(now.getHours())}, {name}</span>
            <span>·</span>
            <span>{formatDate(now)}</span>
            <button className="logout" onClick={onLogout}>log out ↗</button>
          </div>
        </div>

        <div className="clock-strip">
          {clocks.map((c) => {
            const t = clockAt(now, c.offset);
            return (
              <div className="clock" key={c.city}>
                <div className="clock-city">{c.city}</div>
                <div className="clock-time">{t.hm}<span className="clock-sec">:{t.s}</span></div>
                <div className="clock-tz">{c.tz}</div>
              </div>
            );
          })}
        </div>

        <div className="tools-section">
          <div className="tools-head">
            <span className="label">Tools · {TOOLS.length}</span>
          </div>
          <div className="tools-grid">
            {TOOLS.map((t) => (
              <button
                key={t.key}
                className={"tool-card " + t.status}
                disabled={t.status === "soon"}
                onClick={() => onOpen(t)}
              >
                <div className="tool-icon"><ToolIcon name={t.key} /></div>
                <div className="tool-mid">
                  <div className="tool-name">{t.name}</div>
                  <div className="tool-desc">{t.desc}</div>
                </div>
                <div className="tool-foot">
                  <span className="tool-status">{t.status === "live" ? "Live" : "Soon"}</span>
                </div>
              </button>
            ))}
          </div>
        </div>

        <div className="quote-foot">
          <em>&ldquo;The stock market is a device for transferring money from the impatient to the patient.&rdquo;</em>
          <span className="quote-attr">— Warren Buffett</span>
        </div>
      </div>

      {toast && <div className={"toast" + (toast.kind === "live" ? " live" : "")}>{toast.msg}</div>}
    </div>
  );
}
