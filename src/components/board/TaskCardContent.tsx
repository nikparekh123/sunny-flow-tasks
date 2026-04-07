import { useState } from 'react';
import { MoreHorizontal, Repeat, ListChecks, Calendar } from 'lucide-react';
import { format, parseISO, startOfDay, isSameDay, addDays, isBefore } from 'date-fns';
import { PRIORITY_COLORS } from '@/lib/constants';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Progress } from '@/components/ui/progress';
import type { TaskWithDetail } from '@/lib/types';

interface Props {
  task: TaskWithDetail;
  isDone: boolean;
  onClick: () => void;
  onEdit: () => void;
  onDelete: () => void;
  isDragging?: boolean;
  isOverlay?: boolean;
  columnLabel?: string;
  columnColor?: string;
}

const PRIORITY_LABELS: Record<string, string> = {
  high: 'High',
  med: 'Medium',
  low: 'Low',
};

export function TaskCardContent({ task, isDone, onClick, onEdit, onDelete, isDragging, isOverlay, columnLabel, columnColor }: Props) {
  const [menuOpen, setMenuOpen] = useState(false);

  const today = startOfDay(new Date());
  const dueDay = task.due_date ? startOfDay(parseISO(task.due_date)) : null;
  const isToday = dueDay ? isSameDay(dueDay, today) : false;
  const isTomorrow = dueDay ? isSameDay(dueDay, addDays(today, 1)) : false;
  const isOverdue = dueDay ? isBefore(dueDay, today) && !isDone : false;

  const getDueDateDisplay = () => {
    if (!task.due_date || !dueDay) return null;
    if (isDone) return format(parseISO(task.due_date), 'MMM d');
    if (isToday) return 'Today';
    if (isTomorrow) return 'Tomorrow';
    if (isOverdue) return `${format(parseISO(task.due_date), 'MMM d')} — overdue`;
    return format(parseISO(task.due_date), 'MMM d');
  };

  const getDueDateColor = () => {
    if (isDone) return 'var(--owl-text-muted)';
    if (isToday) return 'var(--owl-positive)';
    if (isTomorrow) return 'var(--owl-text-secondary)';
    if (isOverdue) return 'var(--owl-negative)';
    return 'var(--owl-text-secondary)';
  };

  const assignees = task.assignees || [];
  const maxVisible = 3;
  const visibleAssignees = assignees.slice(0, maxVisible);
  const overflowCount = assignees.length - maxVisible;

  const subtasks = task.subtasks || [];
  const subtaskTotal = subtasks.length;
  const subtaskDone = subtasks.filter(s => s.done).length;
  const subtaskPercent = subtaskTotal > 0 ? (subtaskDone / subtaskTotal) * 100 : 0;

  const hasFooter = task.due_date || task.priority;
  const hasBottomMeta = subtaskTotal > 0;

  const isHighPriority = task.priority === 'high' && !isDone;

  return (
    <div
      className="group/card relative"
      style={{
        backgroundColor: isHighPriority ? 'rgba(210, 230, 50, 0.08)' : 'var(--owl-card)',
        border: isHighPriority ? '1px solid rgba(210, 230, 50, 0.35)' : '1px solid var(--owl-border)',
        borderRadius: 'var(--owl-radius-lg)',
        padding: '14px 16px',
        opacity: isDone ? 0.55 : 1,
        cursor: isOverlay ? 'grabbing' : 'grab',
        boxShadow: isOverlay
          ? '0 8px 24px rgba(0,0,0,0.3)'
          : isHighPriority
            ? '0 1px 8px rgba(210, 230, 50, 0.12)'
            : '0 1px 4px rgba(0,0,0,0.2)',
        transform: isOverlay ? 'rotate(2deg) scale(1.02)' : undefined,
      }}
      onClick={(e) => {
        if (!menuOpen && !isOverlay) onClick();
      }}
      role="button"
      tabIndex={0}
    >
      {/* Row 1: Status pill + recurrence + menu */}
      <div className="flex items-center justify-between mb-2.5">
        <div className="flex items-center gap-2">
          {columnLabel && (
            <span
              className="inline-flex items-center gap-1.5 text-[11px] font-medium px-2 py-0.5 rounded-full"
              style={{
                backgroundColor: (columnColor || '#888') + '18',
                color: columnColor || 'var(--owl-text-secondary)',
              }}
            >
              <span
                className="w-1.5 h-1.5 rounded-full"
                style={{ backgroundColor: columnColor || '#888' }}
              />
              {columnLabel}
            </span>
          )}
          {task.recurrence && (
            <Repeat className="w-3.5 h-3.5" style={{ color: 'var(--owl-text-muted)' }} />
          )}
        </div>

        {/* ⋯ menu button */}
        {!isOverlay && (
          <div
            className="flex items-center justify-center rounded cursor-pointer opacity-0 group-hover/card:opacity-100 transition-opacity duration-150"
            style={{
              width: '24px',
              height: '24px',
              backgroundColor: 'var(--owl-surface)',
              border: '1px solid var(--owl-border)',
            }}
            onClick={(e) => {
              e.stopPropagation();
              setMenuOpen(!menuOpen);
            }}
          >
            <MoreHorizontal style={{ width: '13px', height: '13px', color: 'var(--owl-text-secondary)' }} />
          </div>
        )}
      </div>

      {/* Dropdown menu */}
      {menuOpen && (
        <>
          <div className="fixed inset-0 z-40" onClick={(e) => { e.stopPropagation(); setMenuOpen(false); }} />
          <div
            className="absolute z-50 animate-scale-in"
            style={{
              top: '42px',
              right: '12px',
              backgroundColor: 'var(--owl-surface)',
              border: '1px solid var(--owl-border)',
              borderRadius: 'var(--owl-radius-md)',
              boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
              overflow: 'hidden',
              minWidth: '110px',
            }}
          >
            <button
              className="w-full text-left block"
              style={{ fontSize: '12px', color: 'var(--owl-text-secondary)', padding: '8px 14px' }}
              onMouseEnter={(e) => { e.currentTarget.style.backgroundColor = 'rgba(30,90,80,0.15)'; }}
              onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = 'transparent'; }}
              onClick={(e) => { e.stopPropagation(); setMenuOpen(false); onEdit(); }}
            >
              Edit
            </button>
            <button
              className="w-full text-left block"
              style={{ fontSize: '12px', color: 'var(--owl-text-secondary)', padding: '8px 14px' }}
              onMouseEnter={(e) => { e.currentTarget.style.backgroundColor = 'rgba(232,112,96,0.15)'; e.currentTarget.style.color = 'var(--owl-negative)'; }}
              onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = 'transparent'; e.currentTarget.style.color = 'var(--owl-text-secondary)'; }}
              onClick={(e) => { e.stopPropagation(); setMenuOpen(false); onDelete(); }}
            >
              Delete
            </button>
          </div>
        </>
      )}

      {/* Row 2: Title */}
      <p
        style={{
          fontSize: '16px',
          fontWeight: 600,
          color: 'var(--owl-text-primary)',
          lineHeight: 1.4,
          textDecoration: isDone ? 'line-through' : 'none',
          margin: 0,
        }}
      >
        {task.title}
      </p>

      {/* Row 3: Brief */}
      {task.brief && (
        <p
          style={{
            fontSize: '12px',
            lineHeight: 1.4,
            marginTop: '6px',
            color: 'var(--owl-text-secondary)',
            display: '-webkit-box',
            WebkitLineClamp: 2,
            WebkitBoxOrient: 'vertical',
            overflow: 'hidden',
          }}
        >
          {task.brief}
        </p>
      )}

      {/* Tags */}
      {task.tags && task.tags.length > 0 && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '5px', marginTop: '8px' }}>
          {task.tags.map((tag) => (
            <span
              key={tag.id}
              style={{
                fontSize: '11px',
                padding: '2px 8px',
                borderRadius: '10px',
                backgroundColor: (tag.color || '#888') + '20',
                color: tag.color || 'var(--owl-text-secondary)',
                fontWeight: 500,
              }}
            >
              #{tag.name}
            </span>
          ))}
        </div>
      )}

      {/* Row 4: Assignees */}
      {(assignees.length > 0 || task.assignee_initials) && (
        <div className="flex items-center gap-2 mt-2.5">
          <span style={{ fontSize: '11px', color: 'var(--owl-text-muted)' }}>Assignees:</span>
          {assignees.length > 0 ? (
            <div className="flex items-center">
              {visibleAssignees.map((a, i) => (
                <Avatar
                  key={a.id}
                  className="h-6 w-6"
                  style={{
                    marginLeft: i > 0 ? '-6px' : 0,
                    zIndex: maxVisible - i,
                    border: '2px solid var(--owl-surface)',
                  }}
                >
                  <AvatarImage src={a.avatar_url || ''} />
                  <AvatarFallback
                    style={{
                      backgroundColor: a.color || '#378ADD',
                      fontSize: '9px',
                      fontWeight: 600,
                      color: '#fff',
                    }}
                  >
                    {a.initials}
                  </AvatarFallback>
                </Avatar>
              ))}
              {overflowCount > 0 && (
                <span style={{ fontSize: '9px', color: 'var(--owl-text-muted)', marginLeft: '4px' }}>+{overflowCount}</span>
              )}
            </div>
          ) : task.assignee_initials ? (
            <Avatar className="h-6 w-6">
              <AvatarImage src={task.assignee_avatar_url || ''} />
              <AvatarFallback
                style={{
                  backgroundColor: task.assignee_color || '#378ADD',
                  fontSize: '9px',
                  fontWeight: 600,
                  color: '#fff',
                }}
              >
                {task.assignee_initials}
              </AvatarFallback>
            </Avatar>
          ) : null}
        </div>
      )}

      {/* Separator */}
      {(hasFooter || hasBottomMeta) && (
        <div
          style={{
            height: '1px',
            backgroundColor: 'var(--owl-border)',
            marginTop: '10px',
            marginBottom: '10px',
          }}
        />
      )}

      {/* Row 5: Footer — due date + priority pill */}
      {hasFooter && (
        <div className="flex items-center justify-between">
          {task.due_date ? (
            <span
              className="inline-flex items-center gap-1"
              style={{
                fontSize: '12px',
                color: getDueDateColor(),
                fontWeight: isToday || isOverdue ? 500 : 400,
              }}
            >
              <Calendar className="w-3 h-3" />
              {getDueDateDisplay()}
            </span>
          ) : <span />}

          <span
            className="text-[11px] font-medium px-2 py-0.5 rounded-full"
            style={{
              color: PRIORITY_COLORS[task.priority],
              backgroundColor: PRIORITY_COLORS[task.priority] + '15',
            }}
          >
            {PRIORITY_LABELS[task.priority]}
          </span>
        </div>
      )}

      {/* Row 6: Subtask progress */}
      {hasBottomMeta && (
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginTop: hasFooter ? '8px' : '0' }}>
          <ListChecks className="w-3.5 h-3.5 flex-shrink-0" style={{ color: 'var(--owl-text-muted)' }} />
          <Progress value={subtaskPercent} className="h-1.5 flex-1" />
          <span style={{ fontSize: '11px', color: 'var(--owl-text-muted)', whiteSpace: 'nowrap', fontWeight: 500 }}>{subtaskDone}/{subtaskTotal}</span>
        </div>
      )}
    </div>
  );
}
