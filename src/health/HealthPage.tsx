/**
 * /health — diagnostic page for the mp-refresh pipeline.
 *
 * Hidden route (no nav link) — type the URL to access. Surfaces:
 *   - Last run timestamp + status + staleness traffic-light
 *   - Per-table captured_at freshness (Greeks + quotes)
 *   - Recent runs table (last 20) with status, counts, error text
 *   - Most-recent failure list (per-leg OCC + reason)
 *   - Cron job status from pg_cron + last fire time
 *   - Manual "Run mp-refresh now" button
 *
 * Reads only — no mutations except the manual trigger (which calls the
 * same edge function the cron does).
 */
import { useMemo } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import "./health.css";

interface RefreshRun {
  id: string;
  started_at: string;
  finished_at: string | null;
  status: "running" | "ok" | "error";
  legs_total: number | null;
  legs_updated: number | null;
  legs_failed: number | null;
  tickers_total: number | null;
  tickers_updated: number | null;
  error_text: string | null;
  failures: Array<{ id?: string; ticker?: string; occ?: string; reason?: string }> | null;
  invoked_by: string | null;
}

interface FreshnessRow {
  captured_at: string;
}

interface CronJobRow {
  jobid: number;
  jobname: string;
  schedule: string;
  active: boolean;
  last_run: string | null;
  last_status: string | null;
}

// ─── Helpers ────────────────────────────────────────────────────
function relativeAge(iso: string | null): string {
  if (!iso) return "never";
  const ms = Date.now() - new Date(iso).getTime();
  const s = Math.round(ms / 1000);
  if (s < 60) return s + "s ago";
  const m = Math.round(s / 60);
  if (m < 60) return m + "m ago";
  const h = Math.round(m / 60);
  if (h < 48) return h + "h ago";
  return Math.round(h / 24) + "d ago";
}

function fmtTime(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("en-US", {
    month: "short", day: "numeric",
    hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false,
  });
}

/** Traffic light: green if last successful run within 30 min, amber if
 *  within 2 h, red beyond that. During off-hours (weekends, evenings)
 *  amber/red are expected — the page text below the dot explains. */
function staleness(latestOk: string | null): { color: string; label: string } {
  if (!latestOk) return { color: "var(--negative)", label: "no successful runs" };
  const m = (Date.now() - new Date(latestOk).getTime()) / 60_000;
  if (m < 30) return { color: "var(--positive)", label: "fresh" };
  if (m < 120) return { color: "var(--warning)", label: "stale" };
  return { color: "var(--negative)", label: "very stale" };
}

// ─── Page ───────────────────────────────────────────────────────
export function HealthPage() {
  const qc = useQueryClient();

  const runsQ = useQuery({
    queryKey: ["health_runs"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("mp_refresh_runs" as never)
        .select("*")
        .order("started_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return (data ?? []) as unknown as RefreshRun[];
    },
    refetchInterval: 30_000,
  });

  const greeksFreshQ = useQuery({
    queryKey: ["health_greeks_freshness"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_greeks" as never)
        .select("captured_at");
      if (error) throw error;
      return (data ?? []) as unknown as FreshnessRow[];
    },
    refetchInterval: 60_000,
  });

  const quotesFreshQ = useQuery({
    queryKey: ["health_quotes_freshness"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("ticker_quotes" as never)
        .select("captured_at");
      if (error) throw error;
      return (data ?? []) as unknown as FreshnessRow[];
    },
    refetchInterval: 60_000,
  });

  // cron.job + last fire — requires that the cron migration ran AND the
  // user activated the schedule. Returns empty if not.
  const cronQ = useQuery({
    queryKey: ["health_cron"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("get_cron_status" as never, {} as never);
      // RPC may not exist if no one set it up — fall back gracefully.
      if (error) return [] as CronJobRow[];
      return (data ?? []) as unknown as CronJobRow[];
    },
    refetchInterval: 60_000,
  });

  const refreshMut = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.functions.invoke("mp-refresh", { body: {} });
      if (error) throw new Error(error.message ?? "mp-refresh failed");
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["health_runs"] });
      qc.invalidateQueries({ queryKey: ["health_greeks_freshness"] });
      qc.invalidateQueries({ queryKey: ["health_quotes_freshness"] });
      qc.invalidateQueries({ queryKey: ["mp_greeks"] });
      qc.invalidateQueries({ queryKey: ["mp_quotes"] });
    },
  });

  const latestOk = useMemo(() => {
    const ok = (runsQ.data ?? []).find((r) => r.status === "ok");
    return ok?.finished_at ?? ok?.started_at ?? null;
  }, [runsQ.data]);
  const latestAny = useMemo(() => {
    const r = (runsQ.data ?? [])[0];
    return r?.finished_at ?? r?.started_at ?? null;
  }, [runsQ.data]);

  const light = staleness(latestOk);

  // Per-table freshness summaries.
  const greeksRows = greeksFreshQ.data ?? [];
  const quotesRows = quotesFreshQ.data ?? [];
  const greeksLatest = greeksRows.reduce<string | null>(
    (a, r) => (!a || r.captured_at > a ? r.captured_at : a), null);
  const quotesLatest = quotesRows.reduce<string | null>(
    (a, r) => (!a || r.captured_at > a ? r.captured_at : a), null);

  // 24h success counts from the runs feed.
  const cutoff = Date.now() - 24 * 60 * 60_000;
  const last24h = (runsQ.data ?? []).filter((r) => new Date(r.started_at).getTime() > cutoff);
  const ok24 = last24h.filter((r) => r.status === "ok").length;
  const err24 = last24h.filter((r) => r.status === "error").length;
  const running24 = last24h.filter((r) => r.status === "running").length;

  const mostRecentFailures = (runsQ.data ?? []).find((r) => (r.failures?.length ?? 0) > 0);

  return (
    <div className="health-page">
      <div className="hp-head">
        <div>
          <div className="hp-eyebrow">DIAGNOSTIC · MP-REFRESH PIPELINE</div>
          <div className="hp-title">Health<span className="sub"> / portfolio data pipeline</span></div>
        </div>
        <div className="hp-actions">
          <button
            className="hp-btn"
            onClick={() => refreshMut.mutate()}
            disabled={refreshMut.isPending}
            title="Manually invoke mp-refresh now. Useful right after entering a trade so Greeks land before the next 15-min cron."
          >
            ↻ {refreshMut.isPending ? "Refreshing…" : "Run mp-refresh now"}
          </button>
        </div>
      </div>

      {/* ─── Status hero ─── */}
      <div className="hp-hero">
        <div className="hp-light" style={{ background: light.color }} />
        <div className="hp-hero-text">
          <div className="hp-hero-status">{light.label.toUpperCase()}</div>
          <div className="hp-hero-sub">
            Last successful run <b>{relativeAge(latestOk)}</b>
            {latestOk && <span className="hp-dim"> · {fmtTime(latestOk)}</span>}
          </div>
          <div className="hp-hero-meta">
            Last attempt {relativeAge(latestAny)} ·{" "}
            <span className="pos">{ok24} ok</span> · <span className="neg">{err24} error</span>
            {running24 > 0 && <> · <span className="warn">{running24} in flight</span></>} in 24h
          </div>
        </div>
      </div>

      {/* ─── Per-table freshness ─── */}
      <div className="hp-section">
        <div className="hp-section-label">Table freshness</div>
        <div className="hp-fresh-grid">
          <div className="hp-fresh">
            <div className="k">option_greeks</div>
            <div className="v">{greeksRows.length} rows</div>
            <div className="sub">latest captured_at {relativeAge(greeksLatest)}</div>
            <div className="dim">{fmtTime(greeksLatest)}</div>
          </div>
          <div className="hp-fresh">
            <div className="k">ticker_quotes</div>
            <div className="v">{quotesRows.length} rows</div>
            <div className="sub">latest captured_at {relativeAge(quotesLatest)}</div>
            <div className="dim">{fmtTime(quotesLatest)}</div>
          </div>
        </div>
      </div>

      {/* ─── Cron status ─── */}
      <div className="hp-section">
        <div className="hp-section-label">pg_cron</div>
        {(cronQ.data ?? []).length === 0 ? (
          <div className="hp-empty">
            No cron jobs surfaced. Either the schedule isn't active or
            the <code>get_cron_status</code> RPC isn't installed (it's optional —
            see <code>supabase/migrations/20260530001100_health_cron_rpc.sql</code>).
            The 15-min auto-refresh may still be firing; check
            <code> select * from cron.job; </code> in the SQL editor.
          </div>
        ) : (
          <div className="hp-cron-grid">
            {(cronQ.data ?? []).map((j) => (
              <div key={j.jobid} className="hp-cron">
                <div className="k">{j.jobname}</div>
                <div className="v">{j.schedule}</div>
                <div className="sub">
                  {j.active ? <span className="pos">active</span> : <span className="neg">paused</span>}
                  {j.last_run && <> · last fired {relativeAge(j.last_run)}</>}
                  {j.last_status && <> · <span className={j.last_status === "succeeded" ? "pos" : "neg"}>{j.last_status}</span></>}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* ─── Recent failure ─── */}
      {mostRecentFailures && (mostRecentFailures.failures?.length ?? 0) > 0 && (
        <div className="hp-section">
          <div className="hp-section-label">Most recent failures · {mostRecentFailures.failures!.length} legs</div>
          <div className="hp-failures">
            {mostRecentFailures.failures!.map((f, i) => (
              <div key={i} className="hp-fail">
                <span className="ticker">{f.ticker ?? "—"}</span>
                <span className="occ">{f.occ ?? "—"}</span>
                <span className="reason">{f.reason ?? "—"}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ─── Recent runs table ─── */}
      <div className="hp-section">
        <div className="hp-section-label">Recent runs · last 20</div>
        <table className="hp-table">
          <thead>
            <tr>
              <th>Started</th>
              <th>Duration</th>
              <th>Status</th>
              <th>By</th>
              <th>Legs</th>
              <th>Tickers</th>
              <th>Error</th>
            </tr>
          </thead>
          <tbody>
            {runsQ.isLoading && (
              <tr><td colSpan={7} className="hp-empty-row">Loading…</td></tr>
            )}
            {!runsQ.isLoading && (runsQ.data ?? []).length === 0 && (
              <tr><td colSpan={7} className="hp-empty-row">No runs recorded yet.</td></tr>
            )}
            {(runsQ.data ?? []).map((r) => {
              const dur = r.finished_at
                ? Math.round((new Date(r.finished_at).getTime() - new Date(r.started_at).getTime()) / 1000) + "s"
                : "—";
              const legs = r.legs_updated != null
                ? `${r.legs_updated}/${r.legs_total ?? "?"}${r.legs_failed ? ` (${r.legs_failed} fail)` : ""}`
                : "—";
              const tickers = r.tickers_updated != null
                ? `${r.tickers_updated}/${r.tickers_total ?? "?"}`
                : "—";
              const statusClass = r.status === "ok" ? "pos" : r.status === "error" ? "neg" : "warn";
              return (
                <tr key={r.id}>
                  <td><div>{fmtTime(r.started_at)}</div><div className="dim">{relativeAge(r.started_at)}</div></td>
                  <td>{dur}</td>
                  <td><span className={statusClass}>{r.status}</span></td>
                  <td className="dim">{r.invoked_by ?? "—"}</td>
                  <td>{legs}</td>
                  <td>{tickers}</td>
                  <td className="hp-err">{r.error_text ?? "—"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="hp-foot">
        Auto-refreshes every 30s. Hit ↻ to invoke the pipeline manually
        (same call the cron makes).
      </div>
    </div>
  );
}
