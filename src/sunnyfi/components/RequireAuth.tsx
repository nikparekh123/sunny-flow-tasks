import { useEffect, useState, type ReactNode } from "react";
import { Navigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { isAllowed, signOut } from "@/sunnyfi/lib/auth";
import type { Session } from "@supabase/supabase-js";

type State =
  | { kind: "loading" }
  | { kind: "slow" }
  | { kind: "error"; message: string }
  | { kind: "anon" }
  | { kind: "ok" }
  | { kind: "denied" };

/**
 * Module-level cache so navigating between RequireAuth-gated routes
 * doesn't re-issue the `isAllowed` query (network round-trip to Supabase).
 * Keyed by user id; cleared on sign-out.
 */
const allowedCache = new Map<string, boolean>();

export default function RequireAuth({ children }: { children: ReactNode }) {
  const [state, setState] = useState<State>({ kind: "loading" });

  useEffect(() => {
    let mounted = true;
    let resolved = false;

    const evaluate = async (session: Session | null) => {
      try {
        if (!session?.user) {
          allowedCache.clear();
          resolved = true;
          if (mounted) setState({ kind: "anon" });
          return;
        }

        // Use the cached membership decision when we have it — avoids a
        // network round-trip on every navigation.
        const cached = allowedCache.get(session.user.id);
        if (cached !== undefined) {
          resolved = true;
          if (!mounted) return;
          if (cached) {
            setState({ kind: "ok" });
          } else {
            await signOut();
            setState({ kind: "denied" });
          }
          return;
        }

        const allowed = await isAllowed(session.user);
        allowedCache.set(session.user.id, allowed);
        resolved = true;
        if (!mounted) return;
        if (allowed) {
          setState({ kind: "ok" });
          return;
        }
        await signOut();
        setState({ kind: "denied" });
      } catch (e) {
        resolved = true;
        if (mounted)
          setState({
            kind: "error",
            message: e instanceof Error ? e.message : String(e),
          });
      }
    };

    // Surface slow loading after 3s so users see a hint instead of staring at "Loading…".
    const slowTimer = window.setTimeout(() => {
      if (mounted && !resolved) setState({ kind: "slow" });
    }, 3000);

    // onAuthStateChange fires immediately with the current session
    // (INITIAL_SESSION event), so we don't need a separate getSession call
    // — that was causing two redundant evaluations on every mount.
    const { data: sub } = supabase.auth.onAuthStateChange(
      (_event, session) => evaluate(session),
    );

    return () => {
      mounted = false;
      clearTimeout(slowTimer);
      sub.subscription.unsubscribe();
    };
  }, []);

  if (state.kind === "loading" || state.kind === "slow" || state.kind === "error") {
    const label =
      state.kind === "loading"
        ? "Loading…"
        : state.kind === "slow"
          ? "Auth check is slow — Supabase may be unresponsive. Sit tight or check console."
          : `Auth error: ${state.message}`;
    return (
      <div
        style={{
          height: "100vh",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: 12,
          background: "#0e2a1e",
          color: "#c8d7bf",
          fontFamily: "var(--navi-font-mono)",
          fontSize: 11,
          letterSpacing: 1.2,
          padding: 20,
          textAlign: "center",
        }}
      >
        <div>{label}</div>
        {state.kind !== "loading" && (
          <button
            type="button"
            onClick={() => window.location.assign("/")}
            style={{
              padding: "6px 14px",
              fontSize: 11,
              letterSpacing: 1.2,
              textTransform: "uppercase",
              background: "transparent",
              border: "1px solid #468278",
              borderRadius: 4,
              color: "#c8d7bf",
              cursor: "pointer",
            }}
          >
            back to landing
          </button>
        )}
      </div>
    );
  }
  if (state.kind === "anon") return <Navigate to="/" replace />;
  if (state.kind === "denied") return <Navigate to="/?denied=1" replace />;
  return <>{children}</>;
}
