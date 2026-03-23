import { useState } from 'react';
import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { Input } from '@/components/ui/input';
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
  onQuickAdd?: (title: string) => void;
}

export function BoardColumn({ id, label, color, tasks, onCardClick, onCardEdit, onCardDelete, onQuickAdd }: Props) {
  const [quickAddTitle, setQuickAddTitle] = useState('');
  const [showQuickAdd, setShowQuickAdd] = useState(false);

  const { setNodeRef, isOver } = useDroppable({ id });
  const isDone = id === 'done';

  const handleQuickAdd = () => {
    if (quickAddTitle.trim()) {
      onQuickAdd?.(quickAddTitle.trim());
      setQuickAddTitle('');
      setShowQuickAdd(false);
    }
  };

  return (
    <div className="flex-1 min-w-[260px] max-w-[320px]">
      {/* Column header */}
      <div className="flex items-center gap-2 px-1 mb-3">
        <div className="w-2 h-2 rounded-full" style={{ backgroundColor: color }} />
        <span className="text-xs font-medium text-muted-foreground">{label}</span>
        <span className="ml-auto px-1.5 py-0.5 rounded-full bg-secondary text-[10px] text-muted-foreground font-medium">
          {tasks.length}
        </span>
      </div>

      {/* Droppable area */}
      <div
        ref={setNodeRef}
        className={`space-y-2 min-h-[100px] rounded-lg p-1 transition-colors ${
          isOver ? 'bg-secondary/50' : ''
        }`}
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

      {/* Quick add - only To Do */}
      {id === 'todo' && (
        <div className="mt-2 px-1">
          {showQuickAdd ? (
            <Input
              autoFocus
              value={quickAddTitle}
              onChange={(e) => setQuickAddTitle(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleQuickAdd();
                if (e.key === 'Escape') { setShowQuickAdd(false); setQuickAddTitle(''); }
              }}
              onBlur={() => { if (!quickAddTitle.trim()) setShowQuickAdd(false); }}
              placeholder="Task title..."
              className="text-xs h-7"
            />
          ) : (
            <button
              onClick={() => setShowQuickAdd(true)}
              className="text-[11px] text-muted-foreground hover:text-foreground w-full text-left py-1"
            >
              + Add task
            </button>
          )}
        </div>
      )}
    </div>
  );
}
