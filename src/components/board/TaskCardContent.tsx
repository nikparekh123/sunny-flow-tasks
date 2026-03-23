import { useState } from 'react';
import { MoreHorizontal } from 'lucide-react';
import { format, isPast, parseISO } from 'date-fns';
import { PRIORITY_COLORS } from '@/lib/constants';
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

  const isOverdue = task.due_date && isPast(parseISO(task.due_date)) && !isDone;

  return (
    <div
      className="group/card relative"
      style={{
        backgroundColor: isOverlay ? '#fff' : '#f7f7f7',
        border: isOverlay ? '1px solid #d4d4d4' : '0.5px solid #ebebeb',
        borderRadius: '8px',
        padding: '10px',
        opacity: isDragging ? 0.4 : isDone ? 0.5 : 1,
        cursor: isOverlay ? 'grabbing' : 'grab',
        boxShadow: isOverlay ? '0 8px 24px rgba(0,0,0,0.12)' : 'none',
        transform: isOverlay ? 'rotate(2deg) scale(1.02)' : undefined,
        transition: isDragging ? 'opacity 0.2s' : undefined,
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
      {/* Priority dot */}
      <div
        className="absolute transition-[right] duration-150 group-hover/card:right-[30px]"
        style={{
          top: '12px',
          right: '10px',
          width: '7px',
          height: '7px',
          borderRadius: '50%',
          backgroundColor: PRIORITY_COLORS[task.priority],
        }}
      />

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

      {/* Tags */}
      {task.tags && task.tags.length > 0 && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px', marginTop: '6px' }}>
          {task.tags.map((tag) => (
            <span
              key={tag.id}
              className="bg-secondary text-muted-foreground"
              style={{
                fontSize: '10px',
                padding: '1px 6px',
                borderRadius: '10px',
              }}
            >
              #{tag.name}
            </span>
          ))}
        </div>
      )}

      {/* Footer */}
      {(task.due_date || task.assignee_initials) && (
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '8px' }}>
          {task.due_date ? (
            <span
              className="text-muted-foreground"
              style={{
                fontSize: '10px',
                color: isOverdue ? '#A32D2D' : undefined,
              }}
            >
              {format(parseISO(task.due_date), 'MMM d')}
              {isOverdue && ' — overdue'}
            </span>
          ) : <span />}
          {task.assignee_initials && (
            <div
              style={{
                width: '20px',
                height: '20px',
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '9px',
                fontWeight: 500,
                color: '#fff',
                backgroundColor: task.assignee_color || '#378ADD',
              }}
            >
              {task.assignee_initials}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
