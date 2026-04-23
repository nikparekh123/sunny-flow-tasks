import { useMemo, useState } from 'react';
import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { COLUMNS } from '@/lib/constants';
import { TaskCard } from './TaskCard';
import type { TaskWithDetail, TaskColumn } from '@/lib/types';

interface Props {
  tasks: TaskWithDetail[];
  onCardClick: (task: TaskWithDetail) => void;
  onCardEdit: (task: TaskWithDetail) => void;
  onCardDelete: (taskId: string) => void;
  overCellId: string | null;
}

const PRIORITY_ORDER: Record<string, number> = { high: 0, med: 1, low: 2 };

export function PriorityGrid({ tasks, onCardClick, onCardEdit, onCardDelete, overCellId }: Props) {
  const byColumn = useMemo(() => {
    const map: Record<string, TaskWithDetail[]> = {};
    COLUMNS.forEach((c) => (map[c.id] = []));
    tasks.forEach((t) => {
      (map[t.column] ||= []).push(t);
    });
    Object.entries(map).forEach(([col, list]) => {
      if (col === 'done') {
        list.sort((a, b) => {
          const aD = a.completed_at ? new Date(a.completed_at).getTime() : 0;
          const bD = b.completed_at ? new Date(b.completed_at).getTime() : 0;
          return bD - aD;
        });
      } else {
        list.sort((a, b) => {
          const pa = PRIORITY_ORDER[a.priority] ?? 3;
          const pb = PRIORITY_ORDER[b.priority] ?? 3;
          if (pa !== pb) return pa - pb;
          return a.position - b.position;
        });
      }
    });
    return map;
  }, [tasks]);

  const totalActive = tasks.filter((t) => t.column !== 'done').length || 1;

  return (
    <div className="overflow-x-auto pb-1">
      <div
        className="grid gap-[10px] w-full"
        style={{ gridTemplateColumns: `repeat(${COLUMNS.length}, minmax(220px, 1fr))` }}
      >
        {COLUMNS.map((col) => {
          const colTasks = byColumn[col.id] ?? [];
          const isDone = col.id === 'done';
          const pct = Math.round((colTasks.length / totalActive) * 100);
          return (
            <div key={col.id} className="flex flex-col gap-2">
              {/* Column header */}
              <div className="flex flex-col gap-[3px] px-[4px] pt-2 pb-[8px]">
                <div
                  className="flex items-center gap-2 text-[9px] font-semibold uppercase tracking-[2px]"
                  style={{ color: isDone ? 'var(--owl-positive)' : 'var(--owl-text-muted)' }}
                >
                  {col.label}
                  <span className="flex-1 h-px" style={{ background: 'var(--owl-line)' }} />
                </div>
                <div className="flex items-baseline justify-between gap-2">
                  <div
                    className="text-base font-medium tracking-tight"
                    style={{
                      fontFamily: 'var(--owl-font-mono)',
                      color: isDone ? 'var(--owl-positive)' : 'var(--owl-text-secondary)',
                    }}
                  >
                    {colTasks.length}
                  </div>
                  <div
                    className="text-[10px]"
                    style={{ fontFamily: 'var(--owl-font-mono)', color: 'var(--owl-text-label)' }}
                  >
                    {col.sub ?? ''}
                  </div>
                </div>
                <div
                  className="h-[3px] rounded-sm mt-[6px] overflow-hidden"
                  style={{ background: 'rgba(15,51,51,0.8)' }}
                >
                  <span
                    className="block h-full rounded-sm"
                    style={{
                      width: `${Math.min(100, pct)}%`,
                      background: isDone ? 'var(--owl-positive)' : 'var(--owl-elevated)',
                    }}
                  />
                </div>
              </div>

              <Column
                id={col.id}
                tasks={colTasks}
                isOver={overCellId === col.id}
                isDone={isDone}
                onCardClick={onCardClick}
                onCardEdit={onCardEdit}
                onCardDelete={onCardDelete}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
}

interface ColumnProps {
  id: TaskColumn;
  tasks: TaskWithDetail[];
  isOver: boolean;
  isDone: boolean;
  onCardClick: (task: TaskWithDetail) => void;
  onCardEdit: (task: TaskWithDetail) => void;
  onCardDelete: (taskId: string) => void;
}

const COLUMN_LIMIT = 10;

function Column({ id, tasks, isOver, isDone, onCardClick, onCardEdit, onCardDelete }: ColumnProps) {
  const { setNodeRef } = useDroppable({ id, data: { column: id } });
  const isEmpty = tasks.length === 0;
  const [expanded, setExpanded] = useState(false);
  const visibleTasks =
    expanded || tasks.length <= COLUMN_LIMIT ? tasks : tasks.slice(0, COLUMN_LIMIT);
  const hiddenCount = tasks.length - visibleTasks.length;

  const baseStyle: React.CSSProperties = {
    minHeight: isEmpty ? 80 : 100,
    borderRadius: 10,
    padding: 6,
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    transition: 'background 0.15s, border-color 0.15s',
    border: isOver ? '1px solid var(--owl-neon)' : '1px dashed rgba(30,90,80,0.35)',
    background: isOver ? 'rgba(210,230,50,0.05)' : 'rgba(15,51,51,0.22)',
    alignItems: isEmpty ? 'center' : undefined,
    justifyContent: isEmpty ? 'center' : undefined,
  };

  return (
    <div ref={setNodeRef} style={baseStyle}>
      <SortableContext items={visibleTasks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
        {visibleTasks.map((task) => (
          <TaskCard
            key={task.id}
            task={task}
            isDone={task.column === 'done'}
            onClick={() => onCardClick(task)}
            onEdit={() => onCardEdit(task)}
            onDelete={() => onCardDelete(task.id)}
          />
        ))}
      </SortableContext>
      {hiddenCount > 0 && (
        <button
          onClick={() => setExpanded(true)}
          className="w-full rounded-md transition-colors"
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            color: 'var(--owl-text-muted)',
            background: 'transparent',
            border: '1px dashed var(--owl-line-bright)',
            padding: '5px 8px',
            cursor: 'pointer',
            letterSpacing: '0.3px',
          }}
          onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--owl-neon)')}
          onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--owl-text-muted)')}
        >
          +{hiddenCount} more
        </button>
      )}
      {expanded && tasks.length > COLUMN_LIMIT && (
        <button
          onClick={() => setExpanded(false)}
          className="w-full rounded-md transition-colors"
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            color: 'var(--owl-text-label)',
            background: 'transparent',
            border: 'none',
            padding: '3px 8px',
            cursor: 'pointer',
          }}
        >
          show less
        </button>
      )}
      {isEmpty && (
        <div
          className="text-center w-full px-2 py-4"
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            color: isDone ? 'var(--owl-positive)' : 'var(--owl-text-label)',
            opacity: isDone ? 0.6 : 1,
            letterSpacing: '0.5px',
          }}
        >
          {isDone ? '✓ cleared' : '— empty —'}
        </div>
      )}
    </div>
  );
}
