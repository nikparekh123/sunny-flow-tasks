import { useMemo, useState } from 'react';
import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { COLUMNS, PRIORITIES } from '@/lib/constants';
import { TaskCard } from './TaskCard';
import type { TaskWithDetail, TaskColumn, TaskPriority } from '@/lib/types';

interface Props {
  tasks: TaskWithDetail[];
  onCardClick: (task: TaskWithDetail) => void;
  onCardEdit: (task: TaskWithDetail) => void;
  onCardDelete: (taskId: string) => void;
  overCellId: string | null;
}

export function PriorityGrid({ tasks, onCardClick, onCardEdit, onCardDelete, overCellId }: Props) {
  const grouped = useMemo(() => {
    const map: Record<string, TaskWithDetail[]> = {};
    tasks.forEach((t) => {
      const key = `${t.priority}:${t.column}`;
      (map[key] ||= []).push(t);
    });
    Object.keys(map).forEach((k) => {
      if (k.endsWith(':done')) {
        map[k].sort((a, b) => {
          const aD = a.completed_at ? new Date(a.completed_at).getTime() : 0;
          const bD = b.completed_at ? new Date(b.completed_at).getTime() : 0;
          return bD - aD;
        });
      } else {
        map[k].sort((a, b) => a.position - b.position);
      }
    });
    return map;
  }, [tasks]);

  const columnCounts = useMemo(() => {
    const m: Record<string, number> = {};
    COLUMNS.forEach((c) => (m[c.id] = tasks.filter((t) => t.column === c.id).length));
    return m;
  }, [tasks]);

  const totalActive = tasks.filter((t) => t.column !== 'done').length || 1;

  return (
    <div className="overflow-x-auto pb-1">
      <div
        className="grid gap-[8px] min-w-[1120px]"
        style={{ gridTemplateColumns: '96px repeat(5, minmax(200px, 1fr))' }}
      >
        {/* Row 0: column headers */}
        <div style={{ borderBottom: 'none' }} />
        {COLUMNS.map((col) => {
          const pct = Math.round((columnCounts[col.id] / totalActive) * 100);
          const isDone = col.id === 'done';
          return (
            <div
              key={col.id}
              className="flex flex-col gap-[3px] px-[14px] pt-3 pb-[10px]"
              style={{ borderBottom: '1px solid var(--owl-line)' }}
            >
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
                  {columnCounts[col.id]}
                </div>
                <div
                  className="text-[10px]"
                  style={{ fontFamily: 'var(--owl-font-mono)', color: 'var(--owl-text-disabled)' }}
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
                    width: `${pct}%`,
                    background: isDone ? 'var(--owl-positive)' : 'var(--owl-elevated)',
                  }}
                />
              </div>
            </div>
          );
        })}

        {/* Priority rows */}
        {PRIORITIES.map((p) => {
          const color =
            p.id === 'high'
              ? 'var(--owl-negative)'
              : p.id === 'med'
              ? 'var(--owl-warning)'
              : 'var(--owl-text-muted)';
          return (
            <div key={p.id} className="contents">
              <div
                className="flex flex-col items-end text-right gap-[3px] py-3 pr-[10px] pl-[10px]"
                style={{ borderRight: '1px solid var(--owl-line)' }}
              >
                <div className="font-bold tracking-tight leading-none" style={{ fontSize: 22, color }}>
                  {p.glyph}
                </div>
                <div
                  className="text-[9px] font-semibold uppercase tracking-[2px]"
                  style={{ color }}
                >
                  {p.label}
                </div>
                <div
                  className="text-[10px] mt-px"
                  style={{ fontFamily: 'var(--owl-font-mono)', color: 'var(--owl-text-disabled)' }}
                >
                  {p.sub}
                </div>
              </div>
              {COLUMNS.map((col) => {
                const key = `${p.id}:${col.id}`;
                const cellTasks = grouped[key] ?? [];
                return (
                  <Cell
                    key={key}
                    id={key}
                    priority={p.id}
                    column={col.id}
                    isOver={overCellId === key}
                    isDone={col.id === 'done'}
                    isHigh={p.id === 'high'}
                    tasks={cellTasks}
                    onCardClick={onCardClick}
                    onCardEdit={onCardEdit}
                    onCardDelete={onCardDelete}
                  />
                );
              })}
            </div>
          );
        })}
      </div>
    </div>
  );
}

interface CellProps {
  id: string;
  priority: TaskPriority;
  column: TaskColumn;
  isOver: boolean;
  isDone: boolean;
  isHigh: boolean;
  tasks: TaskWithDetail[];
  onCardClick: (task: TaskWithDetail) => void;
  onCardEdit: (task: TaskWithDetail) => void;
  onCardDelete: (taskId: string) => void;
}

const CELL_LIMIT = 6;

function Cell({
  id, priority, column, isOver, isDone, isHigh, tasks,
  onCardClick, onCardEdit, onCardDelete,
}: CellProps) {
  const { setNodeRef } = useDroppable({ id, data: { column, priority } });
  const isEmpty = tasks.length === 0;
  const [expanded, setExpanded] = useState(false);
  const visibleTasks =
    expanded || tasks.length <= CELL_LIMIT ? tasks : tasks.slice(0, CELL_LIMIT);
  const hiddenCount = tasks.length - visibleTasks.length;

  const baseStyle: React.CSSProperties = {
    minHeight: isEmpty ? 56 : 80,
    borderRadius: 10,
    padding: 6,
    display: 'flex',
    flexDirection: 'column',
    gap: 6,
    transition: 'background 0.15s, border-color 0.15s',
    border: isOver
      ? '1px solid var(--owl-neon)'
      : `1px dashed ${isHigh ? 'rgba(232,112,96,0.3)' : 'rgba(30,90,80,0.35)'}`,
    background: isOver
      ? 'rgba(210,230,50,0.05)'
      : isHigh
      ? 'rgba(232,112,96,0.05)'
      : 'rgba(15,51,51,0.22)',
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
            isDone={column === 'done'}
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
      {expanded && tasks.length > CELL_LIMIT && (
        <button
          onClick={() => setExpanded(false)}
          className="w-full rounded-md transition-colors"
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            color: 'var(--owl-text-disabled)',
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
            color: isDone ? 'var(--owl-positive)' : 'var(--owl-text-disabled)',
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
