import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { signOut, getDisplayName } from "@/sunnyfi/lib/auth";
import { supabase } from "@/integrations/supabase/client";

type Status = "live" | "soon";
interface Tool {
  key: "tasks" | "research" | "positions" | "snowball" | "strategy" | "calendar" | "math";
  name: string;
  desc: string;
  status: Status;
  hotkey: string;
  href?: string;
  internal?: string; // react-router path
}

const TOOLS: Tool[] = [
  { key: "positions",   name: "Positions",   desc: "Holdings & P&L",       status: "live", hotkey: "1", href: "https://positions.sunnyfi.co" },
  { key: "math",        name: "Math",        desc: "Calculators & scenarios", status: "live", hotkey: "2", internal: "/math" },
  { key: "strategy",    name: "Strategy",    desc: "BNF mean-reversion",   status: "live", hotkey: "3", internal: "/new-strategy" },
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
    math: g(<><rect x="4" y="3" width="16" height="18" rx="1.5" /><rect x="7" y="6" width="10" height="3" /><path d="M8 13h.01M12 13h.01M16 13h.01M8 17h.01M12 17h.01M16 17h.01" /></>),
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

// Compact summary surfaced on the Strategy tile so the user can see at a
// glance how many BNF candidates are live today without leaving the dash.
// Pulled once on mount — fast enough that we don't bother memoizing.
interface BnfStats {
  matches: number;
  borderline: number;
  lastCloseDate: string | null;
}

export default function Dashboard() {
  const navigate = useNavigate();
  const now = useNow();
  const [toast, setToast] = useState<ToastState | null>(null);
  const [fading, setFading] = useState(false);
  const [name, setName] = useState<string>("there");
  const [bnfStats, setBnfStats] = useState<BnfStats | null>(null);

  useEffect(() => {
    let cancelled = false;
    supabase.auth.getUser().then(async ({ data }) => {
      if (cancelled || !data.user) return;
      const n = await getDisplayName(data.user);
      if (!cancelled) setName(n);
    });
    return () => { cancelled = true; };
  }, []);

  // Fetch BNF candidate counts + cache freshness for the Strategy tile.
  // Failures are silent — the tile just shows its default description.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [{ data: cands }, { data: latest }] = await Promise.all([
          supabase
            .from('bnf_candidates' as never)
            .select('borderline')
            .returns<{ borderline: boolean | null }[]>(),
          supabase
            .from('bnf_universe_latest' as never)
            .select('latest_date')
            .order('latest_date', { ascending: false })
            .limit(1)
            .returns<{ latest_date: string }[]>(),
        ]);
        if (cancelled) return;
        const rows = cands ?? [];
        const matches = rows.filter((r) => !r.borderline).length;
        const borderline = rows.filter((r) => r.borderline).length;
        setBnfStats({
          matches,
          borderline,
          lastCloseDate: latest?.[0]?.latest_date ?? null,
        });
      } catch {
        /* swallow — keep tile in default state */
      }
    })();
    return () => { cancelled = true; };
  }, []);

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

        <div className="tools-section">
          <div className="tools-head">
            <span className="label">Tools · {TOOLS.length}</span>
          </div>
          <div className="tools-grid">
            {TOOLS.map((t) => {
              // The Strategy tile gets live counts when available, replacing
              // the static "BNF mean-reversion" tagline. Counts come from
              // bnf_candidates + bnf_universe_latest fetched on mount.
              const desc = t.key === 'strategy' && bnfStats
                ? `${bnfStats.matches} match · ${bnfStats.borderline} near miss`
                : t.desc;
              return (
                <button
                  key={t.key}
                  className={"tool-card " + t.status}
                  disabled={t.status === "soon"}
                  onClick={() => onOpen(t)}
                >
                  <div className="tool-icon"><ToolIcon name={t.key} /></div>
                  <div className="tool-mid">
                    <div className="tool-name">{t.name}</div>
                    <div className="tool-desc">{desc}</div>
                    {t.key === 'strategy' && bnfStats?.lastCloseDate && (
                      <div className="tool-desc" style={{ marginTop: 2, opacity: 0.7 }}>
                        cache · {bnfStats.lastCloseDate}
                      </div>
                    )}
                  </div>
                  <div className="tool-foot">
                    <span className="tool-status">{t.status === "live" ? "Live" : "Soon"}</span>
                  </div>
                </button>
              );
            })}
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
