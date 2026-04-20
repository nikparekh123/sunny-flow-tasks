import { useMemo } from 'react';
import { differenceInCalendarDays, startOfDay, subDays } from 'date-fns';
import type { TaskWithDetail } from '@/lib/types';

interface Props {
  tasks: TaskWithDetail[];
}

export function BoardHeader({ tasks }: Props) {
  const stats = useMemo(() => {
    const now = new Date();
    const today = startOfDay(now);
    const active = tasks.filter((t) => t.column !== 'done').length;
    const dueWeek = tasks.filter((t) => {
      if (!t.due_date || t.column === 'done') return false;
      const d = differenceInCalendarDays(new Date(t.due_date), today);
      return d >= 0 && d <= 7;
    }).length;
    const overdue = tasks.filter((t) => {
      if (!t.due_date || t.column === 'done') return false;
      return differenceInCalendarDays(new Date(t.due_date), today) < 0;
    }).length;
    const thirtyDaysAgo = subDays(today, 30);
    const recentDone = tasks.filter(
      (t) => t.column === 'done' && t.completed_at && new Date(t.completed_at) >= thirtyDaysAgo,
    );
    const onTime = recentDone.filter((t) => {
      if (!t.due_date || !t.completed_at) return true;
      return new Date(t.completed_at) <= new Date(t.due_date);
    }).length;
    const onTimePct = recentDone.length
      ? Math.round((onTime / recentDone.length) * 100)
      : null;
    return { active, dueWeek, overdue, onTimePct };
  }, [tasks]);

  return (
    <div className="px-5 md:px-7 pt-4 pb-[14px]" style={{ borderBottom: '1px solid var(--owl-line)' }}>
      {/* Breadcrumb + live */}
      <div className="flex items-center justify-between gap-4">
        <div
          className="hidden sm:block"
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            letterSpacing: '0.5px',
            color: 'var(--owl-text-disabled)',
          }}
        >
          workspace <span style={{ color: 'var(--owl-text-disabled)' }}>/</span>{' '}
          <b style={{ color: 'var(--owl-text-secondary)', fontWeight: 500 }}>product board</b>{' '}
          <span style={{ color: 'var(--owl-text-disabled)' }}>/</span> priority × status
        </div>
        <div
          className="inline-flex items-center gap-[6px]"
          style={{ fontSize: 11, color: 'var(--owl-text-muted)' }}
        >
          <span
            className="rounded-full"
            style={{
              width: 6,
              height: 6,
              background: 'var(--owl-text-muted)',
              animation: 'owl-pulse 2.5s ease-in-out infinite',
            }}
          />
          Live
        </div>
      </div>

      {/* Title + stats */}
      <div className="flex items-end justify-between gap-6 flex-wrap pt-2">
        <div>
          <h1
            style={{
              fontSize: 'clamp(26px, 3.6vw, 36px)',
              fontWeight: 300,
              letterSpacing: '-1.2px',
              lineHeight: 1,
              color: 'var(--owl-text-primary)',
            }}
          >
            Product <b style={{ fontWeight: 700 }}>board</b>
          </h1>
          <div
            className="max-w-[580px]"
            style={{ fontSize: 12, color: 'var(--owl-text-muted)', marginTop: 6 }}
          >
            Priority × status grid. Rows = how urgent, columns = where it is. Drop on a cell to set both at once.
          </div>
        </div>
        <div className="flex gap-6 items-center flex-wrap">
          <Stat label="Active" value={stats.active} />
          <Stat label="Due this week" value={stats.dueWeek} tone={stats.dueWeek > 0 ? 'warn' : undefined} />
          <Stat label="Overdue" value={stats.overdue} tone={stats.overdue > 0 ? 'neg' : undefined} />
          <Stat
            label="On-time · 30d"
            value={stats.onTimePct === null ? '—' : `${stats.onTimePct}%`}
          />
        </div>
      </div>
    </div>
  );
}

function Stat({
  label,
  value,
  tone,
}: {
  label: string;
  value: number | string;
  tone?: 'warn' | 'neg' | 'neon';
}) {
  const color =
    tone === 'warn'
      ? 'var(--owl-warning)'
      : tone === 'neg'
      ? 'var(--owl-negative)'
      : tone === 'neon'
      ? 'var(--owl-neon)'
      : 'var(--owl-text-primary)';
  return (
    <div className="flex flex-col gap-[2px]">
      <div
        style={{
          fontFamily: 'var(--owl-font-mono)',
          fontSize: 18,
          fontWeight: 500,
          letterSpacing: '-0.3px',
          color,
        }}
      >
        {value}
      </div>
      <div
        style={{
          fontSize: 9,
          fontWeight: 500,
          letterSpacing: '1.4px',
          textTransform: 'uppercase',
          color: 'var(--owl-text-disabled)',
        }}
      >
        {label}
      </div>
    </div>
  );
}
