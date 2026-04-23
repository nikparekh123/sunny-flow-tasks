import type { Database } from '@/integrations/supabase/types';

type TaskColumn = Database['public']['Enums']['task_column'];

export const COLUMNS: { id: TaskColumn; label: string; color: string; sub?: string }[] = [
  { id: 'backlog', label: 'Backlog', color: '#468278', sub: 'unscheduled' },
  { id: 'todo', label: 'Todo', color: '#378ADD', sub: 'ready' },
  { id: 'inprogress', label: 'In progress', color: '#EF9F27', sub: 'in-flight' },
  { id: 'review', label: 'Review', color: '#7F77DD', sub: 'needs eyes' },
  { id: 'done', label: 'Done', color: '#639922', sub: 'this week' },
];

export const PRIORITIES: { id: 'high' | 'med' | 'low'; label: string; glyph: string; sub: string }[] = [
  { id: 'high', label: 'High', glyph: '!!', sub: 'ship first' },
  { id: 'med',  label: 'Med',  glyph: '=',  sub: 'this sprint' },
  { id: 'low',  label: 'Low',  glyph: '·',  sub: 'nice to have' },
];

export const COLUMN_ORDER: TaskColumn[] = ['backlog', 'todo', 'inprogress', 'review', 'done'];

// A card can move to the next step in the workflow, or jump straight to Done
// from any stage (handy when a task is finished without needing review).
export function canMoveColumn(from: TaskColumn, to: TaskColumn): boolean {
  if (from === to) return true;
  if (to === 'done') return true;
  const fromIdx = COLUMN_ORDER.indexOf(from);
  const toIdx = COLUMN_ORDER.indexOf(to);
  if (fromIdx < 0 || toIdx < 0) return false;
  return toIdx === fromIdx + 1;
}

export const PRIORITY_COLORS: Record<string, string> = {
  high: '#d2e632',
  med: '#EF9F27',
  low: '#639922',
};

export const CATEGORY_COLOR_SEQUENCE = [
  '#D85A30', '#7F77DD', '#1D9E75', '#EF9F27',
  '#E24B4A', '#888780', '#378ADD', '#5DCAA5',
];

export type TaskProject = 'admin_ops' | 'sector_research' | 'macro_research' | 'company_research' | 'technical_setup' | 'live_positions';

export const PROJECTS: { id: TaskProject; label: string }[] = [
  { id: 'admin_ops', label: 'Admin & Operations' },
  { id: 'sector_research', label: 'Sector Research' },
  { id: 'macro_research', label: 'Macro Research' },
  { id: 'company_research', label: 'Company Research' },
  { id: 'technical_setup', label: 'Technical Setup' },
  { id: 'live_positions', label: 'Live Positions' },
];
