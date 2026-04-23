import { useState, useEffect } from 'react';
import { X, Lock } from 'lucide-react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { format } from 'date-fns';
import { toast } from 'sonner';
import { COLUMNS } from '@/lib/constants';
import type { Tag, TeamMember, TaskPriority, TaskColumn } from '@/lib/types';

interface Props {
  tags: Tag[];
  members: TeamMember[];
  currentMemberId: string | null;
  onClose: () => void;
  onSave: (data: any) => Promise<void>;
  onCreateTag: (name: string) => void;
  defaultColumn?: TaskColumn;
  defaultPriority?: TaskPriority;
}

export function NewTaskPanel({
  members,
  currentMemberId,
  onClose,
  onSave,
  defaultColumn = 'todo',
  defaultPriority = 'med',
}: Props) {
  const [title, setTitle] = useState('');
  const [priority, setPriority] = useState<TaskPriority>(defaultPriority);
  const [column, setColumn] = useState<TaskColumn>(defaultColumn);
  const [assigneeIds, setAssigneeIds] = useState<string[]>(
    currentMemberId ? [currentMemberId] : [],
  );
  const [dueDate, setDueDate] = useState<Date | undefined>();
  const [description, setDescription] = useState('');
  const [isPrivate, setIsPrivate] = useState(false);
  const [participantIds, setParticipantIds] = useState<string[]>([]);
  const [isClosing, setIsClosing] = useState(false);
  const [saving, setSaving] = useState(false);

  const toggleParticipant = (id: string) => {
    setParticipantIds((prev) =>
      prev.includes(id) ? prev.filter((p) => p !== id) : [...prev, id],
    );
  };

  const toggleAssignee = (id: string) => {
    setAssigneeIds((prev) =>
      prev.includes(id) ? prev.filter((a) => a !== id) : [...prev, id],
    );
  };

  const handleClose = () => {
    setIsClosing(true);
    setTimeout(onClose, 200);
  };

  const handleSave = async () => {
    if (!title.trim()) return;
    setSaving(true);
    try {
      // Auto-include creator in participants for private cards so they can still see it.
      const finalParticipants =
        isPrivate && currentMemberId
          ? Array.from(new Set([currentMemberId, ...participantIds]))
          : [];
      await onSave({
        title: title.trim(),
        column,
        priority,
        assignee_ids: assigneeIds,
        due_date: dueDate ? format(dueDate, 'yyyy-MM-dd') : null,
        description: description.trim() || null,
        created_by: currentMemberId,
        visibility: isPrivate ? 'private' : 'team',
        participant_ids: finalParticipants,
      });
      toast.success('Task created');
      handleClose();
    } catch {
      toast.error('Failed to create task');
    } finally {
      setSaving(false);
    }
  };

  // Keyboard shortcuts: Esc to close, ⌘/Ctrl+Enter to create
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') handleClose();
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && title.trim()) {
        e.preventDefault();
        handleSave();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [title, column, priority, assigneeIds, dueDate, description]);

  const priorityLabel = priority === 'high' ? 'High' : priority === 'med' ? 'Med' : 'Low';
  const columnLabel = COLUMNS.find((c) => c.id === column)?.label ?? column;

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center"
      style={{
        padding: '6vh 20px 20px',
        background: 'rgba(6,26,16,0.6)',
        backdropFilter: 'blur(2px)',
        animation: 'owl-fade-up 0.2s ease',
        opacity: isClosing ? 0 : 1,
        transition: 'opacity 0.2s ease',
      }}
      onClick={handleClose}
    >
      <div
        role="dialog"
        aria-label="New card"
        onClick={(e) => e.stopPropagation()}
        className="w-full rounded-xl"
        style={{
          maxWidth: 540,
          background: 'var(--owl-surface)',
          border: '1px solid var(--owl-line-bright)',
          padding: '22px 24px 20px',
          boxShadow: '0 20px 60px rgba(0,0,0,0.5)',
          animation: 'owl-fade-up 0.2s ease',
        }}
      >
        {/* Header */}
        <div className="flex items-center justify-between">
          <h2
            className="flex items-center gap-[10px]"
            style={{
              fontSize: 22,
              fontWeight: 500,
              letterSpacing: '-0.5px',
              color: 'var(--owl-text-primary)',
            }}
          >
            New card
            <span
              style={{
                fontSize: 9,
                fontWeight: 500,
                letterSpacing: '0.6px',
                textTransform: 'uppercase',
                padding: '3px 8px',
                borderRadius: 4,
                background: 'rgba(70,130,120,0.18)',
                color: 'var(--owl-text-secondary)',
              }}
            >
              adds to {columnLabel} · {priorityLabel}
            </span>
          </h2>
          <button
            onClick={handleClose}
            aria-label="Close"
            style={{ color: 'var(--owl-text-muted)' }}
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Title */}
        <Field label="Title">
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="What needs to happen?"
            autoFocus
            className="w-full outline-none"
            style={inputStyle}
          />
        </Field>

        {/* Description */}
        <Field label="Description" hint="optional">
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Repro steps, links, context…"
            rows={3}
            className="w-full outline-none resize-y"
            style={{ ...inputStyle, minHeight: 80, lineHeight: 1.55, fontSize: 13 }}
          />
        </Field>

        {/* Priority + Due date */}
        <div className="grid gap-3" style={{ gridTemplateColumns: '1fr 1fr' }}>
          <Field label="Priority">
            <ChipGroup>
              {(['low', 'med', 'high'] as TaskPriority[]).map((p) => (
                <Chip key={p} on={priority === p} onClick={() => setPriority(p)}>
                  <Glyph>{p === 'low' ? '·' : p === 'med' ? '=' : '!!'}</Glyph>
                  {p === 'low' ? 'Low' : p === 'med' ? 'Med' : 'High'}
                </Chip>
              ))}
            </ChipGroup>
          </Field>

          <Field label="Due date">
            <Popover>
              <PopoverTrigger asChild>
                <button className="w-full text-left" style={inputStyle}>
                  {dueDate ? format(dueDate, 'MMM d, yyyy') : (
                    <span style={{ color: 'var(--owl-text-label)' }}>
                      e.g. Apr 25 · next fri
                    </span>
                  )}
                </button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0" align="start">
                <Calendar mode="single" selected={dueDate} onSelect={setDueDate} />
              </PopoverContent>
            </Popover>
          </Field>
        </div>

        {/* Column + Assignees */}
        <div className="grid gap-3 mt-3" style={{ gridTemplateColumns: '1fr 1fr' }}>
          <Field label="Column">
            <ChipGroup>
              {COLUMNS.filter((c) => c.id !== 'done').map((c) => (
                <Chip key={c.id} on={column === c.id} onClick={() => setColumn(c.id)}>
                  {c.label}
                </Chip>
              ))}
            </ChipGroup>
          </Field>

          <Field label="Assignee">
            <ChipGroup>
              {members.slice(0, 5).map((m) => (
                <Chip
                  key={m.id}
                  on={assigneeIds.includes(m.id)}
                  onClick={() => toggleAssignee(m.id)}
                >
                  <Avatar me={m.id === currentMemberId}>{m.initials}</Avatar>
                  {m.id === currentMemberId ? 'Me' : m.initials}
                </Chip>
              ))}
            </ChipGroup>
          </Field>
        </div>

        {/* Privacy */}
        <div className="mt-[14px]">
          <label
            className="flex items-center justify-between cursor-pointer"
            style={{
              fontSize: 12,
              color: 'var(--owl-text-secondary)',
              padding: '8px 12px',
              borderRadius: 8,
              background: isPrivate ? 'rgba(210,230,50,0.06)' : 'rgba(15,51,51,0.4)',
              border: `1px solid ${isPrivate ? 'rgba(210,230,50,0.3)' : 'var(--owl-line)'}`,
            }}
          >
            <span className="inline-flex items-center gap-2">
              <Lock
                className="w-3.5 h-3.5"
                style={{ color: isPrivate ? 'var(--owl-neon)' : 'var(--owl-text-muted)' }}
              />
              Private — only you and selected people can see this
            </span>
            <input
              type="checkbox"
              checked={isPrivate}
              onChange={(e) => setIsPrivate(e.target.checked)}
              style={{ accentColor: 'var(--owl-neon)' }}
            />
          </label>
          {isPrivate && (
            <div className="mt-[10px]">
              <div
                className="mb-[6px]"
                style={{
                  fontSize: 10,
                  fontWeight: 600,
                  letterSpacing: '2.5px',
                  textTransform: 'uppercase',
                  color: 'var(--owl-text-label)',
                }}
              >
                Shared with
              </div>
              <ChipGroup>
                {members
                  .filter((m) => m.id !== currentMemberId)
                  .map((m) => (
                    <Chip
                      key={m.id}
                      on={participantIds.includes(m.id)}
                      onClick={() => toggleParticipant(m.id)}
                    >
                      <Avatar>{m.initials}</Avatar>
                      {m.name}
                    </Chip>
                  ))}
              </ChipGroup>
              {participantIds.length === 0 && (
                <div
                  className="mt-[6px]"
                  style={{
                    fontFamily: 'var(--owl-font-mono)',
                    fontSize: 10,
                    color: 'var(--owl-warning)',
                  }}
                >
                  Pick at least one person to share with
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between gap-2 mt-[18px] flex-wrap">
          <span
            style={{
              fontFamily: 'var(--owl-font-mono)',
              fontSize: 10,
              color: 'var(--owl-text-label)',
            }}
          >
            ⏎ to create · ⌘⏎ to create & close
          </span>
          <div className="flex gap-2">
            <button
              onClick={handleClose}
              style={{
                fontSize: 13,
                background: 'transparent',
                border: 'none',
                color: 'var(--owl-text-muted)',
                padding: '9px 14px',
                cursor: 'pointer',
              }}
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              disabled={saving || !title.trim()}
              style={{
                fontSize: 13,
                fontWeight: 500,
                padding: '9px 16px',
                background: 'var(--owl-neon)',
                color: '#0a2828',
                border: 'none',
                borderRadius: 8,
                cursor: title.trim() ? 'pointer' : 'not-allowed',
                opacity: title.trim() ? 1 : 0.5,
              }}
            >
              {saving ? 'Creating…' : 'Create card'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  background: 'rgba(15,51,51,0.6)',
  border: 'none',
  color: 'var(--owl-text-primary)',
  font: 'inherit',
  fontSize: 14,
  padding: '10px 12px',
  borderRadius: 8,
};

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="mt-[14px]">
      <label
        className="block mb-[6px]"
        style={{
          fontSize: 10,
          fontWeight: 600,
          letterSpacing: '2.5px',
          textTransform: 'uppercase',
          color: 'var(--owl-text-label)',
        }}
      >
        {label}
        {hint && (
          <span
            style={{
              color: 'var(--owl-text-muted)',
              fontWeight: 400,
              letterSpacing: 'normal',
              textTransform: 'none',
              marginLeft: 6,
            }}
          >
            · {hint}
          </span>
        )}
      </label>
      {children}
    </div>
  );
}

function ChipGroup({ children }: { children: React.ReactNode }) {
  return <div className="flex gap-[5px] flex-wrap">{children}</div>;
}

function Chip({
  on,
  onClick,
  children,
}: {
  on?: boolean;
  onClick?: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      type="button"
      className="inline-flex items-center gap-[5px] rounded-full transition-colors"
      style={{
        fontSize: 12,
        padding: '6px 12px',
        background: on ? 'rgba(210,230,50,0.1)' : 'rgba(15,51,51,0.6)',
        color: on ? 'var(--owl-neon)' : 'var(--owl-text-muted)',
        border: 'none',
        cursor: 'pointer',
      }}
    >
      {children}
    </button>
  );
}

function Glyph({ children }: { children: React.ReactNode }) {
  return (
    <span style={{ fontFamily: 'var(--owl-font-mono)', fontSize: 11, opacity: 0.7 }}>
      {children}
    </span>
  );
}

function Avatar({ me, children }: { me?: boolean; children: React.ReactNode }) {
  return (
    <span
      className="inline-flex items-center justify-center rounded-full"
      style={{
        width: 16,
        height: 16,
        margin: '-3px 0 -3px -2px',
        fontFamily: 'var(--owl-font-mono)',
        fontSize: 10,
        fontWeight: 500,
        background: me ? 'var(--owl-neon)' : 'var(--owl-elevated)',
        color: me ? '#0a2828' : 'var(--owl-text-primary)',
        border: '1px solid var(--owl-dash)',
      }}
    >
      {children}
    </span>
  );
}
