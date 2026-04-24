import { useMemo } from 'react';
import { differenceInCalendarDays, startOfDay, subDays } from 'date-fns';
import type { TaskWithDetail } from '@/lib/types';

interface SidebarProps {
  tasks: TaskWithDetail[];
}

export function Sidebar({ tasks }: SidebarProps) {
  const stats = useMemo(() => {
    const today = startOfDay(new Date());
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
    <aside
      className="hidden md:flex flex-col gap-5 sticky top-0 h-screen px-[14px] py-5 border-r"
      style={{
        background: 'var(--owl-dash)',
        borderRightColor: 'rgba(255,255,255,0.03)',
        width: 240,
        minWidth: 240,
      }}
    >
      {/* Brand */}
      <div className="flex items-center gap-[9px] px-[6px] py-[2px]">
        <div
          style={{
            width: 18,
            height: 18,
            background: 'var(--owl-neon)',
            borderRadius: 2,
            transform: 'rotate(10deg)',
            boxShadow: '0 0 0 2px rgba(210,230,50,0.15)',
          }}
        />
        <div
          className="text-[13px] font-bold tracking-[0.5px]"
          style={{ color: 'var(--owl-text-primary)' }}
        >
          S To dos
          <span
            className="inline-block align-[-2px] ml-[1px]"
            style={{
              width: 2,
              height: '0.8em',
              background: 'var(--owl-neon)',
              animation: 'owl-blink 1s step-end infinite',
            }}
          />
        </div>
      </div>

      {/* Activity stats */}
      <div className="flex flex-col gap-[14px] px-[6px]">
        <SectionLabel>Activity</SectionLabel>
        <Stat label="Active" value={stats.active} />
        <Stat
          label="Due this week"
          value={stats.dueWeek}
          tone={stats.dueWeek > 0 ? 'warn' : undefined}
        />
        <Stat
          label="Overdue"
          value={stats.overdue}
          tone={stats.overdue > 0 ? 'neg' : undefined}
        />
        <Stat
          label="On-time · 30d"
          value={stats.onTimePct === null ? '—' : `${stats.onTimePct}%`}
        />
      </div>

    </aside>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="mb-1"
      style={{
        fontSize: 10,
        fontWeight: 600,
        letterSpacing: '2.5px',
        textTransform: 'uppercase',
        color: 'var(--owl-text-label)',
      }}
    >
      {children}
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
    <div className="flex items-baseline justify-between gap-2">
      <span
        style={{
          fontSize: 11,
          color: 'var(--owl-text-muted)',
        }}
      >
        {label}
      </span>
      <span
        style={{
          fontFamily: 'var(--owl-font-mono)',
          fontSize: 16,
          fontWeight: 500,
          letterSpacing: '-0.3px',
          color,
        }}
      >
        {value}
      </span>
    </div>
  );
}

