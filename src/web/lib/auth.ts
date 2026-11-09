import { supabase } from "@/integrations/supabase/client";
import type { Session, User } from "@supabase/supabase-js";

// Sign-in for the Sunny web (moved from src/sunnyfi/lib/auth.ts, 9 Nov 2026). Code only (Nik, 8 Nov 2026).

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
    .from("members" as never)
    .select("email")
    .eq("email", user.email.toLowerCase())
    .maybeSingle();
  if (error) return false;
  return !!data;
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut();
}

export function getCurrentSession(): Promise<Session | null> {
  return supabase.auth.getSession().then(({ data }) => data.session);
}
