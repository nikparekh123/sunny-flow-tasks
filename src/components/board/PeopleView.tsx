import { useState, useMemo, useCallback, useEffect } from 'react';
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  useSensor,
  useSensors,
  useDraggable,
  useDroppable,
  pointerWithin,
  type DragStartEvent,
  type DragEndEvent,
} from '@dnd-kit/core';
import { Calendar as CalendarIcon, X } from 'lucide-react';
import { format, parseISO } from 'date-fns';
import { COLUMNS, canMoveColumn } from '@/lib/constants';
import { toast } from 'sonner';
import type { TaskWithDetail, TeamMember, TaskColumn, TaskPriority } from '@/lib/types';

interface Props {
  tasks: TaskWithDetail[];
  members: TeamMember[];
  onTaskClick?: (task: TaskWithDetail) => void; // kept for API compat; unused in matrix view
  currentMemberId: string | null;
  onUpdate: (data: { id: string } & Record<string, any>) => void;
  onDelete: (taskId: string) => void;
}

type TaskType = 'task' | 'recurring';

const PRI_ORDER: Record<string, number> = { high: 0, med: 1, low: 2 };
const PRI_LETTER: Record<string, string> = { high: 'H', med: 'M', low: 'L' };
const PRI_LABEL: Record<string, string> = { high: 'HIGH', med: 'MED', low: 'LOW' };
const TYPE_GLYPH: Record<TaskType, string> = { task: '▢', recurring: '↻' };
const CELL_CAP = 12;

// Loose type mapping — rest of the handoff's types (deadline/bug/milestone) are
// not tracked in our data yet, so everything non-recurring is a plain task.
function typeOf(t: TaskWithDetail): TaskType {
  return t.recurrence ? 'recurring' : 'task';
}

// Each teammate has a stable background color for their avatar + row.
const AVATAR_COLORS = ['#c85a7a', '#5a8ac8', '#7aa878', '#c8a05a', '#a090e0', '#e0a070'];
function avatarColor(id: string): string {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return AVATAR_COLORS[h % AVATAR_COLORS.length];
}

function sortByPri(list: TaskWithDetail[]): TaskWithDetail[] {
  return [...list].sort((a, b) => {
    const p = (PRI_ORDER[a.priority] ?? 3) - (PRI_ORDER[b.priority] ?? 3);
    if (p) return p;
    return a.title.localeCompare(b.title);
  });
}

export function PeopleView({
  tasks,
  members,
  currentMemberId,
  onUpdate,
  onDelete,
}: Props) {
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [showMore, setShowMore] = useState<Record<string, boolean>>({});
  const [draggedTask, setDraggedTask] = useState<TaskWithDetail | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
  );

  // Close expanded on Escape
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setExpandedId(null);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // Per-cell tasks keyed by `${memberId}:${columnId}`.
  const cellTasks = useCallback(
    (memberId: string, columnId: TaskColumn) =>
      tasks.filter(
        (t) =>
          t.column === columnId &&
          (t.assignee_id === memberId ||
            (!t.assignee_id && t.assignee_ids?.[0] === memberId)),
      ),
    [tasks],
  );

  // Column header totals — across the whole team.
  const totals = useMemo(() => {
    const out: Record<TaskColumn, number> = { backlog: 0, todo: 0, inprogress: 0, review: 0, done: 0 };
    tasks.forEach((t) => {
      out[t.column] = (out[t.column] ?? 0) + 1;
    });
    return out;
  }, [tasks]);

  const handleDragStart = (event: DragStartEvent) => {
    const task = event.active.data.current?.task as TaskWithDetail | undefined;
    if (task) setDraggedTask(task);
  };

  const handleDragEnd = (event: DragEndEvent) => {
    setDraggedTask(null);
    const task = event.active.data.current?.task as TaskWithDetail | undefined;
    if (!task || !event.over) return;
    const [memberId, columnId] = (event.over.id as string).split(':');
    const nextColumn = columnId as TaskColumn;
    const nextAssignee = memberId;
    const changedColumn = task.column !== nextColumn;
    const changedOwner = task.assignee_id !== nextAssignee;
    if (!changedColumn && !changedOwner) return;

    if (changedColumn && !canMoveColumn(task.column, nextColumn)) {
      toast.error('Can only move to the next step');
      return;
    }

    const patch: Record<string, any> = { id: task.id };
    if (changedColumn) patch.column = nextColumn;
    if (changedOwner) {
      patch.assignee_id = nextAssignee;
      // Keep the owner consistent in the multi-assignee list too.
      const ids = Array.from(new Set([nextAssignee, ...(task.assignee_ids || [])]));
      patch.assignee_ids = ids;
    }
    onUpdate(patch);
  };

  if (members.length === 0) {
    return (
      <div
        className="px-5 md:px-7 py-8"
        style={{ color: 'var(--owl-text-muted)', fontSize: 13 }}
      >
        No team members yet.
      </div>
    );
  }

  return (
    <div className="px-5 md:px-7 pb-4" onClick={() => setExpandedId(null)}>
      <DndContext
        sensors={sensors}
        collisionDetection={pointerWithin}
        onDragStart={handleDragStart}
        onDragEnd={handleDragEnd}
      >
        <div
          className="mt-2"
          style={{
            display: 'grid',
            gap: 1,
            background: 'var(--owl-line)',
            border: '1px solid var(--owl-line)',
            borderRadius: 10,
            overflow: 'hidden',
            gridTemplateColumns: `76px repeat(${COLUMNS.length}, 1fr)`,
          }}
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header row: "Teammate" + each status */}
          <HeaderCell isFirst>Teammate</HeaderCell>
          {COLUMNS.map((c) => (
            <HeaderCell key={c.id} column={c.id}>
              <span
                style={{
                  fontFamily: 'var(--owl-font-mono)',
                  fontSize: 20,
                  fontWeight: 500,
                  letterSpacing: '-0.5px',
                  color:
                    c.id === 'done'
                      ? 'var(--owl-positive)'
                      : c.id === 'todo'
                      ? 'var(--owl-neon)'
                      : 'var(--owl-text-primary)',
                }}
              >
                {totals[c.id]}
              </span>
              <span
                style={{
                  fontSize: 9,
                  fontWeight: 600,
                  letterSpacing: '2px',
                  textTransform: 'uppercase',
                  color: 'var(--owl-text-muted)',
                }}
              >
                {c.label}
              </span>
            </HeaderCell>
          ))}

          {/* One row per teammate (+ optional expand-row underneath) */}
          {members.map((m) => {
            const expanded = expandedId ? tasks.find((t) => t.id === expandedId) : null;
            const expandedBelongsToRow =
              expanded &&
              (expanded.assignee_id === m.id ||
                (!expanded.assignee_id && expanded.assignee_ids?.[0] === m.id));

            return (
              <FragmentRow key={m.id}>
                <AvatarCell member={m} color={avatarColor(m.id)} />

                {COLUMNS.map((c) => (
                  <Cell
                    key={c.id}
                    memberId={m.id}
                    columnId={c.id}
                    tasks={sortByPri(cellTasks(m.id, c.id))}
                    expandedId={expandedId}
                    onExpand={setExpandedId}
                    showMore={showMore[`${m.id}:${c.id}`]}
                    onShowMore={() =>
                      setShowMore((prev) => ({ ...prev, [`${m.id}:${c.id}`]: true }))
                    }
                  />
                ))}

                {expandedBelongsToRow && expanded && (
                  <>
                    <div
                      style={{
                        background: 'var(--owl-surface)',
                        borderRight: '1px solid var(--owl-line)',
                      }}
                    />
                    <div
                      style={{
                        gridColumn: `2 / -1`,
                        background: 'var(--owl-surface)',
                        padding: '14px 16px 18px',
                        borderTop: '1px solid var(--owl-line-bright)',
                      }}
                    >
                      <ExpandedCard
                        task={expanded}
                        member={m}
                        allMembers={members}
                        onClose={() => setExpandedId(null)}
                        onUpdate={onUpdate}
                        onDelete={onDelete}
                      />
                    </div>
                  </>
                )}
              </FragmentRow>
            );
          })}
        </div>

        <DragOverlay dropAnimation={null}>
          {draggedTask && <SmallCard task={draggedTask} isOverlay />}
        </DragOverlay>
      </DndContext>
    </div>
  );
}

// ── Layout helpers ───────────────────────────────────────────────────────────
function FragmentRow({ children }: { children: React.ReactNode }) {
  // React.Fragment wrapper so the grid treats these as direct children.
  return <>{children}</>;
}

function HeaderCell({
  children,
  column,
  isFirst,
}: {
  children: React.ReactNode;
  column?: string;
  isFirst?: boolean;
}) {
  return (
    <div
      style={{
        background: 'var(--owl-dash)',
        padding: '14px 16px',
        display: 'flex',
        alignItems: 'baseline',
        gap: 10,
      }}
    >
      {isFirst ? (
        <span
          style={{
            fontSize: 9,
            fontWeight: 600,
            letterSpacing: '2px',
            textTransform: 'uppercase',
            color: 'var(--owl-text-label)',
          }}
        >
          {children}
        </span>
      ) : (
        children
      )}
    </div>
  );
}

function AvatarCell({ member, color }: { member: TeamMember; color: string }) {
  return (
    <div
      title={`${member.name}${member.role ? ` · ${member.role}` : ''}`}
      style={{
        background: 'var(--owl-page)',
        padding: '12px 10px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        borderRight: '1px solid var(--owl-line)',
      }}
    >
      <span
        style={{
          width: 28,
          height: 28,
          borderRadius: '50%',
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontFamily: 'var(--owl-font-mono)',
          fontSize: 11,
          fontWeight: 500,
          color: '#faf5f0',
          background: color,
        }}
      >
        {member.initials}
      </span>
    </div>
  );
}

// ── Cell ────────────────────────────────────────────────────────────────────
interface CellProps {
  memberId: string;
  columnId: TaskColumn;
  tasks: TaskWithDetail[];
  expandedId: string | null;
  onExpand: (id: string | null) => void;
  showMore?: boolean;
  onShowMore: () => void;
}

function Cell({
  memberId,
  columnId,
  tasks,
  expandedId,
  onExpand,
  showMore,
  onShowMore,
}: CellProps) {
  const id = `${memberId}:${columnId}`;
  const { setNodeRef, isOver } = useDroppable({ id });

  let visible = tasks;
  let hidden = 0;
  if (!showMore && tasks.length > CELL_CAP) {
    visible = tasks.slice(0, CELL_CAP);
    const expanded = expandedId && tasks.find((t) => t.id === expandedId);
    if (expanded && !visible.find((t) => t.id === expanded.id)) {
      visible = [...visible.slice(0, CELL_CAP - 1), expanded];
    }
    hidden = tasks.length - visible.length;
  }

  const isEmpty = tasks.length === 0;

  return (
    <div
      ref={setNodeRef}
      style={{
        background: 'var(--owl-page)',
        padding: 12,
        minHeight: isEmpty ? 100 : 80,
        display: 'flex',
        flexDirection: 'column',
        gap: 5,
        transition: 'background 0.15s',
        ...(isOver
          ? {
              background: 'rgba(210,230,50,0.05)',
              boxShadow: 'inset 0 0 0 1.5px var(--owl-neon)',
            }
          : {}),
        ...(isEmpty
          ? { alignItems: 'center', justifyContent: 'center' }
          : {}),
      }}
    >
      {!isEmpty && (
        <div
          style={{
            display: 'flex',
            justifyContent: 'flex-end',
            marginBottom: 2,
          }}
        >
          <span
            style={{
              fontFamily: 'var(--owl-font-mono)',
              fontSize: 10.5,
              fontWeight: 500,
              color: 'var(--owl-text-label)',
              letterSpacing: '0.5px',
            }}
          >
            {tasks.length}
          </span>
        </div>
      )}

      {isEmpty && (
        <div
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 11,
            color: 'var(--owl-text-label)',
            textAlign: 'center',
            lineHeight: 1.5,
            letterSpacing: '0.5px',
          }}
        >
          — no tasks —
          <br />
          <span style={{ fontSize: 9, opacity: 0.7 }}>drop here to assign</span>
        </div>
      )}

      {visible.map((t) => (
        <DraggableCard
          key={t.id}
          task={t}
          selected={t.id === expandedId}
          onClick={() => onExpand(t.id === expandedId ? null : t.id)}
        />
      ))}

      {hidden > 0 && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onShowMore();
          }}
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            color: 'var(--owl-text-label)',
            textAlign: 'center',
            padding: 5,
            border: '1px dashed var(--owl-line)',
            borderRadius: 5,
            marginTop: 2,
            background: 'transparent',
            cursor: 'pointer',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.color = 'var(--owl-text-muted)';
            e.currentTarget.style.borderColor = 'var(--owl-line-bright)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.color = 'var(--owl-text-label)';
            e.currentTarget.style.borderColor = 'var(--owl-line)';
          }}
        >
          + {hidden} more
        </button>
      )}
    </div>
  );
}

// ── Small card ──────────────────────────────────────────────────────────────
function DraggableCard({
  task,
  selected,
  onClick,
}: {
  task: TaskWithDetail;
  selected?: boolean;
  onClick: () => void;
}) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: task.id,
    data: { task },
  });

  return (
    <div
      ref={setNodeRef}
      {...attributes}
      {...listeners}
      onClick={(e) => {
        e.stopPropagation();
        if (!isDragging) onClick();
      }}
      style={{ opacity: isDragging ? 0.3 : 1 }}
    >
      <SmallCard task={task} selected={selected} />
    </div>
  );
}

function SmallCard({
  task,
  selected,
  isOverlay,
}: {
  task: TaskWithDetail;
  selected?: boolean;
  isOverlay?: boolean;
}) {
  const type = typeOf(task);
  const isDone = task.column === 'done';

  const typeBg: Record<TaskType, { bg: string; border: string; title: string }> = {
    task: {
      bg: '#123e3e',
      border: 'rgba(50,110,100,0.3)',
      title: 'var(--owl-text-primary)',
    },
    recurring: {
      bg: 'rgba(160,144,224,0.18)',
      border: 'rgba(160,144,224,0.35)',
      title: '#e2dcf5',
    },
  };
  const t = typeBg[type];

  const priColor =
    task.priority === 'high'
      ? 'var(--owl-negative)'
      : task.priority === 'med'
      ? 'var(--owl-warning)'
      : 'var(--owl-text-invisible)';

  const glyphColor =
    type === 'recurring'
      ? '#a090e0'
      : 'var(--owl-text-muted)';

  const dateStr = task.due_date
    ? `→ ${format(parseISO(task.due_date), 'MMM d')}`
    : task.created_at
    ? `→ ${format(parseISO(task.created_at), 'MMM d')}`
    : '';

  return (
    <div
      style={{
        background: t.bg,
        border: `1px solid ${t.border}`,
        borderRadius: 6,
        padding: '6px 10px',
        display: 'flex',
        alignItems: 'flex-start',
        gap: 8,
        minHeight: 36,
        cursor: isOverlay ? 'grabbing' : 'grab',
        transition: 'transform 0.15s, background 0.15s, box-shadow 0.15s',
        opacity: isDone ? 0.68 : 1,
        boxShadow: selected ? '0 0 0 1.5px var(--owl-neon)' : 'none',
        transform: selected ? 'translateY(-1px)' : undefined,
      }}
      onMouseEnter={(e) => {
        if (!selected && !isOverlay) {
          e.currentTarget.style.transform = 'translateY(-1px)';
        }
      }}
      onMouseLeave={(e) => {
        if (!selected && !isOverlay) {
          e.currentTarget.style.transform = '';
        }
      }}
    >
      <span
        title={PRI_LABEL[task.priority]}
        style={{
          fontFamily: 'var(--owl-font-mono)',
          fontSize: 9.5,
          fontWeight: 600,
          letterSpacing: '0.5px',
          textTransform: 'uppercase',
          color: priColor,
          flexShrink: 0,
          width: 11,
          textAlign: 'center',
          marginTop: 1,
        }}
      >
        {PRI_LETTER[task.priority] ?? ''}
      </span>
      <span
        style={{
          fontSize: 12,
          color: glyphColor,
          flexShrink: 0,
          width: 12,
          textAlign: 'center',
          lineHeight: 1,
          marginTop: 1,
        }}
      >
        {TYPE_GLYPH[type]}
      </span>
      <span
        style={{
          fontSize: 11.5,
          fontWeight: 500,
          color: t.title,
          lineHeight: 1.3,
          flex: 1,
          minWidth: 0,
          display: '-webkit-box',
          WebkitLineClamp: 2,
          WebkitBoxOrient: 'vertical',
          overflow: 'hidden',
          overflowWrap: 'break-word',
          textDecoration: isDone ? 'line-through' : 'none',
        }}
      >
        {task.title}
      </span>
      {dateStr && (
        <span
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            color: 'var(--owl-text-label)',
            flexShrink: 0,
            whiteSpace: 'nowrap',
            alignSelf: 'flex-end',
            opacity: 0.85,
          }}
        >
          {dateStr}
        </span>
      )}
    </div>
  );
}

// ── Expanded card ───────────────────────────────────────────────────────────
function ExpandedCard({
  task,
  member,
  allMembers,
  onClose,
  onUpdate,
  onDelete,
}: {
  task: TaskWithDetail;
  member: TeamMember;
  allMembers: TeamMember[];
  onClose: () => void;
  onUpdate: (data: { id: string } & Record<string, any>) => void;
  onDelete: (id: string) => void;
}) {
  const type = typeOf(task);
  const isDone = task.column === 'done';

  const typeTagBg =
    type === 'recurring'
      ? 'rgba(160,144,224,0.15)'
      : 'rgba(210,230,50,0.1)';
  const typeTagColor = type === 'recurring' ? '#a090e0' : 'var(--owl-neon)';

  const cyclePri = (): TaskPriority => {
    const order: TaskPriority[] = ['high', 'med', 'low'];
    const next = (order.indexOf(task.priority) + 1) % order.length;
    return order[next];
  };

  const dueDisplay = task.due_date
    ? format(parseISO(task.due_date), 'MMM d, yyyy')
    : '—';
  const startDisplay = task.created_at
    ? format(parseISO(task.created_at), 'MMM d')
    : '—';

  return (
    <div
      style={{
        background: 'var(--owl-surface)',
        border: '1px solid var(--owl-line-bright)',
        borderRadius: 8,
        padding: 14,
        display: 'flex',
        flexDirection: 'column',
        gap: 12,
        maxWidth: 860,
        boxShadow: '0 6px 20px rgba(0,0,0,0.35)',
      }}
    >
      {/* Header */}
      <div className="flex items-start gap-[10px]">
        <span
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 9,
            fontWeight: 500,
            letterSpacing: '1.4px',
            textTransform: 'uppercase',
            padding: '3px 7px',
            borderRadius: 3,
            background: typeTagBg,
            color: typeTagColor,
          }}
        >
          {type}
        </span>
        <span className="flex-1" />
        <button
          onClick={onClose}
          style={{
            border: 0,
            background: 'transparent',
            color: 'var(--owl-text-label)',
            cursor: 'pointer',
            padding: '4px 8px',
            borderRadius: 4,
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            display: 'inline-flex',
            alignItems: 'center',
            gap: 4,
          }}
        >
          <X className="w-3 h-3" /> Collapse
        </button>
      </div>

      {/* Title */}
      <h3
        contentEditable
        suppressContentEditableWarning
        onBlur={(e) => {
          const next = e.currentTarget.innerText.trim();
          if (next && next !== task.title) {
            onUpdate({ id: task.id, title: next });
          }
        }}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            (e.currentTarget as HTMLElement).blur();
          }
        }}
        style={{
          fontSize: 15,
          fontWeight: 500,
          color: 'var(--owl-text-primary)',
          lineHeight: 1.35,
          letterSpacing: '-0.1px',
          outline: 'none',
          padding: '2px 4px',
          margin: '-2px -4px',
          borderRadius: 3,
          textDecoration: isDone ? 'line-through' : 'none',
        }}
      >
        {task.title}
      </h3>

      {/* Description */}
      <div
        contentEditable
        suppressContentEditableWarning
        onBlur={(e) => {
          const next = e.currentTarget.innerText.trim();
          if (next !== (task.description || '')) {
            onUpdate({ id: task.id, description: next || null });
          }
        }}
        style={{
          fontSize: 12,
          color: task.description ? 'var(--owl-text-secondary)' : 'var(--owl-text-invisible)',
          fontStyle: task.description ? 'normal' : 'italic',
          lineHeight: 1.55,
          outline: 'none',
          padding: '6px 8px',
          margin: '0 -8px',
          borderRadius: 4,
        }}
      >
        {task.description || 'Add a description…'}
      </div>

      {/* Metadata grid */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(2, 1fr)',
          gap: '8px 14px',
          padding: '10px 0',
          borderTop: '1px solid var(--owl-line)',
          borderBottom: '1px solid var(--owl-line)',
        }}
      >
        <MetaField label="Priority">
          <span
            onClick={(e) => {
              e.stopPropagation();
              onUpdate({ id: task.id, priority: cyclePri() });
            }}
            style={{
              cursor: 'pointer',
              display: 'inline-flex',
              alignItems: 'center',
              gap: 5,
              fontFamily: 'var(--owl-font-mono)',
              fontSize: 11,
              color:
                task.priority === 'high'
                  ? 'var(--owl-negative)'
                  : task.priority === 'med'
                  ? 'var(--owl-warning)'
                  : 'var(--owl-text-muted)',
            }}
          >
            <span
              style={{
                width: 6,
                height: 6,
                borderRadius: '50%',
                background: 'currentColor',
              }}
            />
            {PRI_LABEL[task.priority]}
          </span>
        </MetaField>
        <MetaField label="Owner">
          <span
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 5,
            }}
          >
            <span
              style={{
                width: 18,
                height: 18,
                borderRadius: '50%',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontFamily: 'var(--owl-font-mono)',
                fontSize: 8.5,
                fontWeight: 500,
                color: '#faf5f0',
                background: avatarColor(member.id),
              }}
            >
              {member.initials}
            </span>
            <span style={{ color: 'var(--owl-text-primary)' }}>{member.name}</span>
          </span>
        </MetaField>
        <MetaField label="Start">
          <span
            style={{
              fontFamily: 'var(--owl-font-mono)',
              fontSize: 11,
              color: 'var(--owl-text-primary)',
            }}
          >
            {startDisplay}
          </span>
        </MetaField>
        <MetaField label="Due">
          <span
            style={{
              fontFamily: 'var(--owl-font-mono)',
              fontSize: 11,
              color: 'var(--owl-text-primary)',
              display: 'inline-flex',
              alignItems: 'center',
              gap: 4,
            }}
          >
            <CalendarIcon className="w-3 h-3" />
            {dueDisplay}
          </span>
        </MetaField>
      </div>

      {/* Actions */}
      <div className="flex gap-2 flex-wrap">
        <ActionButton
          primary
          onClick={() => {
            onUpdate({
              id: task.id,
              column: isDone ? 'inprogress' : 'done',
            });
            onClose();
          }}
        >
          {isDone ? '↺ Reopen' : '✓ Mark done'}
        </ActionButton>
        <ActionButton
          onClick={() => {
            const idx = COLUMNS.findIndex((c) => c.id === task.column);
            const next = COLUMNS[(idx + 1) % COLUMNS.length].id;
            onUpdate({ id: task.id, column: next });
            onClose();
          }}
        >
          Move status →
        </ActionButton>
        <ActionButton
          onClick={() => {
            const idx = allMembers.findIndex((m) => m.id === member.id);
            const next = allMembers[(idx + 1) % allMembers.length];
            if (next) onUpdate({ id: task.id, assignee_id: next.id });
          }}
        >
          Reassign ↻
        </ActionButton>
        <div className="flex-1" />
        <ActionButton
          danger
          onClick={() => {
            onDelete(task.id);
            onClose();
          }}
        >
          Delete
        </ActionButton>
      </div>
    </div>
  );
}

function MetaField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline gap-2" style={{ fontSize: 11, minWidth: 0 }}>
      <span
        style={{
          fontSize: 8.5,
          fontWeight: 600,
          letterSpacing: '1.5px',
          textTransform: 'uppercase',
          color: 'var(--owl-text-label)',
          width: 58,
          flexShrink: 0,
        }}
      >
        {label}
      </span>
      {children}
    </div>
  );
}

function ActionButton({
  children,
  onClick,
  primary,
  danger,
}: {
  children: React.ReactNode;
  onClick: () => void;
  primary?: boolean;
  danger?: boolean;
}) {
  const baseBg = primary ? 'var(--owl-neon)' : 'rgba(15,51,51,0.6)';
  const baseColor = primary ? '#0a2828' : 'var(--owl-text-secondary)';
  const baseBorder = primary ? 'var(--owl-neon)' : 'var(--owl-line-bright)';

  return (
    <button
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      style={{
        border: `1px solid ${baseBorder}`,
        background: baseBg,
        color: baseColor,
        padding: '6px 11px',
        borderRadius: 5,
        cursor: 'pointer',
        fontFamily: 'var(--owl-font-sans)',
        fontWeight: 500,
        fontSize: 11,
        display: 'inline-flex',
        gap: 5,
        alignItems: 'center',
      }}
      onMouseEnter={(e) => {
        if (danger) {
          e.currentTarget.style.background = 'rgba(232,112,96,0.15)';
          e.currentTarget.style.color = 'var(--owl-negative)';
          e.currentTarget.style.borderColor = 'rgba(232,112,96,0.4)';
        } else if (!primary) {
          e.currentTarget.style.background = 'rgba(30,90,80,0.4)';
          e.currentTarget.style.color = 'var(--owl-text-primary)';
        }
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.background = baseBg;
        e.currentTarget.style.color = baseColor;
        e.currentTarget.style.borderColor = baseBorder;
      }}
    >
      {children}
    </button>
  );
}
