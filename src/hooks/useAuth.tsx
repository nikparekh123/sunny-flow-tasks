import { useState, useEffect, createContext, useContext } from 'react';
import type { ReactNode } from 'react';
import type { User } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';
import type { TeamMember } from '@/lib/types';

interface AuthContextType {
  user: User | null;
  member: TeamMember | null;
  loading: boolean;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  member: null,
  loading: true,
  signOut: async () => {},
});

const MEMBER_COLORS = ['blue', 'green', 'purple', 'orange', 'pink', 'teal'] as const;

const getInitials = (name: string) =>
  name
    .split(' ')
    .filter(Boolean)
    .map((w) => w[0])
    .join('')
    .toUpperCase()
    .slice(0, 2);

const pickColor = (seed: string) => {
  const total = seed.split('').reduce((sum, ch) => sum + ch.charCodeAt(0), 0);
  return MEMBER_COLORS[total % MEMBER_COLORS.length];
};

async function getOrCreateMember(u: User): Promise<TeamMember | null> {
  const { data: existing, error: existingError } = await supabase
    .from('team_members')
    .select('*')
    .eq('user_id', u.id)
    .order('created_at', { ascending: true })
    .limit(1)
    .maybeSingle();

  if (existingError) throw existingError;
  if (existing) return existing as TeamMember;

  const rawName = typeof u.user_metadata?.full_name === 'string' ? u.user_metadata.full_name : undefined;
  const name = rawName?.trim() || u.email?.split('@')[0] || 'User';
  const initials = getInitials(name);
  const color = pickColor(u.id);

  const { data: created, error: createError } = await supabase
    .from('team_members')
    .insert({ user_id: u.id, name, initials, color })
    .select()
    .single();

  if (createError) throw createError;
  return (created as TeamMember) ?? null;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [member, setMember] = useState<TeamMember | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;

    const syncAuthState = async (nextUser: User | null) => {
      try {
        if (!mounted) return;
        setUser(nextUser);

        if (!nextUser) {
          setMember(null);
          return;
        }

        const memberData = await getOrCreateMember(nextUser);
        if (mounted) setMember(memberData);
      } catch (err) {
        console.error('Auth state error:', err);
        if (mounted) setMember(null);
      } finally {
        if (mounted) setLoading(false);
      }
    };

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      void syncAuthState(session?.user ?? null);
    });

    void (async () => {
      try {
        const {
          data: { session },
          error,
        } = await supabase.auth.getSession();

        if (error) throw error;
        await syncAuthState(session?.user ?? null);
      } catch (err) {
        console.error('Initial session error:', err);
        if (mounted) {
          setUser(null);
          setMember(null);
          setLoading(false);
        }
      }
    })();

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, []);

  const signOut = async () => {
    await supabase.auth.signOut();
  };

  return <AuthContext.Provider value={{ user, member, loading, signOut }}>{children}</AuthContext.Provider>;
}

export const useAuth = () => useContext(AuthContext);
