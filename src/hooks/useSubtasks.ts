import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { Subtask } from '@/lib/types';

export function useSubtasks() {
  const qc = useQueryClient();

  const { data: subtasks = [] } = useQuery({
    queryKey: ['subtasks'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('subtasks')
        .select('*')
        .order('position');
      if (error) throw error;
      return (data ?? []) as Subtask[];
    },
  });

  const createSubtask = useMutation({
    mutationFn: async (params: { task_id: string; title: string; assignee_id?: string | null }) => {
      // Get max position for this task
      const taskSubtasks = subtasks.filter(s => s.task_id === params.task_id);
      const maxPos = taskSubtasks.length > 0 ? Math.max(...taskSubtasks.map(s => s.position)) + 1 : 0;

      const { error } = await supabase.from('subtasks').insert({
        task_id: params.task_id,
        title: params.title,
        assignee_id: params.assignee_id || null,
        position: maxPos,
      } as any);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['subtasks'] }),
  });

  const toggleSubtask = useMutation({
    mutationFn: async ({ id, done }: { id: string; done: boolean }) => {
      const { error } = await supabase.from('subtasks').update({ done } as any).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['subtasks'] }),
  });

  const deleteSubtask = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('subtasks').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['subtasks'] }),
  });

  const completeAllSubtasks = useMutation({
    mutationFn: async (taskId: string) => {
      const { error } = await supabase
        .from('subtasks')
        .update({ done: true } as any)
        .eq('task_id', taskId);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['subtasks'] }),
  });

  return { subtasks, createSubtask, toggleSubtask, deleteSubtask, completeAllSubtasks };
}
