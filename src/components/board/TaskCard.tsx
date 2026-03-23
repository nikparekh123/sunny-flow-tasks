import { useState } from 'react';
import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { MoreHorizontal } from 'lucide-react';
import { format, isPast, parseISO } from 'date-fns';
import { PRIORITY_COLORS } from '@/lib/constants';
import type { TaskWithDetail } from '@/lib/types';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';

interface Props {
  task: TaskWithDetail;
  isDone: boolean;
  onClick: () => void;
  onEdit: () => void;
  onDelete: () => void;
}

function getCategoryPillStyles(color: string) {
  return {
    backgroundColor: `${color}1a`,
    color: color,
  };
}

export function TaskCard({ task, isDone, onClick, onEdit, onDelete }: Props) {
  const [menuOpen, setMenuOpen] = useState(false);

  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: task.id, data: { task } });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : isDone ? 0.55 : 1,
  };

  const isOverdue = task.due_date && isPast(parseISO(task.due_date)) && !isDone;

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...attributes}
      {...listeners}
      className="group relative bg-card rounded-lg p-3 cursor-grab active:cursor-grabbing"
      onClick={(e) => {
        if (!menuOpen) onClick();
      }}
      role="button"
      tabIndex={0}
    >
      {/* Card border via box-shadow to avoid layout shift */}
      <div className="absolute inset-0 rounded-lg border border-[hsl(var(--card-border))] group-hover:border-[hsl(var(--card-border-hover))] pointer-events-none" />

      {/* Priority dot */}
      <div
        className="absolute top-3 right-3 w-2 h-2 rounded-full"
        style={{ backgroundColor: PRIORITY_COLORS[task.priority] }}
      />

      {/* Menu */}
      <div className="absolute top-2 right-7 opacity-0 group-hover:opacity-100 transition-opacity">
        <DropdownMenu open={menuOpen} onOpenChange={setMenuOpen}>
          <DropdownMenuTrigger asChild onClick={(e) => e.stopPropagation()}>
            <button className="p-0.5 text-muted-foreground hover:text-foreground">
              <MoreHorizontal className="w-3.5 h-3.5" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-24">
            <DropdownMenuItem className="text-xs" onClick={(e) => { e.stopPropagation(); onEdit(); }}>
              Edit
            </DropdownMenuItem>
            <DropdownMenuItem className="text-xs text-destructive" onClick={(e) => { e.stopPropagation(); onDelete(); }}>
              Delete
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      {/* Title */}
      <p className={`text-xs font-medium leading-[1.4] pr-6 ${isDone ? 'line-through' : ''}`}>
        {task.title}
      </p>

      {/* Category pill */}
      {task.category_name && task.category_color && (
        <span
          className="inline-block mt-1.5 px-1.5 py-0.5 rounded text-[10px] font-medium"
          style={getCategoryPillStyles(task.category_color)}
        >
          {task.category_name}
        </span>
      )}

      {/* Footer */}
      {(task.due_date || task.assignee_initials) && (
        <div className="flex items-center justify-between mt-2">
          {task.due_date ? (
            <span className={`text-[10px] ${isOverdue ? 'text-destructive font-medium' : 'text-muted-foreground'}`}>
              {format(parseISO(task.due_date), 'MMM d')}
              {isOverdue && ' — overdue'}
            </span>
          ) : <span />}
          {task.assignee_initials && (
            <div
              className="w-5 h-5 rounded-full flex items-center justify-center text-[8px] font-medium text-primary-foreground"
              style={{ backgroundColor: task.assignee_color || '#378ADD' }}
            >
              {task.assignee_initials}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
