import type { Database } from '@/integrations/supabase/types';
import type { TaskProject } from '@/lib/constants';

export type TaskColumn = Database['public']['Enums']['task_column'];
export type TaskPriority = Database['public']['Enums']['task_priority'];
export type MemberRole = Database['public']['Enums']['member_role'];
export type { TaskProject } from '@/lib/constants';

export type RecurrenceFrequency = 'daily' | 'weekly' | 'biweekly' | 'monthly' | 'custom';

export interface CustomRecurrenceConfig {
  days?: string[]; // 'mon','tue','wed','thu','fri','sat','sun'
  dayOfMonth?: number;
}

export interface Tag {
  id: string;
  name: string;
  color?: string;
}

export interface TaskAssignee {
  id: string;
  name: string;
  initials: string;
  color: string | null;
  avatar_url: string | null;
}

export interface TaskWithDetail {
  id: string;
  title: string;
  description: string | null;
  column: TaskColumn;
  priority: TaskPriority;
  position: number;
  due_date: string | null;
  created_at: string | null;
  updated_at: string | null;
  created_by: string | null;
  category_id: string | null;
  category_name: string | null;
  category_color: string | null;
  assignee_id: string | null;
  assignee_name: string | null;
  assignee_initials: string | null;
  assignee_color: string | null;
  assignee_avatar_url: string | null;
  project: TaskProject | null;
  tags?: Tag[];
  recurrence: string | null;
  brief: string | null;
  completed_at: string | null;
  assignee_ids: string[];
  assignees: TaskAssignee[];
  subtasks?: Subtask[];
}

export interface TeamMember {
  id: string;
  user_id: string;
  name: string;
  initials: string;
  color: string | null;
  role: MemberRole;
  avatar_url?: string | null;
}

export interface TaskCategory {
  id: string;
  name: string;
  color: string;
  position: number | null;
}

export interface AutomationRule {
  id: string;
  name: string;
  trigger_type: string;
  trigger_config: Record<string, any>;
  action_type: string;
  action_config: Record<string, any>;
  active: boolean;
  created_by: string | null;
  created_at: string;
}

export interface Subtask {
  id: string;
  task_id: string;
  title: string;
  done: boolean;
  assignee_id: string | null;
  position: number;
  created_at: string;
}

export interface Notification {
  id: string;
  user_id: string;
  message: string;
  task_id: string | null;
  read: boolean;
  created_at: string;
}
