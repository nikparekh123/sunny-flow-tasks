import { supabase } from "@/integrations/supabase/client";
import type { Session, User } from "@supabase/supabase-js";

/**
 * Shared team account. Anyone with the 10-digit code signs in as this user.
 * To rotate access, change this user's password in Supabase Auth.
 */
export const SHARED_LOGIN_EMAIL = "nik@sunnyfi.co";

/**
 * Book N's login (the cousin's own 10-digit code, on the same screen), as in the
 * phone app's AuthStore. A code that is not book S's is tried here next; the
 * database refuses the same code for both.
 */
export const BOOK_N_LOGIN_EMAIL = "book-n@sunnyfi.co";

/**
 * Sign in with a 10-digit code (the password for one of the two logins).
 * Code only: there is no email-link sign-in on the web.
 */
export async function signInWithCode(code: string): Promise<
  | { ok: true }
  | { ok: false; reason: "invalid_code" | "wrong_code" | "network" | "unknown"; message?: string }
> {
  const trimmed = code.trim().replace(/\s+/g, "");
  if (!/^\d{10}$/.test(trimmed)) {
    return { ok: false, reason: "invalid_code" };
  }
  let last: { reason: "wrong_code" | "unknown"; message?: string } | null = null;
  for (const email of [SHARED_LOGIN_EMAIL, BOOK_N_LOGIN_EMAIL]) {
    try {
      const { error } = await supabase.auth.signInWithPassword({ email, password: trimmed });
      if (!error) return { ok: true };
      const status = (error as { status?: number }).status;
      // Only a wrong code moves on to the next login; anything else stops here.
      if (status !== 400) return { ok: false, reason: "unknown", message: error.message };
      last = { reason: "wrong_code", message: error.message };
    } catch (e) {
      return { ok: false, reason: "network", message: e instanceof Error ? e.message : undefined };
    }
  }
  return { ok: false, ...(last ?? { reason: "wrong_code" as const }) };
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

/**
 * Is the signed-in user let in? Yes when they belong to a book (book_members,
 * which RLS lets a user read only for their own rows), as in the phone app.
 * The older `members` list (nik@ only) still counts, so nothing that worked stops.
 */
export async function isAllowed(user: User): Promise<boolean> {
  const { data: books, error: booksError } = await supabase
    .from("book_members" as never)
    .select("book_id")
    .eq("user_id", user.id)
    .limit(1);
  if (!booksError && Array.isArray(books) && books.length > 0) return true;
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
