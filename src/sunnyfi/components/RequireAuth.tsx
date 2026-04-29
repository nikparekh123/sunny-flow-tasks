import { useEffect, useState, type ReactNode } from "react";
import { Navigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { isAllowed, signOut } from "@/sunnyfi/lib/auth";
import type { Session } from "@supabase/supabase-js";

type State =
  | { kind: "loading" }
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

    const evaluate = async (session: Session | null) => {
      if (!session?.user) {
        allowedCache.clear();
        if (mounted) setState({ kind: "anon" });
        return;
      }

      // Use the cached membership decision when we have it — avoids a
      // network round-trip on every navigation.
      const cached = allowedCache.get(session.user.id);
      if (cached !== undefined) {
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
      if (!mounted) return;
      if (allowed) {
        setState({ kind: "ok" });
        return;
      }
      await signOut();
      setState({ kind: "denied" });
    };

    // onAuthStateChange fires immediately with the current session
    // (INITIAL_SESSION event), so we don't need a separate getSession call
    // — that was causing two redundant evaluations on every mount.
    const { data: sub } = supabase.auth.onAuthStateChange(
      (_event, session) => evaluate(session),
    );

    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  if (state.kind === "loading") {
    return (
      <div
        style={{
          height: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#0e2a1e",
          color: "#c8d7bf",
          fontFamily: "var(--navi-font-mono)",
          fontSize: 11,
          letterSpacing: 1.2,
        }}
      >
        Loading…
      </div>
    );
  }
  if (state.kind === "anon") return <Navigate to="/" replace />;
  if (state.kind === "denied") return <Navigate to="/?denied=1" replace />;
  return <>{children}</>;
}
