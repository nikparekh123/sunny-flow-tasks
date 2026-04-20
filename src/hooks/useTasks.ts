import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { addDays, addMonths, format, parseISO, getDay, nextDay } from 'date-fns';
import type { TaskWithDetail, Tag, TeamMember, RecurrenceFrequency, TaskAssignee, CustomRecurrenceConfig, Subtask } from '@/lib/types';
import type { Database } from '@/integrations/supabase/types';
import { useRuleEngine } from './useRuleEngine';

type TaskColumn = Database['public']['Enums']['task_column'];

const BOARD_COLUMNS: TaskColumn[] = ['backlog', 'todo', 'inprogress', 'review', 'done'];

const DAY_MAP: Record<string, number> = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };

const moveTaskOptimistically = (
  tasks: TaskWithDetail[],
  taskId: string,
  targetColumn: TaskColumn,
  targetPosition: number
): TaskWithDetail[] => {
  const sourceTask = tasks.find((task) => task.id === taskId);
  if (!sourceTask) return tasks;

  const byColumn: Record<TaskColumn, TaskWithDetail[]> = {
    backlog: [], todo: [], inprogress: [], review: [], done: [],
  };

  tasks.forEach((task) => {
    if (task.id !== taskId) byColumn[task.column].push({ ...task });
  });

  BOARD_COLUMNS.forEach((column) => {
    byColumn[column].sort((a, b) => a.position - b.position);
  });

  const movedTask: TaskWithDetail = { ...sourceTask, column: targetColumn };
  const safePosition = Math.max(0, Math.min(targetPosition, byColumn[targetColumn].length));
  byColumn[targetColumn].splice(safePosition, 0, movedTask);

  BOARD_COLUMNS.forEach((column) => {
    byColumn[column] = byColumn[column].map((task, index) => ({ ...task, position: index }));
  });

  return BOARD_COLUMNS.flatMap((column) => byColumn[column]);
};

function calcNextDueDate(currentDue: string, frequency: string): string {
  // Handle custom recurrence
  if (frequency.startsWith('custom:')) {
    try {
      const config: CustomRecurrenceConfig = JSON.parse(frequency.slice(7));
      const date = parseISO(currentDue);
      if (config.days && config.days.length > 0) {
        const currentDayIndex = getDay(date);
        const dayIndices = config.days.map(d => DAY_MAP[d]).filter(d => d !== undefined).sort((a, b) => a - b);
        // Find next day after current
        const nextDayIndex = dayIndices.find(d => d > currentDayIndex);
        if (nextDayIndex !== undefined) {
          return format(nextDay(date, nextDayIndex as 0|1|2|3|4|5|6), 'yyyy-MM-dd');
        }
        // Wrap to first day of next week
        const firstDay = dayIndices[0];
        return format(nextDay(date, firstDay as 0|1|2|3|4|5|6), 'yyyy-MM-dd');
      }
      if (config.dayOfMonth) {
        const next = new Date(date);
        next.setMonth(next.getMonth() + 1);
        next.setDate(config.dayOfMonth);
        return format(next, 'yyyy-MM-dd');
      }
    } catch {
      // fallback
    }
    return format(addDays(parseISO(currentDue), 7), 'yyyy-MM-dd');
  }

  const date = parseISO(currentDue);
  switch (frequency as RecurrenceFrequency) {
    case 'daily': return format(addDays(date, 1), 'yyyy-MM-dd');
    case 'weekly': return format(addDays(date, 7), 'yyyy-MM-dd');
    case 'biweekly': return format(addDays(date, 14), 'yyyy-MM-dd');
    case 'monthly': return format(addMonths(date, 1), 'yyyy-MM-dd');
    default: return format(addDays(date, 7), 'yyyy-MM-dd');
  }
}

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

  const { data: taskAssignees = [] } = useQuery({
    queryKey: ['task_assignees'],
    queryFn: async () => {
      const { data, error } = await supabase.from('task_assignees').select('task_id, assignee_id');
      if (error) throw error;
      return (data ?? []) as { task_id: string; assignee_id: string }[];
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

  const { data: members = [] } = useQuery({
    queryKey: ['members'],
    queryFn: async () => {
      const { data, error } = await supabase.from('team_members').select('*');
      if (error) throw error;
      return (data ?? []) as TeamMember[];
    },
  });

  const { data: allSubtasks = [] } = useQuery({
    queryKey: ['subtasks'],
    queryFn: async () => {
      const { data, error } = await supabase.from('subtasks').select('*').order('position');
      if (error) throw error;
      return (data ?? []) as Subtask[];
    },
  });

  const tasks: TaskWithDetail[] = rawTasks.map((task) => {
    const tagIds = taskTags.filter((tt) => tt.task_id === task.id).map((tt) => tt.tag_id);
    const taskTagList = tags.filter((tag) => tagIds.includes(tag.id));
    const aIds = taskAssignees.filter((ta) => ta.task_id === task.id).map((ta) => ta.assignee_id);
    const assigneeList: TaskAssignee[] = aIds
      .map((aId) => members.find((m) => m.id === aId))
      .filter(Boolean)
      .map((m) => ({ id: m!.id, name: m!.name, initials: m!.initials, color: m!.color, avatar_url: m!.avatar_url || null }));
    const taskSubtasks = allSubtasks.filter((s) => s.task_id === task.id);
    return { ...task, tags: taskTagList, assignee_ids: aIds, assignees: assigneeList, subtasks: taskSubtasks };
  });

  const { evaluateRules } = useRuleEngine(members);

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

    const assigneeSub = supabase
      .channel('task-assignees-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'task_assignees' }, () => {
        qc.invalidateQueries({ queryKey: ['task_assignees'] });
      })
      .subscribe();

    const subtasksSub = supabase
      .channel('subtasks-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'subtasks' }, () => {
        qc.invalidateQueries({ queryKey: ['subtasks'] });
      })
      .subscribe();

    return () => {
      supabase.removeChannel(tasksSub);
      supabase.removeChannel(tagsSub);
      supabase.removeChannel(assigneeSub);
      supabase.removeChannel(subtasksSub);
    };
  }, [qc]);

  const createTask = useMutation({
    mutationFn: async (task: {
      title: string;
      column?: TaskColumn;
      priority?: Database['public']['Enums']['task_priority'];
      assignee_ids?: string[];
      assignee_id?: string | null;
      due_date?: string | null;
      description?: string | null;
      created_by?: string | null;
      tag_ids?: string[];
      recurrence?: string | null;
      brief?: string | null;
      visibility?: Database['public']['Enums']['task_visibility'];
      participant_ids?: string[];
    }) => {
      const column = task.column || 'todo';
      const { data: maxPos } = await supabase
        .from('tasks')
        .select('position')
        .eq('column', column)
        .eq('archived', false)
        .order('position', { ascending: false })
        .limit(1)
        .single();

      const position = (maxPos?.position ?? -1) + 1;
      const primaryAssignee = task.assignee_ids?.[0] || task.assignee_id || null;

      // Private tasks: auto-include creator and all assignees in participants
      // so they can still see and interact with the task.
      const assigneesForParticipants = task.assignee_ids || (task.assignee_id ? [task.assignee_id] : []);
      const participantIds =
        task.visibility === 'private'
          ? Array.from(
              new Set([
                ...(task.participant_ids || []),
                ...(task.created_by ? [task.created_by] : []),
                ...assigneesForParticipants,
              ]),
            )
          : [];

      const insertPayload: Record<string, any> = {
        title: task.title,
        column,
        priority: task.priority || 'med',
        position,
        assignee_id: primaryAssignee,
        due_date: task.due_date || null,
        description: task.description || null,
        created_by: task.created_by || null,
        recurrence: task.recurrence || null,
        brief: task.brief || null,
      };
      // Only send privacy fields when actually needed — lets public task
      // creation work even before the privacy migration has been applied.
      if (task.visibility === 'private') {
        insertPayload.visibility = 'private';
        insertPayload.participant_ids = participantIds;
      }
      const { data: newTask, error } = await supabase
        .from('tasks')
        .insert(insertPayload as any)
        .select('id')
        .single();
      if (error) throw error;

      if (task.tag_ids && task.tag_ids.length > 0 && newTask) {
        await supabase.from('task_tags').insert(
          task.tag_ids.map((tag_id) => ({ task_id: newTask.id, tag_id }))
        );
      }

      // Insert multiple assignees
      const assigneeIds = task.assignee_ids || (task.assignee_id ? [task.assignee_id] : []);
      if (assigneeIds.length > 0 && newTask) {
        await supabase.from('task_assignees').insert(
          assigneeIds.map((assignee_id) => ({ task_id: newTask.id, assignee_id }))
        );
      }

      // Send notification to all assignees. For private tasks, only notify
      // assignees who are participants (otherwise they can't see the task
      // the notification references, and the title would leak).
      const isPrivate = task.visibility === 'private';
      const allowedForNotify = new Set(participantIds);
      for (const aId of assigneeIds) {
        if (isPrivate && !allowedForNotify.has(aId)) continue;
        const assigneeMember = members.find((m) => m.id === aId);
        if (assigneeMember) {
          await supabase.from('notifications').insert({
            user_id: assigneeMember.user_id,
            message: `You were assigned "${task.title}"`,
            task_id: newTask?.id || null,
          } as any);
        }
      }

      // Evaluate automation rules
      if (newTask) {
        const createdTask: TaskWithDetail = {
          id: newTask.id, title: task.title, column, priority: task.priority || 'med',
          position, due_date: task.due_date || null, description: task.description || null,
          created_at: null, updated_at: null, created_by: task.created_by || null,
          category_id: null, category_name: null, category_color: null,
          assignee_id: primaryAssignee, assignee_name: null, assignee_initials: null,
          assignee_color: null, assignee_avatar_url: null, project: null,
          tags: [], recurrence: task.recurrence || null, brief: task.brief || null,
          completed_at: null, assignee_ids: assigneeIds, assignees: [],
          visibility: task.visibility || 'team', participant_ids: participantIds,
        };
        evaluateRules({ type: 'task_created', task: createdTask });
        if (primaryAssignee) {
          evaluateRules({ type: 'task_assigned', task: createdTask, newAssigneeId: primaryAssignee });
        }
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['tasks'] });
      qc.invalidateQueries({ queryKey: ['task_tags'] });
      qc.invalidateQueries({ queryKey: ['task_assignees'] });
    },
  });

  const updateTask = useMutation({
    mutationFn: async ({ id, tag_ids, assignee_ids, ...updates }: {
      id: string;
      tag_ids?: string[];
      assignee_ids?: string[];
    } & Partial<{
      title: string;
      priority: Database['public']['Enums']['task_priority'];
      assignee_id: string | null;
      due_date: string | null;
      description: string | null;
      recurrence: string | null;
      brief: string | null;
    }>) => {
      // If assignee_ids provided, update primary assignee too
      if (assignee_ids !== undefined) {
        updates.assignee_id = assignee_ids[0] || null;
      }

      if (Object.keys(updates).length > 0) {
        const { error } = await supabase.from('tasks').update(updates as any).eq('id', id);
        if (error) throw error;
      }

      if (tag_ids !== undefined) {
        await supabase.from('task_tags').delete().eq('task_id', id);
        if (tag_ids.length > 0) {
          await supabase.from('task_tags').insert(
            tag_ids.map((tag_id) => ({ task_id: id, tag_id }))
          );
        }
      }

      if (assignee_ids !== undefined) {
        await supabase.from('task_assignees').delete().eq('task_id', id);
        if (assignee_ids.length > 0) {
          await supabase.from('task_assignees').insert(
            assignee_ids.map((assignee_id) => ({ task_id: id, assignee_id }))
          );
        }
      }

      // Notifications for new assignees
      const task = tasks.find((t) => t.id === id);
      if (assignee_ids && task) {
        // For private tasks, auto-add new assignees to participants so the
        // notification target can actually see the task, and don't notify
        // anyone who isn't a participant.
        if (task.visibility === 'private') {
          const nextParticipants = Array.from(
            new Set([...(task.participant_ids || []), ...assignee_ids]),
          );
          await supabase
            .from('tasks')
            .update({ participant_ids: nextParticipants } as any)
            .eq('id', id);
        }
        const allowedSet = new Set(
          task.visibility === 'private'
            ? [...(task.participant_ids || []), ...assignee_ids]
            : assignee_ids,
        );
        const newAssignees = assignee_ids.filter((aId) => !task.assignee_ids.includes(aId));
        for (const aId of newAssignees) {
          if (!allowedSet.has(aId)) continue;
          const m = members.find((m) => m.id === aId);
          if (m) {
            await supabase.from('notifications').insert({
              user_id: m.user_id,
              message: `You were assigned "${task.title}"`,
              task_id: id,
            } as any);
          }
          // Rule engine
          evaluateRules({ type: 'task_assigned', task: { ...task, assignee_ids }, newAssigneeId: aId });
        }
      }

      // Tag added rules
      if (tag_ids && task) {
        const oldTagIds = (task.tags || []).map(t => t.id);
        const newTags = tag_ids.filter(tId => !oldTagIds.includes(tId));
        for (const tId of newTags) {
          evaluateRules({ type: 'tag_added', task, newTagId: tId });
        }
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['tasks'] });
      qc.invalidateQueries({ queryKey: ['task_tags'] });
      qc.invalidateQueries({ queryKey: ['task_assignees'] });
    },
  });

  const archiveTask = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('tasks')
        .update({ archived: true, archived_at: new Date().toISOString() } as any)
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks'] }),
  });

  const restoreTask = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('tasks')
        .update({ archived: false, archived_at: null } as any)
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks'] }),
  });

  const permanentlyDeleteTask = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('tasks').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks'] }),
  });

  const moveTask = useMutation({
    mutationFn: async ({ taskId, column, position, priority }: { taskId: string; column: TaskColumn; position: number; priority?: Database['public']['Enums']['task_priority'] }) => {
      // Set completed_at when moving to done, clear when moving out
      if (column === 'done') {
        await supabase.from('tasks').update({ completed_at: new Date().toISOString() } as any).eq('id', taskId);
      } else {
        const task = tasks.find((t) => t.id === taskId);
        if (task?.column === 'done') {
          await supabase.from('tasks').update({ completed_at: null } as any).eq('id', taskId);
        }
      }

      const { error } = await supabase.rpc('reorder_task', {
        p_task_id: taskId,
        p_column: column,
        p_position: position,
      });
      if (error) throw error;

      // Apply priority change in the same move (e.g. drop on a priority-row cell)
      if (priority) {
        await supabase.from('tasks').update({ priority } as any).eq('id', taskId);
      }

      const task = tasks.find((t) => t.id === taskId);

      // Handle recurring task regeneration when moved to done
      if (column === 'done' && task) {
        if (task.recurrence && task.due_date) {
          const nextDue = calcNextDueDate(task.due_date, task.recurrence);
          const tagIds = taskTags.filter((tt) => tt.task_id === taskId).map((tt) => tt.tag_id);

          const { data: maxPos } = await supabase
            .from('tasks')
            .select('position')
            .eq('column', 'todo')
            .eq('archived', false)
            .order('position', { ascending: false })
            .limit(1)
            .single();

          const { data: newTask } = await supabase.from('tasks').insert({
            title: task.title,
            column: 'todo',
            priority: task.priority,
            position: (maxPos?.position ?? -1) + 1,
            assignee_id: task.assignee_id || null,
            due_date: nextDue,
            description: task.description || null,
            created_by: task.created_by || null,
            recurrence: task.recurrence,
            brief: task.brief || null,
          } as any).select('id').single();

          if (newTask && tagIds.length > 0) {
            await supabase.from('task_tags').insert(
              tagIds.map((tag_id) => ({ task_id: newTask.id, tag_id }))
            );
          }
          // Copy assignees to new task
          if (newTask && task.assignee_ids.length > 0) {
            await supabase.from('task_assignees').insert(
              task.assignee_ids.map((assignee_id) => ({ task_id: newTask.id, assignee_id }))
            );
          }
        }

        // Rule engine: task completed
        if (task) {
          evaluateRules({ type: 'task_completed', task });
        }
      }

      // Rule engine: task moved
      if (task) {
        evaluateRules({ type: 'task_moved', task, newColumn: column });
      }
    },
    onMutate: async ({ taskId, column, position, priority }) => {
      await qc.cancelQueries({ queryKey: ['tasks'] });
      await qc.cancelQueries({ queryKey: ['task_tags'] });
      const previousTasks = qc.getQueryData<TaskWithDetail[]>(['tasks']) ?? [];

      qc.setQueryData<TaskWithDetail[]>(['tasks'], (oldTasks = []) => {
        const moved = moveTaskOptimistically(oldTasks, taskId, column, position);
        return priority
          ? moved.map((t) => (t.id === taskId ? { ...t, priority } : t))
          : moved;
      });

      return { previousTasks };
    },
    onError: (_error, _variables, context) => {
      if (context?.previousTasks) {
        qc.setQueryData(['tasks'], context.previousTasks);
      }
    },
    onSettled: () => {
      setTimeout(() => {
        qc.invalidateQueries({ queryKey: ['tasks'] });
        qc.invalidateQueries({ queryKey: ['task_tags'] });
        qc.invalidateQueries({ queryKey: ['task_assignees'] });
      }, 300);
    },
  });

  const createTag = useMutation({
    mutationFn: async (name: string) => {
      const { data, error } = await supabase.from('tags').insert({ name }).select('id').single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tags'] }),
  });

  const updateTag = useMutation({
    mutationFn: async ({ id, ...updates }: { id: string; name?: string; color?: string }) => {
      const { error } = await supabase.from('tags').update(updates as any).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tags'] }),
  });

  const deleteTag = useMutation({
    mutationFn: async (id: string) => {
      await supabase.from('task_tags').delete().eq('tag_id', id);
      const { error } = await supabase.from('tags').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['tags'] });
      qc.invalidateQueries({ queryKey: ['task_tags'] });
    },
  });

  return {
    tasks,
    tags,
    members,
    isLoading,
    createTask,
    updateTask,
    archiveTask,
    restoreTask,
    permanentlyDeleteTask,
    moveTask,
    createTag,
    updateTag,
    deleteTag,
  };
}
