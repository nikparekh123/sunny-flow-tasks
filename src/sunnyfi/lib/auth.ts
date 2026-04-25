import { supabase } from "@/integrations/supabase/client";
import type { Session, User } from "@supabase/supabase-js";

const REDIRECT_URL =
  typeof window !== "undefined" ? `${window.location.origin}/auth/callback` : "";

export async function sendMagicLink(email: string): Promise<
  | { ok: true }
  | { ok: false; reason: "invalid_email" | "rate_limited" | "network" | "unknown"; message?: string }
> {
  const trimmed = email.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) {
    return { ok: false, reason: "invalid_email" };
  }
  try {
    const { error } = await supabase.auth.signInWithOtp({
      email: trimmed,
      options: {
        emailRedirectTo: REDIRECT_URL,
        // Don't auto-create accounts for non-allowlisted users — but Supabase
        // doesn't enforce the allowlist; our client check after callback does.
        shouldCreateUser: true,
      },
    });
    if (error) {
      const status = (error as { status?: number }).status;
      if (status === 429) return { ok: false, reason: "rate_limited", message: error.message };
      return { ok: false, reason: "unknown", message: error.message };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: "network", message: e instanceof Error ? e.message : undefined };
  }
}

/** Pre-login check: is this email in the allowlist? Safe to call anon. */
export async function checkMemberEmail(email: string): Promise<boolean> {
  const trimmed = email.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) return false;
  const { data, error } = await (supabase.rpc as unknown as (
    name: string,
    args: { p_email: string },
  ) => Promise<{ data: boolean | null; error: unknown }>)("is_member", {
    p_email: trimmed,
  });
  if (error) return false;
  return !!data;
}

/** Check that the signed-in user's email is in the `members` allowlist. */
export async function isAllowed(user: User): Promise<boolean> {
  if (!user.email) return false;
  const { data, error } = await supabase
    .from("members")
    .select("email")
    .eq("email", user.email.toLowerCase())
    .maybeSingle();
  if (error) return false;
  return !!data;
}

/** Look up the display name from `members`, fall back to email-derived. */
export async function getDisplayName(user: User): Promise<string> {
  if (!user.email) return "there";
  const { data } = await supabase
    .from("members")
    .select("display_name")
    .eq("email", user.email.toLowerCase())
    .maybeSingle();
  if (data?.display_name) return data.display_name;
  // Fallback: capitalize the local part of the email.
  const local = user.email.split("@")[0];
  return local.charAt(0).toUpperCase() + local.slice(1);
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut();
}

export function getCurrentSession(): Promise<Session | null> {
  return supabase.auth.getSession().then(({ data }) => data.session);
}
