import { useState, useEffect } from 'react';
import { X } from 'lucide-react';
import { toast } from 'sonner';
import { CardForm, EMPTY_DRAFT, type CardDraft } from './CardForm';
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
  const [draft, setDraft] = useState<CardDraft>({
    ...EMPTY_DRAFT,
    priority: defaultPriority,
    column: defaultColumn,
    assignee_id: currentMemberId ?? null,
  });
  const [isClosing, setIsClosing] = useState(false);
  const [saving, setSaving] = useState(false);

  const updateDraft = (patch: Partial<CardDraft>) =>
    setDraft((prev) => ({ ...prev, ...patch }));

  const handleClose = () => {
    setIsClosing(true);
    setTimeout(onClose, 200);
  };

  const handleSave = async () => {
    if (!draft.title.trim()) {
      toast.error('Title is required');
      return;
    }
    setSaving(true);
    try {
      await onSave({
        title: draft.title.trim(),
        column: draft.column,
        priority: draft.priority,
        assignee_ids: draft.assignee_id ? [draft.assignee_id] : [],
        assignee_id: draft.assignee_id,
        due_date: draft.due_date,
        description: draft.description,
        created_by: currentMemberId,
        recurrence: draft.recurrence,
      });
      toast.success('Task created');
      handleClose();
    } catch {
      toast.error('Failed to create task');
    } finally {
      setSaving(false);
    }
  };

  // Esc to close, Cmd/Ctrl+Enter to submit
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') handleClose();
      if (
        e.key === 'Enter' &&
        (e.metaKey || e.ctrlKey) &&
        draft.title.trim()
      ) {
        e.preventDefault();
        handleSave();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draft]);

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
        className="w-full"
        style={{
          maxWidth: 640,
          background: 'var(--owl-surface)',
          border: '1px solid var(--owl-line-bright)',
          borderRadius: 8,
          padding: 14,
          display: 'flex',
          flexDirection: 'column',
          gap: 12,
          boxShadow: '0 20px 60px rgba(0,0,0,0.5), 0 6px 20px rgba(0,0,0,0.35)',
          animation: 'owl-fade-up 0.2s ease',
        }}
      >
        {/* Close button (top-right, no chrome) */}
        <div className="flex items-center">
          <span
            style={{
              fontFamily: 'var(--owl-font-mono)',
              fontSize: 9,
              fontWeight: 500,
              letterSpacing: '1.4px',
              textTransform: 'uppercase',
              color: 'var(--owl-text-label)',
            }}
          >
            New card
          </span>
          <span className="flex-1" />
          <button
            onClick={handleClose}
            aria-label="Close"
            style={{
              background: 'transparent',
              border: 'none',
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
            <X className="w-3 h-3" /> esc
          </button>
        </div>

        {/* Shared card body */}
        <CardForm draft={draft} onChange={updateDraft} members={members} mode="new" />

        {/* Footer actions */}
        <div className="flex items-center gap-2 flex-wrap">
          <span
            style={{
              fontFamily: 'var(--owl-font-mono)',
              fontSize: 10,
              color: 'var(--owl-text-label)',
            }}
          >
            ⌘⏎ to create
          </span>
          <span className="flex-1" />
          <button
            onClick={handleClose}
            type="button"
            style={{
              border: '1px solid var(--owl-line-bright)',
              background: 'rgba(15,51,51,0.6)',
              color: 'var(--owl-text-secondary)',
              padding: '6px 11px',
              borderRadius: 5,
              cursor: 'pointer',
              fontSize: 11,
              fontWeight: 500,
            }}
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={saving || !draft.title.trim()}
            type="button"
            style={{
              border: '1px solid var(--owl-neon)',
              background: 'var(--owl-neon)',
              color: '#0a2828',
              padding: '6px 11px',
              borderRadius: 5,
              cursor: draft.title.trim() ? 'pointer' : 'not-allowed',
              fontSize: 11,
              fontWeight: 500,
              opacity: draft.title.trim() ? 1 : 0.5,
            }}
          >
            {saving ? 'Creating…' : '✓ Create card'}
          </button>
        </div>
      </div>
    </div>
  );
}
