import { useState } from 'react';
import { MoreHorizontal, Repeat } from 'lucide-react';
import { format, parseISO, startOfDay, isSameDay, addDays, isBefore } from 'date-fns';
import { PRIORITY_COLORS } from '@/lib/constants';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import type { TaskWithDetail } from '@/lib/types';

interface Props {
  task: TaskWithDetail;
  isDone: boolean;
  onClick: () => void;
  onEdit: () => void;
  onDelete: () => void;
  isDragging?: boolean;
  isOverlay?: boolean;
}

export function TaskCardContent({ task, isDone, onClick, onEdit, onDelete, isDragging, isOverlay }: Props) {
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
    if (isDone) return undefined;
    if (isToday) return '#639922';
    if (isTomorrow) return 'hsl(var(--muted-foreground))';
    if (isOverdue) return '#A32D2D';
    return undefined;
  };

  const assignees = task.assignees || [];
  const maxVisible = 3;
  const visibleAssignees = assignees.slice(0, maxVisible);
  const overflowCount = assignees.length - maxVisible;

  return (
    <div
      className="group/card relative"
      style={{
        backgroundColor: isOverlay
          ? '#fff'
          : task.priority === 'high'
            ? 'rgba(226,75,74,0.04)'
            : task.priority === 'med'
              ? 'rgba(239,159,39,0.04)'
              : 'rgba(99,153,34,0.04)',
        border: isOverlay ? '1px solid #d4d4d4' : '0.5px solid #ebebeb',
        borderLeft: isOverlay
          ? undefined
          : `3px solid ${PRIORITY_COLORS[task.priority]}`,
        borderRadius: '8px',
        padding: '10px',
        opacity: isDone ? 0.5 : 1,
        cursor: isOverlay ? 'grabbing' : 'grab',
        boxShadow: isOverlay ? '0 8px 24px rgba(0,0,0,0.12)' : 'none',
        transform: isOverlay ? 'rotate(2deg) scale(1.02)' : undefined,
      }}
      onMouseEnter={(e) => {
        if (!isOverlay) {
          e.currentTarget.style.backgroundColor = '#f3f3f3';
          e.currentTarget.style.borderColor = '#d4d4d4';
        }
      }}
      onMouseLeave={(e) => {
        if (!isOverlay) {
          e.currentTarget.style.backgroundColor = '#f7f7f7';
          e.currentTarget.style.borderColor = '#ebebeb';
        }
      }}
      onClick={(e) => {
        if (!menuOpen && !isOverlay) onClick();
      }}
      role="button"
      tabIndex={0}
    >
      {/* Priority dot + recurring icon */}
      <div className="absolute flex items-center gap-1 transition-[right] duration-150 group-hover/card:right-[30px]" style={{ top: '12px', right: '10px' }}>
        {task.recurrence && (
          <Repeat className="w-2.5 h-2.5 text-muted-foreground" />
        )}
        <div
          style={{
            width: '7px',
            height: '7px',
            borderRadius: '50%',
            backgroundColor: PRIORITY_COLORS[task.priority],
          }}
        />
      </div>

      {/* ⋯ menu button */}
      {!isOverlay && (
        <div
          className="absolute hidden group-hover/card:flex items-center justify-center"
          style={{
            top: '8px',
            right: '8px',
            width: '20px',
            height: '20px',
            borderRadius: '4px',
            backgroundColor: '#ebebeb',
            border: '0.5px solid #ddd',
            cursor: 'pointer',
          }}
          onClick={(e) => {
            e.stopPropagation();
            setMenuOpen(!menuOpen);
          }}
        >
          <MoreHorizontal style={{ width: '11px', height: '11px', color: '#999' }} />
        </div>
      )}

      {/* Dropdown menu */}
      {menuOpen && (
        <>
          <div className="fixed inset-0 z-40" onClick={(e) => { e.stopPropagation(); setMenuOpen(false); }} />
          <div
            className="absolute z-50 animate-scale-in"
            style={{
              top: '30px',
              right: '8px',
              backgroundColor: '#fff',
              border: '0.5px solid #ebebeb',
              borderRadius: '8px',
              boxShadow: '0 4px 12px rgba(0,0,0,0.08)',
              overflow: 'hidden',
              minWidth: '100px',
            }}
          >
            <button
              className="w-full text-left block hover:bg-secondary"
              style={{ fontSize: '12px', color: 'hsl(var(--muted-foreground))', padding: '8px 14px' }}
              onClick={(e) => { e.stopPropagation(); setMenuOpen(false); onEdit(); }}
            >
              Edit
            </button>
            <button
              className="w-full text-left block"
              style={{ fontSize: '12px', color: 'hsl(var(--muted-foreground))', padding: '8px 14px' }}
              onMouseEnter={(e) => { e.currentTarget.style.backgroundColor = '#FCEBEB'; e.currentTarget.style.color = '#A32D2D'; }}
              onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = 'transparent'; e.currentTarget.style.color = 'hsl(var(--muted-foreground))'; }}
              onClick={(e) => { e.stopPropagation(); setMenuOpen(false); onDelete(); }}
            >
              Delete
            </button>
          </div>
        </>
      )}

      {/* Title */}
      <p
        style={{
          fontSize: '12px',
          fontWeight: 500,
          color: 'hsl(var(--foreground))',
          lineHeight: 1.4,
          paddingRight: '16px',
          textDecoration: isDone ? 'line-through' : 'none',
          margin: 0,
        }}
      >
        {task.title}
      </p>

      {/* Brief preview */}
      {task.brief && (
        <p
          className="text-muted-foreground"
          style={{
            fontSize: '10px',
            lineHeight: 1.3,
            marginTop: '3px',
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
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px', marginTop: '6px' }}>
          {task.tags.map((tag) => (
            <span
              key={tag.id}
              style={{
                fontSize: '10px',
                padding: '1px 6px',
                borderRadius: '10px',
                backgroundColor: (tag.color || '#888') + '20',
                color: tag.color || '#888',
              }}
            >
              #{tag.name}
            </span>
          ))}
        </div>
      )}

      {/* Footer */}
      {(task.due_date || assignees.length > 0 || task.assignee_initials) && (
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '8px' }}>
          {task.due_date ? (
            <span
              style={{
                fontSize: '10px',
                color: getDueDateColor(),
                fontWeight: isToday ? 500 : undefined,
              }}
              className={getDueDateColor() ? '' : 'text-muted-foreground'}
            >
              {getDueDateDisplay()}
            </span>
          ) : <span />}

          {/* Multi-assignee avatars */}
          {assignees.length > 0 ? (
            <div className="flex items-center" style={{ marginLeft: 'auto' }}>
              {visibleAssignees.map((a, i) => (
                <Avatar
                  key={a.id}
                  className="h-5 w-5 border border-card"
                  style={{ marginLeft: i > 0 ? '-6px' : 0, zIndex: maxVisible - i }}
                >
                  <AvatarImage src={a.avatar_url || ''} />
                  <AvatarFallback
                    style={{
                      backgroundColor: a.color || '#378ADD',
                      fontSize: '8px',
                      fontWeight: 500,
                      color: '#fff',
                    }}
                  >
                    {a.initials}
                  </AvatarFallback>
                </Avatar>
              ))}
              {overflowCount > 0 && (
                <span className="text-[8px] text-muted-foreground ml-0.5">+{overflowCount}</span>
              )}
            </div>
          ) : task.assignee_initials ? (
            <Avatar className="h-5 w-5">
              <AvatarImage src={task.assignee_avatar_url || ''} />
              <AvatarFallback
                style={{
                  backgroundColor: task.assignee_color || '#378ADD',
                  fontSize: '9px',
                  fontWeight: 500,
                  color: '#fff',
                }}
              >
                {task.assignee_initials}
              </AvatarFallback>
            </Avatar>
          ) : null}
        </div>
      )}
    </div>
  );
}
