import type { Database } from '@/integrations/supabase/types';

type TaskColumn = Database['public']['Enums']['task_column'];

export const COLUMNS: { id: TaskColumn; label: string; color: string }[] = [
  { id: 'todo', label: 'To Do', color: '#378ADD' },
  { id: 'inprogress', label: 'In Progress', color: '#EF9F27' },
  { id: 'review', label: 'Review', color: '#7F77DD' },
  { id: 'done', label: 'Done', color: '#639922' },
];

export const PRIORITY_COLORS: Record<string, string> = {
  high: '#E24B4A',
  med: '#EF9F27',
  low: '#639922',
};

export const CATEGORY_COLOR_SEQUENCE = [
  '#D85A30', '#7F77DD', '#1D9E75', '#EF9F27',
  '#E24B4A', '#888780', '#378ADD', '#5DCAA5',
];
