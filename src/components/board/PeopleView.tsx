import { useMemo } from 'react';
import { differenceInCalendarDays, format, startOfDay, subDays } from 'date-fns';
import type { TaskWithDetail, TeamMember } from '@/lib/types';
import { COLUMNS } from '@/lib/constants';

interface Props {
  tasks: TaskWithDetail[];
  members: TeamMember[];
  onTaskClick: (task: TaskWithDetail) => void;
  currentMemberId: string | null;
}

export function PeopleView({ tasks, members, onTaskClick, currentMemberId }: Props) {
  const today = startOfDay(new Date());

  const perMember = useMemo(() => {
    const thirtyDaysAgo = subDays(today, 30);
    return members.map((m) => {
      const assigned = tasks.filter(
        (t) => t.assignee_ids?.includes(m.id) || t.assignee_id === m.id,
      );
      const active = assigned.filter((t) => t.column !== 'done');
      const high = active.filter((t) => t.priority === 'high').length;
      const med = active.filter((t) => t.priority === 'med').length;
      const low = active.filter((t) => t.priority === 'low').length;
      const dueSoon = active.filter((t) => {
        if (!t.due_date) return false;
        const d = differenceInCalendarDays(new Date(t.due_date), today);
        return d >= 0 && d <= 3;
      }).length;
      const shipped30d = assigned.filter(
        (t) =>
          t.column === 'done' && t.completed_at && new Date(t.completed_at) >= thirtyDaysAgo,
      ).length;
      return { member: m, assigned, active, high, med, low, dueSoon, shipped30d };
    });
  }, [tasks, members, today]);

  return (
    <div className="px-5 md:px-7 pb-4">
      <div
        className="grid gap-[14px] pt-4"
        style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))' }}
      >
        {perMember.map(({ member, assigned, active, high, med, low, dueSoon, shipped30d }) => {
          const total = active.length || 1;
          const hiPct = (high / total) * 100;
          const mdPct = (med / total) * 100;
          const loPct = (low / total) * 100;
          const sorted = [...assigned].sort((a, b) => {
            const order = { high: 0, med: 1, low: 2 } as const;
            if (a.column === 'done' && b.column !== 'done') return 1;
            if (b.column === 'done' && a.column !== 'done') return -1;
            return (order[a.priority] ?? 3) - (order[b.priority] ?? 3);
          });
          return (
            <div
              key={member.id}
              className="flex flex-col gap-3 rounded-xl p-4"
              style={{
                background: 'var(--owl-card-elevated)',
                border: '1px solid var(--owl-line)',
              }}
            >
              {/* Header */}
              <div className="flex items-center gap-3">
                <span
                  className="inline-flex items-center justify-center rounded-full"
                  style={{
                    width: 38,
                    height: 38,
                    fontFamily: 'var(--owl-font-mono)',
                    fontSize: 13,
                    fontWeight: 500,
                    background:
                      member.id === currentMemberId ? 'var(--owl-neon)' : 'var(--owl-elevated)',
                    color:
                      member.id === currentMemberId ? '#0a2828' : 'var(--owl-text-primary)',
                    border: '2px solid var(--owl-dash)',
                  }}
                >
                  {member.initials}
                </span>
                <div>
                  <div
                    style={{
                      fontSize: 15,
                      fontWeight: 500,
                      color: 'var(--owl-text-primary)',
                      letterSpacing: '-0.2px',
                    }}
                  >
                    {member.name}
                  </div>
                  <div
                    style={{
                      fontSize: 10,
                      fontWeight: 500,
                      letterSpacing: '1.2px',
                      textTransform: 'uppercase',
                      color: 'var(--owl-text-label)',
                      marginTop: 2,
                    }}
                  >
                    {member.role === 'admin' ? 'Admin' : 'Member'}
                  </div>
                </div>
              </div>

              {/* Stats */}
              <div
                className="flex gap-[14px] py-2"
                style={{
                  borderTop: '1px solid var(--owl-line)',
                  borderBottom: '1px solid var(--owl-line)',
                }}
              >
                <PStat n={active.length} k="Active" />
                <PStat n={high} k="High" tone={high > 0 ? 'neg' : undefined} />
                <PStat n={dueSoon} k="Due ≤3d" tone={dueSoon > 0 ? 'warn' : undefined} />
                <PStat n={`+${shipped30d}`} k="30d shipped" tone="pos" />
              </div>

              {/* Load bar */}
              {active.length > 0 && (
                <div
                  className="rounded-sm overflow-hidden flex"
                  style={{ height: 3, background: 'rgba(15,51,51,0.8)' }}
                >
                  {hiPct > 0 && (
                    <span style={{ width: `${hiPct}%`, background: 'var(--owl-negative)' }} />
                  )}
                  {mdPct > 0 && (
                    <span style={{ width: `${mdPct}%`, background: 'var(--owl-warning)' }} />
                  )}
                  {loPct > 0 && (
                    <span style={{ width: `${loPct}%`, background: 'var(--owl-text-muted)' }} />
                  )}
                </div>
              )}

              {/* Cards */}
              <div
                className="flex flex-col gap-[6px]"
                style={{ maxHeight: 320, overflowY: 'auto' }}
              >
                {sorted.length === 0 ? (
                  <div
                    className="text-[11px] italic p-2"
                    style={{ color: 'var(--owl-text-label)' }}
                  >
                    No cards assigned.
                  </div>
                ) : (
                  sorted.map((t) => (
                    <PersonCard key={t.id} task={t} onClick={() => onTaskClick(t)} />
                  ))
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function PStat({
  n,
  k,
  tone,
}: {
  n: number | string;
  k: string;
  tone?: 'neg' | 'warn' | 'pos';
}) {
  const color =
    tone === 'neg'
      ? 'var(--owl-negative)'
      : tone === 'warn'
      ? 'var(--owl-warning)'
      : tone === 'pos'
      ? 'var(--owl-positive)'
      : 'var(--owl-text-primary)';
  return (
    <div className="flex flex-col gap-[1px]">
      <div
        style={{
          fontFamily: 'var(--owl-font-mono)',
          fontSize: 16,
          fontWeight: 500,
          letterSpacing: '-0.3px',
          color,
        }}
      >
        {n}
      </div>
      <div
        style={{
          fontSize: 8,
          fontWeight: 600,
          letterSpacing: '1.5px',
          textTransform: 'uppercase',
          color: 'var(--owl-text-label)',
        }}
      >
        {k}
      </div>
    </div>
  );
}

function PersonCard({ task, onClick }: { task: TaskWithDetail; onClick: () => void }) {
  const today = startOfDay(new Date());
  const priClass =
    task.column === 'done'
      ? 'done'
      : task.priority === 'high'
      ? 'hi'
      : task.priority === 'med'
      ? 'md'
      : 'lo';
  const barColor =
    priClass === 'done'
      ? 'var(--owl-positive)'
      : priClass === 'hi'
      ? 'var(--owl-negative)'
      : priClass === 'md'
      ? 'var(--owl-warning)'
      : 'var(--owl-text-muted)';
  const dueLabel = (() => {
    if (!task.due_date) return '—';
    const d = differenceInCalendarDays(new Date(task.due_date), today);
    if (task.column === 'done') return format(new Date(task.due_date), 'MMM d');
    if (d === 0) return 'Today';
    if (d < 0) return `${Math.abs(d)}d over`;
    return format(new Date(task.due_date), 'MMM d');
  })();
  const dueTone =
    task.column === 'done'
      ? 'var(--owl-text-muted)'
      : !task.due_date
      ? 'var(--owl-text-label)'
      : differenceInCalendarDays(new Date(task.due_date), today) < 0
      ? 'var(--owl-negative)'
      : differenceInCalendarDays(new Date(task.due_date), today) <= 3
      ? 'var(--owl-warning)'
      : 'var(--owl-text-muted)';
  const colLabel = COLUMNS.find((c) => c.id === task.column)?.label ?? task.column;
  const prLabel = task.priority === 'high' ? 'High' : task.priority === 'med' ? 'Med' : 'Low';

  return (
    <button
      onClick={onClick}
      className="grid items-center gap-[9px] px-[10px] py-[7px] rounded-md text-left transition-colors"
      style={{
        gridTemplateColumns: '6px 1fr auto',
        background: 'rgba(15,51,51,0.5)',
      }}
      onMouseEnter={(e) => (e.currentTarget.style.background = 'rgba(30,90,80,0.25)')}
      onMouseLeave={(e) => (e.currentTarget.style.background = 'rgba(15,51,51,0.5)')}
    >
      <span
        className="rounded-sm"
        style={{ width: 3, height: 24, background: barColor }}
      />
      <span className="min-w-0">
        <div
          className="truncate"
          style={{
            fontSize: 12.5,
            color: task.column === 'done' ? 'var(--owl-text-muted)' : 'var(--owl-text-primary)',
            textDecoration: task.column === 'done' ? 'line-through' : 'none',
          }}
        >
          {task.title}
        </div>
        <div
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 9.5,
            color: 'var(--owl-text-label)',
            letterSpacing: '0.3px',
            marginTop: 2,
            textTransform: 'uppercase',
          }}
        >
          {colLabel} · {prLabel}
        </div>
      </span>
      <span
        style={{
          fontFamily: 'var(--owl-font-mono)',
          fontSize: 10,
          color: dueTone,
          textAlign: 'right',
        }}
      >
        {dueLabel}
      </span>
    </button>
  );
}
