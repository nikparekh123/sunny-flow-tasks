import type { Database } from '@/integrations/supabase/types';
import type { TaskProject } from '@/lib/constants';

export type TaskColumn = Database['public']['Enums']['task_column'];
export type TaskPriority = Database['public']['Enums']['task_priority'];
export type MemberRole = Database['public']['Enums']['member_role'];
export type { TaskProject } from '@/lib/constants';

export interface Tag {
  id: string;
  name: string;
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
  project: TaskProject | null;
  tags?: Tag[];
}

export interface TeamMember {
  id: string;
  user_id: string;
  name: string;
  initials: string;
  color: string | null;
  role: MemberRole;
}

export interface TaskCategory {
  id: string;
  name: string;
  color: string;
  position: number | null;
}
