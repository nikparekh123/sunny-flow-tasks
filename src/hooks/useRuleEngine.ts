import { useCallback, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { AutomationRule, TaskWithDetail, TeamMember } from '@/lib/types';

type TaskColumn = 'todo' | 'inprogress' | 'review' | 'done';

interface TriggerContext {
  type: 'task_created' | 'task_moved' | 'task_completed' | 'task_assigned' | 'tag_added';
  task: TaskWithDetail;
  newColumn?: TaskColumn;
  newAssigneeId?: string;
  newTagId?: string;
}

export function useRuleEngine(members: TeamMember[]) {
  const qc = useQueryClient();
  const executingRef = useRef(false);

  const evaluateRules = useCallback(async (context: TriggerContext) => {
    if (executingRef.current) return; // depth guard
    executingRef.current = true;

    try {
      const { data: rules } = await supabase
        .from('automation_rules')
        .select('*')
        .eq('active', true);

      if (!rules || rules.length === 0) {
        executingRef.current = false;
        return;
      }

      for (const rule of rules as unknown as AutomationRule[]) {
        const matched = matchTrigger(rule, context);
        if (!matched) continue;

        console.log(`[RuleEngine] Rule "${rule.name}" matched trigger "${context.type}" for task "${context.task.title}"`);

        try {
          await executeAction(rule, context.task, members);
          console.log(`[RuleEngine] Action "${rule.action_type}" executed for rule "${rule.name}"`);
        } catch (err) {
          console.error(`[RuleEngine] Failed to execute action for rule "${rule.name}":`, err);
        }
      }
    } catch (err) {
      console.error('[RuleEngine] Error fetching/evaluating rules:', err);
    } finally {
      executingRef.current = false;
      // Invalidate tasks after rule execution
      setTimeout(() => {
        qc.invalidateQueries({ queryKey: ['tasks'] });
        qc.invalidateQueries({ queryKey: ['task_tags'] });
      }, 500);
    }
  }, [members, qc]);

  return { evaluateRules };
}

function matchTrigger(rule: AutomationRule, ctx: TriggerContext): boolean {
  const { trigger_type, trigger_config } = rule;

  switch (trigger_type) {
    case 'task_created':
      return ctx.type === 'task_created';

    case 'task_moved':
      if (ctx.type !== 'task_moved') return false;
      return !trigger_config.column || trigger_config.column === ctx.newColumn;

    case 'task_completed':
      return ctx.type === 'task_completed';

    case 'task_assigned':
      if (ctx.type !== 'task_assigned' && ctx.type !== 'task_created') return false;
      return !trigger_config.member_id || trigger_config.member_id === ctx.newAssigneeId;

    case 'task_overdue':
      // This would need a cron job; skip for client-side
      return false;

    case 'tag_added':
      if (ctx.type !== 'tag_added') return false;
      return !trigger_config.tag_id || trigger_config.tag_id === ctx.newTagId;

    default:
      return false;
  }
}

async function executeAction(rule: AutomationRule, task: TaskWithDetail, members: TeamMember[]) {
  const { action_type, action_config } = rule;

  switch (action_type) {
    case 'assign_user': {
      if (!action_config.member_id) break;
      // Add to task_assignees
      await supabase.from('task_assignees').upsert({
        task_id: task.id,
        assignee_id: action_config.member_id,
      } as any);
      // Also update primary assignee
      await supabase.from('tasks').update({ assignee_id: action_config.member_id } as any).eq('id', task.id);
      break;
    }

    case 'move_to_column': {
      if (!action_config.column) break;
      await supabase.rpc('reorder_task', {
        p_task_id: task.id,
        p_column: action_config.column,
        p_position: 0,
      });
      break;
    }

    case 'add_tag': {
      if (!action_config.tag_id) break;
      await supabase.from('task_tags').upsert({
        task_id: task.id,
        tag_id: action_config.tag_id,
      } as any);
      break;
    }

    case 'send_notification': {
      const message = action_config.message || `Rule "${rule.name}" triggered for "${task.title}"`;
      // Send to all assignees
      const assigneeIds = task.assignee_ids || (task.assignee_id ? [task.assignee_id] : []);
      for (const aId of assigneeIds) {
        const member = members.find((m) => m.id === aId);
        if (member) {
          await supabase.from('notifications').insert({
            user_id: member.user_id,
            message,
            task_id: task.id,
          } as any);
        }
      }
      break;
    }

    case 'remove_assignee': {
      await supabase.from('task_assignees').delete().eq('task_id', task.id);
      await supabase.from('tasks').update({ assignee_id: null } as any).eq('id', task.id);
      break;
    }

    case 'set_due_date': {
      if (!action_config.days_from_now) break;
      const d = new Date();
      d.setDate(d.getDate() + Number(action_config.days_from_now));
      const formatted = d.toISOString().split('T')[0];
      await supabase.from('tasks').update({ due_date: formatted } as any).eq('id', task.id);
      break;
    }

    default:
      console.warn(`[RuleEngine] Unknown action type: ${action_type}`);
  }
}
