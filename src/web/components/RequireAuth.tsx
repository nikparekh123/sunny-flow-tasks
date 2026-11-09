// The gate in front of every signed-in page: a session, and a login that belongs to a book (or the old members
// list). Signed out goes to the sign-in page; a login with no book is signed out and sent back with ?denied=1.
// DEV only: fixture mode (?fx) skips the gate, so pages can be checked on saved real replies without signing in.
import { useEffect, useState, type ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';
import { isAllowed, signOut } from '../lib/auth';
import { FX } from '../lib/data';

type State = 'loading' | 'anon' | 'ok' | 'denied';
const allowed = new Map<string, boolean>();

export function RequireAuth({ children }: { children: ReactNode }) {
  const [state, setState] = useState<State>(FX ? 'ok' : 'loading');

  useEffect(() => {
    if (FX) return;
    let live = true;
    const check = async (s: Session | null) => {
      if (!s?.user) { allowed.clear(); if (live) setState('anon'); return; }
      let ok = allowed.get(s.user.id);
      if (ok === undefined) { ok = await isAllowed(s.user); allowed.set(s.user.id, ok); }
      if (!live) return;
      if (ok) setState('ok');
      else { await signOut(); setState('denied'); }
    };
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => { void check(s); });
    return () => { live = false; sub.subscription.unsubscribe(); };
  }, []);

  if (state === 'loading') return <div style={{ minHeight: '100vh', background: '#000000' }} aria-busy="true" />;
  if (state === 'anon') return <Navigate to="/" replace />;
  if (state === 'denied') return <Navigate to="/?denied=1" replace />;
  return <>{children}</>;
}
