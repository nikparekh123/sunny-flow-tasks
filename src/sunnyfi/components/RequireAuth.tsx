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

export default function RequireAuth({ children }: { children: ReactNode }) {
  const [state, setState] = useState<State>({ kind: "loading" });

  useEffect(() => {
    let mounted = true;
    const evaluate = async (session: Session | null) => {
      if (!session?.user) { if (mounted) setState({ kind: "anon" }); return; }
      const allowed = await isAllowed(session.user);
      if (!mounted) return;
      if (allowed) { setState({ kind: "ok" }); return; }
      // Signed in but not on the allowlist — kick them out.
      await signOut();
      setState({ kind: "denied" });
    };

    supabase.auth.getSession().then(({ data }) => evaluate(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => evaluate(session));
    return () => { mounted = false; sub.subscription.unsubscribe(); };
  }, []);

  if (state.kind === "loading") {
    return (
      <div style={{
        height: "100vh", display: "flex", alignItems: "center", justifyContent: "center",
        background: "#0e2a1e", color: "#c8d7bf",
        fontFamily: "var(--navi-font-mono)", fontSize: 11, letterSpacing: 1.2,
      }}>
        Loading…
      </div>
    );
  }
  if (state.kind === "anon") return <Navigate to="/" replace />;
  if (state.kind === "denied") return <Navigate to="/?denied=1" replace />;
  return <>{children}</>;
}
