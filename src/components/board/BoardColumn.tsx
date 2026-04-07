import { useState } from 'react';
import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { TaskCard } from './TaskCard';
import { Button } from '@/components/ui/button';
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
  const PAGE_SIZE = 20;
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE);

  const sortedTasks = isDone
    ? [...tasks].sort((a, b) => {
        const aDate = a.completed_at ? new Date(a.completed_at).getTime() : 0;
        const bDate = b.completed_at ? new Date(b.completed_at).getTime() : 0;
        return bDate - aDate;
      })
    : tasks;

  const displayedTasks = isDone ? sortedTasks.slice(0, visibleCount) : sortedTasks;
  const hasMore = isDone && visibleCount < sortedTasks.length;

  return (
    <div
      className={`min-w-[240px] lg:min-w-0 rounded-xl p-3 transition-all duration-200 h-[calc(100vh-132px)] flex flex-col ${
        isOver ? 'bg-accent/20' : ''
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
        <span className="text-sm font-semibold" style={{ color: 'var(--owl-text-primary)' }}>{label}</span>
        <span
          className="ml-auto px-1.5 py-0.5 rounded-full text-[11px] font-medium"
          style={{ backgroundColor: 'var(--owl-card)', color: 'var(--owl-text-muted)' }}
        >
          {tasks.length}
        </span>
      </div>

      <div
        ref={setNodeRef}
        className="space-y-3 min-h-[60px] flex-1 overflow-y-auto pr-1 transition-all duration-200"
      >
        <SortableContext items={displayedTasks.map((task) => task.id)} strategy={verticalListSortingStrategy}>
          {displayedTasks.map((task) => (
            <TaskCard
              key={task.id}
              task={task}
              isDone={isDone}
              onClick={() => onCardClick(task)}
              onEdit={() => onCardEdit(task)}
              onDelete={() => onCardDelete(task.id)}
              columnLabel={label}
              columnColor={color}
            />
          ))}
        </SortableContext>

        {hasMore && (
          <Button
            variant="ghost"
            size="sm"
            className="w-full text-[11px] h-7"
            style={{ color: 'var(--owl-text-muted)' }}
            onClick={() => setVisibleCount((prev) => prev + PAGE_SIZE)}
          >
            See more ({sortedTasks.length - visibleCount} remaining)
          </Button>
        )}

        {tasks.length === 0 && isOver && (
          <div
            className="rounded-lg h-16 flex items-center justify-center animate-scale-in"
            style={{ border: '2px dashed var(--owl-border-mid)' }}
          >
            <span style={{ fontSize: '11px', color: 'var(--owl-text-muted)' }}>Drop here</span>
          </div>
        )}
      </div>
    </div>
  );
}
