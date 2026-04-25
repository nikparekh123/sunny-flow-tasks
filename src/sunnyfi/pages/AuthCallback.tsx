import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { isAllowed, signOut } from "@/sunnyfi/lib/auth";

export default function AuthCallback() {
  const navigate = useNavigate();
  const [msg, setMsg] = useState<string>("Signing you in…");

  useEffect(() => {
    let cancelled = false;

    const finish = async () => {
      // supabase-js auto-detects the token in the URL hash on load. Wait
      // briefly for it to populate the session, then read it out.
      await new Promise((r) => setTimeout(r, 50));
      const { data } = await supabase.auth.getSession();
      if (cancelled) return;

      if (!data.session?.user) {
        // No session — link expired or already used.
        setMsg("That sign-in link didn't work. Try again.");
        setTimeout(() => navigate("/?expired=1", { replace: true }), 1200);
        return;
      }

      const ok = await isAllowed(data.session.user);
      if (cancelled) return;
      if (!ok) {
        await signOut();
        setMsg("That email isn't on the allowlist.");
        setTimeout(() => navigate("/?denied=1", { replace: true }), 1500);
        return;
      }

      navigate("/dashboard", { replace: true });
    };

    finish();
    return () => { cancelled = true; };
  }, [navigate]);

  return (
    <div className="app">
      <div className="landing">
        <div className="landing-hero">
          <div style={{
            fontFamily: "var(--navi-font-sans)",
            fontSize: 16, letterSpacing: 1.2, textTransform: "uppercase",
            color: "var(--neon-text-on-neon)",
          }}>
            {msg}
          </div>
        </div>
      </div>
    </div>
  );
}
