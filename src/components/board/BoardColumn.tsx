import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { TaskCard } from './TaskCard';
import type { TaskWithDetail, TaskColumn } from '@/lib/types';

interface Props {
  id: TaskColumn;
  label: string;
  color: string;
  tasks: TaskWithDetail[];
  isOver?: boolean;
  onCardClick: (task: TaskWithDetail) => void;
  onCardEdit: (task: TaskWithDetail) => void;
  onCardDelete: (taskId: string) => void;
}

export function BoardColumn({ id, label, color, tasks, isOver, onCardClick, onCardEdit, onCardDelete }: Props) {
  const { setNodeRef } = useDroppable({ id });
  const isDone = id === 'done';

  return (
    <div
      className={`min-w-[240px] lg:min-w-0 rounded-xl p-3 bg-card border transition-all duration-200 h-[calc(100vh-132px)] flex flex-col ${
        isOver
          ? 'border-ring/40 bg-accent/40 scale-[1.01]'
          : 'border-border'
      }`}
    >
      <div className="flex items-center gap-2 px-1 mb-3">
        <div
          className="w-2.5 h-2.5 rounded-full transition-transform duration-200"
          style={{
            backgroundColor: color,
            transform: isOver ? 'scale(1.25)' : 'scale(1)',
          }}
        />
        <span className="text-xs font-semibold text-foreground">{label}</span>
        <span className="ml-auto px-1.5 py-0.5 rounded-full bg-secondary text-[10px] text-muted-foreground font-medium">
          {tasks.length}
        </span>
      </div>

      <div
        ref={setNodeRef}
        className="space-y-2 min-h-[60px] flex-1 overflow-y-auto pr-1 transition-all duration-200"
      >
        <SortableContext items={tasks.map((task) => task.id)} strategy={verticalListSortingStrategy}>
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

        {tasks.length === 0 && isOver && (
          <div className="border-2 border-dashed border-ring/30 rounded-lg h-16 flex items-center justify-center animate-scale-in">
            <span className="text-[10px] text-muted-foreground">Drop here</span>
          </div>
        )}
      </div>
    </div>
  );
}
