import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { TaskWithDetail, Tag, TeamMember } from '@/lib/types';
import type { Database } from '@/integrations/supabase/types';

type TaskColumn = Database['public']['Enums']['task_column'];

export function useTasks() {
  const qc = useQueryClient();

  const { data: tags = [] } = useQuery({
    queryKey: ['tags'],
    queryFn: async () => {
      const { data, error } = await supabase.from('tags').select('*');
      if (error) throw error;
      return (data ?? []) as Tag[];
    },
  });

  const { data: taskTags = [] } = useQuery({
    queryKey: ['task_tags'],
    queryFn: async () => {
      const { data, error } = await supabase.from('task_tags').select('task_id, tag_id');
      if (error) throw error;
      return (data ?? []) as { task_id: string; tag_id: string }[];
    },
  });

  const { data: rawTasks = [], isLoading } = useQuery({
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

  // Merge tags into tasks
  const tasks: TaskWithDetail[] = rawTasks.map((t) => {
    const tagIds = taskTags.filter((tt) => tt.task_id === t.id).map((tt) => tt.tag_id);
    const taskTagList = tags.filter((tag) => tagIds.includes(tag.id));
    return { ...t, tags: taskTagList };
  });

  const { data: members = [] } = useQuery({
    queryKey: ['members'],
    queryFn: async () => {
      const { data, error } = await supabase.from('team_members').select('*');
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

    const tagsSub = supabase
      .channel('tags-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tags' }, () => {
        qc.invalidateQueries({ queryKey: ['tags'] });
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'task_tags' }, () => {
        qc.invalidateQueries({ queryKey: ['task_tags'] });
      })
      .subscribe();

    return () => {
      supabase.removeChannel(tasksSub);
      supabase.removeChannel(tagsSub);
    };
  }, [qc]);

  const createTask = useMutation({
    mutationFn: async (task: {
      title: string;
      column?: TaskColumn;
      priority?: Database['public']['Enums']['task_priority'];
      assignee_id?: string | null;
      due_date?: string | null;
      description?: string | null;
      created_by?: string | null;
      tag_ids?: string[];
    }) => {
      const col = task.column || 'todo';
      const { data: maxPos } = await supabase
        .from('tasks')
        .select('position')
        .eq('column', col)
        .order('position', { ascending: false })
        .limit(1)
        .single();

      const position = (maxPos?.position ?? -1) + 1;

      const { data: newTask, error } = await supabase.from('tasks').insert({
        title: task.title,
        column: col,
        priority: task.priority || 'med',
        position,
        assignee_id: task.assignee_id || null,
        due_date: task.due_date || null,
        description: task.description || null,
        created_by: task.created_by || null,
      }).select('id').single();
      if (error) throw error;

      // Insert tags
      if (task.tag_ids && task.tag_ids.length > 0 && newTask) {
        const { error: tagError } = await supabase.from('task_tags').insert(
          task.tag_ids.map((tag_id) => ({ task_id: newTask.id, tag_id }))
        );
        if (tagError) throw tagError;
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['tasks'] });
      qc.invalidateQueries({ queryKey: ['task_tags'] });
    },
  });

  const updateTask = useMutation({
    mutationFn: async ({ id, tag_ids, ...updates }: { id: string; tag_ids?: string[] } & Partial<{
      title: string;
      priority: Database['public']['Enums']['task_priority'];
      assignee_id: string | null;
      due_date: string | null;
      description: string | null;
    }>) => {
      if (Object.keys(updates).length > 0) {
        const { error } = await supabase.from('tasks').update(updates).eq('id', id);
        if (error) throw error;
      }

      if (tag_ids !== undefined) {
        // Replace all tags
        await supabase.from('task_tags').delete().eq('task_id', id);
        if (tag_ids.length > 0) {
          const { error: tagError } = await supabase.from('task_tags').insert(
            tag_ids.map((tag_id) => ({ task_id: id, tag_id }))
          );
          if (tagError) throw tagError;
        }
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['tasks'] });
      qc.invalidateQueries({ queryKey: ['task_tags'] });
    },
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

  const createTag = useMutation({
    mutationFn: async (name: string) => {
      const { data, error } = await supabase.from('tags').insert({ name }).select('id').single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tags'] }),
  });

  return {
    tasks,
    tags,
    members,
    isLoading,
    createTask,
    updateTask,
    deleteTask,
    moveTask,
    createTag,
  };
}
