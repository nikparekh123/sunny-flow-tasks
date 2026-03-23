import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { TaskCard } from './TaskCard';
import type { TaskWithDetail, TaskColumn } from '@/lib/types';

interface Props {
  id: TaskColumn;
  label: string;
  color: string;
  tasks: TaskWithDetail[];
  onCardClick: (task: TaskWithDetail) => void;
  onCardEdit: (task: TaskWithDetail) => void;
  onCardDelete: (taskId: string) => void;
}

export function BoardColumn({ id, label, color, tasks, onCardClick, onCardEdit, onCardDelete }: Props) {
  const { setNodeRef, isOver } = useDroppable({ id });
  const isDone = id === 'done';

  return (
    <div
      className={`w-72 flex-shrink-0 rounded-xl p-3 bg-card border border-border transition-colors ${isOver ? 'ring-1 ring-ring' : ''}`}
    >
      {/* Column header */}
      <div className="flex items-center gap-2 px-1 mb-3">
        <div className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: color }} />
        <span className="text-xs font-medium text-muted-foreground">{label}</span>
        <span className="ml-auto px-1.5 py-0.5 rounded-full bg-secondary text-[10px] text-muted-foreground font-medium">
          {tasks.length}
        </span>
      </div>

      {/* Droppable area */}
      <div
        ref={setNodeRef}
        className="space-y-2 min-h-[60px]"
      >
        <SortableContext items={tasks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
          {tasks.map((task) => (
            <TaskCard
              key={task.id}
              task={task}
              isDone={isDone}
              onClick={() => onCardClick(task)}
              onEdit={() => onCardEdit(task)}
              onDelete={() => onCardDelete(task.id)}
            />
          ))}
        </SortableContext>
      </div>
    </div>
  );
}
