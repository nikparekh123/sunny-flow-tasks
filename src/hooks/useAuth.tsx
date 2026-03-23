import { useState, useEffect, createContext, useContext } from 'react';
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

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [member, setMember] = useState<TeamMember | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (_event, session) => {
      const u = session?.user ?? null;
      setUser(u);
      if (u) {
        // Fetch or create team member
        const { data: existing } = await supabase
          .from('team_members')
          .select('*')
          .eq('user_id', u.id)
          .maybeSingle();

        if (existing) {
          setMember(existing as TeamMember);
        } else {
          const name = u.user_metadata?.full_name || u.email?.split('@')[0] || 'User';
          const initials = name.split(' ').map((w: string) => w[0]).join('').toUpperCase().slice(0, 2);
          const colors = ['blue', 'green', 'purple', 'orange', 'pink', 'teal'];
          const color = colors[Math.floor(Math.random() * colors.length)];

          const { data: created } = await supabase
            .from('team_members')
            .insert({ user_id: u.id, name, initials, color })
            .select()
            .single();

          if (created) setMember(created as TeamMember);
        }
      } else {
        setMember(null);
      }
      setLoading(false);
    });

    supabase.auth.getSession();

    return () => subscription.unsubscribe();
  }, []);

  const signOut = async () => {
    await supabase.auth.signOut();
  };

  return (
    <AuthContext.Provider value={{ user, member, loading, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);
