import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { AutomationRule } from '@/lib/types';

export function useRules() {
  const qc = useQueryClient();

  const { data: rules = [], isLoading } = useQuery({
    queryKey: ['automation_rules'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('automation_rules')
        .select('*')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as AutomationRule[];
    },
  });

  const createRule = useMutation({
    mutationFn: async (rule: Omit<AutomationRule, 'id' | 'created_at'>) => {
      const { error } = await supabase.from('automation_rules').insert(rule as any);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['automation_rules'] }),
  });

  const updateRule = useMutation({
    mutationFn: async ({ id, ...updates }: { id: string } & Partial<AutomationRule>) => {
      const { error } = await supabase.from('automation_rules').update(updates as any).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['automation_rules'] }),
  });

  const deleteRule = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('automation_rules').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['automation_rules'] }),
  });

  const toggleRule = useMutation({
    mutationFn: async ({ id, active }: { id: string; active: boolean }) => {
      const { error } = await supabase.from('automation_rules').update({ active } as any).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['automation_rules'] }),
  });

  return { rules, isLoading, createRule, updateRule, deleteRule, toggleRule };
}
