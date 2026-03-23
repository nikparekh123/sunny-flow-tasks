import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { TaskWithDetail, TaskCategory, TeamMember } from '@/lib/types';
import type { Database } from '@/integrations/supabase/types';

type TaskColumn = Database['public']['Enums']['task_column'];

export function useTasks() {
  const qc = useQueryClient();

  const { data: tasks = [], isLoading } = useQuery({
    queryKey: ['tasks'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('tasks_with_detail')
        .select('*')
        .order('position');
      if (error) throw error;
      return (data ?? []) as unknown as TaskWithDetail[];
    },
  });

  const { data: categories = [] } = useQuery({
    queryKey: ['categories'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('task_categories')
        .select('*')
        .order('position');
      if (error) throw error;
      return (data ?? []) as TaskCategory[];
    },
  });

  const { data: members = [] } = useQuery({
    queryKey: ['members'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('team_members')
        .select('*');
      if (error) throw error;
      return (data ?? []) as TeamMember[];
    },
  });

  // Realtime subscriptions
  useEffect(() => {
    const tasksSub = supabase
      .channel('tasks-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks' }, () => {
        qc.invalidateQueries({ queryKey: ['tasks'] });
      })
      .subscribe();

    const catsSub = supabase
      .channel('categories-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'task_categories' }, () => {
        qc.invalidateQueries({ queryKey: ['categories'] });
      })
      .subscribe();

    return () => {
      supabase.removeChannel(tasksSub);
      supabase.removeChannel(catsSub);
    };
  }, [qc]);

  const createTask = useMutation({
    mutationFn: async (task: {
      title: string;
      column?: TaskColumn;
      priority?: Database['public']['Enums']['task_priority'];
      category_id?: string | null;
      assignee_id?: string | null;
      due_date?: string | null;
      description?: string | null;
      created_by?: string | null;
    }) => {
      // Get max position in column
      const col = task.column || 'todo';
      const { data: maxPos } = await supabase
        .from('tasks')
        .select('position')
        .eq('column', col)
        .order('position', { ascending: false })
        .limit(1)
        .single();

      const position = (maxPos?.position ?? -1) + 1;

      const { error } = await supabase.from('tasks').insert({
        title: task.title,
        column: col,
        priority: task.priority || 'med',
        position,
        category_id: task.category_id || null,
        assignee_id: task.assignee_id || null,
        due_date: task.due_date || null,
        description: task.description || null,
        created_by: task.created_by || null,
      });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks'] }),
  });

  const updateTask = useMutation({
    mutationFn: async ({ id, ...updates }: { id: string } & Partial<{
      title: string;
      priority: Database['public']['Enums']['task_priority'];
      category_id: string | null;
      assignee_id: string | null;
      due_date: string | null;
      description: string | null;
    }>) => {
      const { error } = await supabase.from('tasks').update(updates).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks'] }),
  });

  const deleteTask = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('tasks').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks'] }),
  });

  const moveTask = useMutation({
    mutationFn: async ({ taskId, column, position }: { taskId: string; column: TaskColumn; position: number }) => {
      const { error } = await supabase.rpc('reorder_task', {
        p_task_id: taskId,
        p_column: column,
        p_position: position,
      });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks'] }),
  });

  // Category mutations
  const createCategory = useMutation({
    mutationFn: async ({ name, color, position }: { name: string; color: string; position: number }) => {
      const { error } = await supabase.from('task_categories').insert({ name, color, position });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['categories'] }),
  });

  const updateCategory = useMutation({
    mutationFn: async ({ id, name }: { id: string; name: string }) => {
      const { error } = await supabase.from('task_categories').update({ name }).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['categories'] }),
  });

  const deleteCategory = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('task_categories').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['categories'] }),
  });

  return {
    tasks,
    categories,
    members,
    isLoading,
    createTask,
    updateTask,
    deleteTask,
    moveTask,
    createCategory,
    updateCategory,
    deleteCategory,
  };
}
