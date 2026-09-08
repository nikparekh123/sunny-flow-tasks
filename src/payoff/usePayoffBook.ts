import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { PayoffBook, SavedPlan } from './types';
import type { Leg } from './math';

/* payoff_plans is newer than the generated Database types, so the typed
   client refuses it. Untyped for this one table, until the types are regenerated. */
const plansTable = () => (supabase as unknown as SupabaseClient).from('payoff_plans');

/* Local dev only: ?fixture renders the page from /dev/payoff-book.json and
   skips auth, the web twin of the iOS -skipAuth launch arg. Never in prod. */
export const DEV_FIXTURE = import.meta.env.DEV && new URLSearchParams(window.location.search).has('fixture');

export function usePayoffBook() {
  return useQuery<PayoffBook>({
    queryKey: ['payoff-book'],
    queryFn: async () => {
      if (DEV_FIXTURE) return (await fetch('/dev/payoff-book.json')).json() as Promise<PayoffBook>;
      const { data, error } = await supabase.functions.invoke('payoff-book', { body: {} });
      if (error) throw error;
      if (!data?.ok) throw new Error(data?.error ?? 'payoff-book did not answer');
      return data as PayoffBook;
    },
    staleTime: 60_000,
  });
}

/**
 * Saved plans live in Supabase, per user, so the web and the iOS app read the
 * same rows. Nik, 2026-09-08: "Plans can get saved on... database, not
 * locally... in a way that I can see it here and also on the iOS."
 */
export function usePlans(userId: string | undefined) {
  const qc = useQueryClient();
  const q = useQuery<SavedPlan[]>({
    queryKey: ['payoff-plans', userId],
    enabled: !!userId,
    queryFn: async () => {
      const { data, error } = await plansTable()
        .select('id,ticker,name,legs,updated_at')
        .order('created_at', { ascending: true });
      if (error) throw error;
      return (data ?? []) as SavedPlan[];
    },
  });
  const invalidate = () => qc.invalidateQueries({ queryKey: ['payoff-plans', userId] });

  const save = useMutation({
    mutationFn: async (p: { ticker: string; name: string; legs: Leg[] }) => {
      const { data, error } = await plansTable()
        .insert({ user_id: userId, ticker: p.ticker, name: p.name, legs: p.legs })
        .select('id')
        .single();
      if (error) throw error;
      return data.id as string;
    },
    onSuccess: invalidate,
  });
  const update = useMutation({
    mutationFn: async (p: { id: string; legs: Leg[] }) => {
      const { error } = await plansTable()
        .update({ legs: p.legs, updated_at: new Date().toISOString() })
        .eq('id', p.id);
      if (error) throw error;
    },
    onSuccess: invalidate,
  });
  const remove = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await plansTable().delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: invalidate,
  });

  return { plans: q.data ?? [], loading: q.isLoading, save, update, remove };
}
