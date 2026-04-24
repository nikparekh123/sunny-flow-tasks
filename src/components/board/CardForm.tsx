/**
 * Shared form body for both the new-task modal and the expand-in-place edit
 * view in PeopleView. Renders: type chip, editable title, editable desc,
 * metadata grid (Priority / Owner / Start / Due), and a recurring module
 * when type === 'recurring'. Caller wraps with actions (Create / Mark done /
 * Delete / etc.) and decides when to flush the draft to the server.
 */
import { useRef } from 'react';
import { Calendar as CalendarIcon } from 'lucide-react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { format, parseISO } from 'date-fns';
import { COLUMNS } from '@/lib/constants';
import type {
  TaskPriority,
  TaskColumn,
  TeamMember,
} from '@/lib/types';

export type CardType = 'task' | 'recurring';

export interface CardDraft {
  title: string;
  description: string | null;
  priority: TaskPriority;
  assignee_id: string | null;
  due_date: string | null; // YYYY-MM-DD
  recurrence: string | null;
  column: TaskColumn;
}

export const EMPTY_DRAFT: CardDraft = {
  title: '',
  description: null,
  priority: 'med',
  assignee_id: null,
  due_date: null,
  recurrence: null,
  column: 'todo',
};

const PRI_LABEL: Record<string, string> = { high: 'HIGH', med: 'MED', low: 'LOW' };

const AVATAR_COLORS = ['#c85a7a', '#5a8ac8', '#7aa878', '#c8a05a', '#a090e0', '#e0a070'];
function avatarColor(id: string): string {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return AVATAR_COLORS[h % AVATAR_COLORS.length];
}

function cycleNext<T>(list: T[], current: T): T {
  const idx = list.indexOf(current);
  return list[(idx + 1) % list.length];
}

interface CardFormProps {
  draft: CardDraft;
  onChange: (patch: Partial<CardDraft>) => void;
  members: TeamMember[];
  mode: 'new' | 'edit';
  startDisplay?: string | null; // for edit mode, formatted created_at
}

export function CardForm({
  draft,
  onChange,
  members,
  mode,
  startDisplay,
}: CardFormProps) {
  const titleRef = useRef<HTMLHeadingElement | null>(null);
  const descRef = useRef<HTMLDivElement | null>(null);

  const type: CardType = draft.recurrence ? 'recurring' : 'task';
  const typeTagBg =
    type === 'recurring' ? 'rgba(160,144,224,0.15)' : 'rgba(210,230,50,0.1)';
  const typeTagColor = type === 'recurring' ? '#a090e0' : 'var(--owl-neon)';

  const toggleType = () => {
    if (type === 'recurring') onChange({ recurrence: null });
    else onChange({ recurrence: 'weekly' });
  };

  const cyclePriority = () => {
    const next = cycleNext<TaskPriority>(['high', 'med', 'low'], draft.priority);
    onChange({ priority: next });
  };

  const owner = members.find((m) => m.id === draft.assignee_id) || null;

  return (
    <div className="flex flex-col gap-3">
      {/* Type chip (clickable to toggle) */}
      <div className="flex items-start gap-[10px]">
        <button
          type="button"
          onClick={toggleType}
          title="Click to toggle recurring"
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
            border: 'none',
            cursor: 'pointer',
          }}
        >
          {type}
        </button>
        <span className="flex-1" />
      </div>

      {/* Title — editable. New mode uses a placeholder when empty. */}
      <h3
        ref={titleRef}
        contentEditable
        suppressContentEditableWarning
        data-placeholder={mode === 'new' ? 'What needs to happen?' : ''}
        onBlur={(e) => {
          const next = e.currentTarget.innerText.trim();
          if (next !== draft.title) onChange({ title: next });
        }}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            (e.currentTarget as HTMLElement).blur();
          }
        }}
        style={{
          fontSize: 18,
          fontWeight: 300,
          color: draft.title ? 'var(--owl-text-primary)' : 'var(--owl-text-label)',
          lineHeight: 1.35,
          letterSpacing: '-0.1px',
          outline: 'none',
          padding: '2px 4px',
          margin: '-2px -4px',
          borderRadius: 3,
          minHeight: '1.6em',
        }}
      >
        {draft.title}
      </h3>

      {/* Description — editable */}
      <div
        ref={descRef}
        contentEditable
        suppressContentEditableWarning
        data-placeholder="Add a description…"
        onBlur={(e) => {
          const next = e.currentTarget.innerText.trim();
          if (next !== (draft.description || '')) {
            onChange({ description: next || null });
          }
        }}
        style={{
          fontSize: 13,
          color: draft.description ? 'var(--owl-text-secondary)' : 'var(--owl-text-invisible)',
          fontStyle: draft.description ? 'normal' : 'italic',
          lineHeight: 1.55,
          outline: 'none',
          padding: '6px 8px',
          margin: '0 -8px',
          borderRadius: 4,
          minHeight: '1.6em',
        }}
      >
        {draft.description || ''}
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
          <button
            type="button"
            onClick={cyclePriority}
            title="Click to cycle"
            style={{
              cursor: 'pointer',
              display: 'inline-flex',
              alignItems: 'center',
              gap: 5,
              fontFamily: 'var(--owl-font-mono)',
              fontSize: 11,
              color:
                draft.priority === 'high'
                  ? 'var(--owl-negative)'
                  : draft.priority === 'med'
                  ? 'var(--owl-positive)'
                  : 'var(--owl-text-muted)',
              background: 'transparent',
              border: 'none',
              padding: 0,
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
            {PRI_LABEL[draft.priority]}
          </button>
        </MetaField>

        <MetaField label="Owner">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                style={{
                  cursor: 'pointer',
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 5,
                  background: 'transparent',
                  border: 'none',
                  padding: 0,
                }}
              >
                {owner ? (
                  <>
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
                        background: avatarColor(owner.id),
                      }}
                    >
                      {owner.initials}
                    </span>
                    <span style={{ color: 'var(--owl-text-primary)', fontSize: 12 }}>
                      {owner.name}
                    </span>
                  </>
                ) : (
                  <span
                    style={{
                      color: 'var(--owl-text-label)',
                      fontSize: 12,
                    }}
                  >
                    Pick someone
                  </span>
                )}
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start">
              {members.map((m) => (
                <DropdownMenuItem
                  key={m.id}
                  onClick={() => onChange({ assignee_id: m.id })}
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
                      background: avatarColor(m.id),
                      marginRight: 8,
                    }}
                  >
                    {m.initials}
                  </span>
                  {m.name}
                </DropdownMenuItem>
              ))}
              {owner && (
                <DropdownMenuItem onClick={() => onChange({ assignee_id: null })}>
                  <span
                    style={{
                      width: 18,
                      height: 18,
                      marginRight: 8,
                      display: 'inline-block',
                    }}
                  />
                  <span style={{ color: 'var(--owl-text-muted)' }}>Unassign</span>
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </MetaField>

        <MetaField label="Status">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                style={{
                  cursor: 'pointer',
                  fontFamily: 'var(--owl-font-mono)',
                  fontSize: 11,
                  color: 'var(--owl-text-primary)',
                  background: 'transparent',
                  border: 'none',
                  padding: 0,
                }}
              >
                {COLUMNS.find((c) => c.id === draft.column)?.label ?? draft.column}
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start">
              {COLUMNS.map((c) => (
                <DropdownMenuItem
                  key={c.id}
                  onClick={() => onChange({ column: c.id })}
                >
                  <span
                    className="w-2 h-2 rounded-full mr-2"
                    style={{ background: c.color }}
                  />
                  {c.label}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        </MetaField>

        <MetaField label="Due">
          <Popover>
            <PopoverTrigger asChild>
              <button
                type="button"
                style={{
                  cursor: 'pointer',
                  fontFamily: 'var(--owl-font-mono)',
                  fontSize: 11,
                  color: draft.due_date
                    ? 'var(--owl-text-primary)'
                    : 'var(--owl-text-label)',
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 4,
                  background: 'transparent',
                  border: 'none',
                  padding: 0,
                }}
              >
                <CalendarIcon className="w-3 h-3" />
                {draft.due_date
                  ? format(parseISO(draft.due_date), 'MMM d, yyyy')
                  : 'No due date'}
              </button>
            </PopoverTrigger>
            <PopoverContent className="w-auto p-0" align="start">
              <Calendar
                mode="single"
                selected={draft.due_date ? parseISO(draft.due_date) : undefined}
                onSelect={(d) =>
                  onChange({ due_date: d ? format(d, 'yyyy-MM-dd') : null })
                }
              />
            </PopoverContent>
          </Popover>
        </MetaField>

        {mode === 'edit' && startDisplay && (
          <MetaField label="Start">
            <span
              style={{
                fontFamily: 'var(--owl-font-mono)',
                fontSize: 11,
                color: 'var(--owl-text-muted)',
              }}
            >
              {startDisplay}
            </span>
          </MetaField>
        )}
      </div>

      {/* Recurring module */}
      {type === 'recurring' && (
        <RecurringModule
          recurrence={draft.recurrence}
          onChange={(next) => onChange({ recurrence: next })}
        />
      )}
    </div>
  );
}

// ── Metadata row helper ─────────────────────────────────────────────────────
function MetaField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline gap-2" style={{ fontSize: 11, minWidth: 0 }}>
      <span
        style={{
          fontSize: 9,
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

// ── Recurring cadence picker ────────────────────────────────────────────────
const WEEKDAYS: { id: string; label: string }[] = [
  { id: 'mon', label: 'M' },
  { id: 'tue', label: 'T' },
  { id: 'wed', label: 'W' },
  { id: 'thu', label: 'T' },
  { id: 'fri', label: 'F' },
  { id: 'sat', label: 'S' },
  { id: 'sun', label: 'S' },
];
const FREQUENCIES = ['daily', 'weekly', 'biweekly', 'monthly', 'custom'] as const;
type Frequency = (typeof FREQUENCIES)[number];

function parseRecurrence(rec: string | null): {
  frequency: Frequency;
  customDays: string[];
  customDayOfMonth: string;
} {
  if (!rec) return { frequency: 'weekly', customDays: [], customDayOfMonth: '' };
  if (rec.startsWith('custom:')) {
    try {
      const config = JSON.parse(rec.slice(7));
      return {
        frequency: 'custom',
        customDays: config.days || [],
        customDayOfMonth: config.dayOfMonth?.toString() || '',
      };
    } catch {
      return { frequency: 'weekly', customDays: [], customDayOfMonth: '' };
    }
  }
  return { frequency: rec as Frequency, customDays: [], customDayOfMonth: '' };
}

function serializeRecurrence(
  frequency: Frequency,
  customDays: string[],
  customDayOfMonth: string,
): string {
  if (frequency === 'custom') {
    const cfg: Record<string, unknown> = {};
    if (customDays.length) cfg.days = customDays;
    const dom = parseInt(customDayOfMonth, 10);
    if (!isNaN(dom) && dom >= 1 && dom <= 31) cfg.dayOfMonth = dom;
    return `custom:${JSON.stringify(cfg)}`;
  }
  return frequency;
}

function RecurringModule({
  recurrence,
  onChange,
}: {
  recurrence: string | null;
  onChange: (next: string) => void;
}) {
  const parsed = parseRecurrence(recurrence);

  const update = (patch: Partial<ReturnType<typeof parseRecurrence>>) => {
    const next = { ...parsed, ...patch };
    onChange(serializeRecurrence(next.frequency, next.customDays, next.customDayOfMonth));
  };

  const toggleWeekday = (id: string) => {
    const next = parsed.customDays.includes(id)
      ? parsed.customDays.filter((d) => d !== id)
      : [...parsed.customDays, id];
    update({ customDays: next });
  };

  return (
    <div
      style={{
        background: 'rgba(0,0,0,0.18)',
        borderLeft: '2px solid #a090e0',
        borderRadius: 5,
        padding: '10px 12px',
        fontSize: 11.5,
        color: 'var(--owl-text-secondary)',
        display: 'flex',
        flexDirection: 'column',
        gap: 8,
      }}
    >
      <span
        style={{
          fontSize: 9,
          fontWeight: 600,
          letterSpacing: '1.5px',
          textTransform: 'uppercase',
          color: 'var(--owl-text-label)',
        }}
      >
        Recurrence
      </span>

      <div className="flex gap-[5px] flex-wrap">
        {FREQUENCIES.map((f) => (
          <button
            key={f}
            type="button"
            onClick={() => update({ frequency: f })}
            style={{
              fontSize: 11,
              padding: '4px 10px',
              borderRadius: 100,
              background:
                parsed.frequency === f
                  ? 'rgba(160,144,224,0.15)'
                  : 'rgba(15,51,51,0.6)',
              color:
                parsed.frequency === f ? '#a090e0' : 'var(--owl-text-muted)',
              border: 'none',
              cursor: 'pointer',
              textTransform: 'capitalize',
            }}
          >
            {f === 'biweekly' ? 'Bi-weekly' : f}
          </button>
        ))}
      </div>

      {parsed.frequency === 'custom' && (
        <div className="flex flex-col gap-2">
          <div>
            <div
              style={{
                fontSize: 9,
                fontWeight: 600,
                letterSpacing: '1.5px',
                textTransform: 'uppercase',
                color: 'var(--owl-text-label)',
                marginBottom: 4,
              }}
            >
              Repeat on
            </div>
            <div className="flex gap-1">
              {WEEKDAYS.map((d) => {
                const on = parsed.customDays.includes(d.id);
                return (
                  <button
                    key={d.id}
                    type="button"
                    onClick={() => toggleWeekday(d.id)}
                    style={{
                      width: 26,
                      height: 26,
                      borderRadius: '50%',
                      fontSize: 11,
                      fontWeight: 500,
                      background: on ? 'rgba(160,144,224,0.2)' : 'rgba(15,51,51,0.6)',
                      color: on ? '#a090e0' : 'var(--owl-text-muted)',
                      border: 'none',
                      cursor: 'pointer',
                    }}
                  >
                    {d.label}
                  </button>
                );
              })}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <div
              style={{
                fontSize: 9,
                fontWeight: 600,
                letterSpacing: '1.5px',
                textTransform: 'uppercase',
                color: 'var(--owl-text-label)',
              }}
            >
              Day of month
            </div>
            <input
              type="number"
              min={1}
              max={31}
              value={parsed.customDayOfMonth}
              onChange={(e) => update({ customDayOfMonth: e.target.value })}
              placeholder="—"
              style={{
                width: 60,
                fontFamily: 'var(--owl-font-mono)',
                fontSize: 12,
                padding: '4px 8px',
                background: 'rgba(15,51,51,0.6)',
                color: 'var(--owl-text-primary)',
                border: 'none',
                borderRadius: 6,
                outline: 'none',
              }}
            />
            <span style={{ fontSize: 10, color: 'var(--owl-text-label)' }}>
              optional
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
