import { useMemo } from 'react';
import { differenceInCalendarDays, subDays, startOfDay, formatDistanceToNowStrict } from 'date-fns';
import type { TaskWithDetail } from '@/lib/types';
import { COLUMNS } from '@/lib/constants';

interface Props {
  tasks: TaskWithDetail[];
}

export function FooterStatus({ tasks }: Props) {
  const stats = useMemo(() => {
    const today = startOfDay(new Date());
    const active = tasks.filter((t) => t.column !== 'done').length;
    const high = tasks.filter((t) => t.priority === 'high' && t.column !== 'done').length;
    const dueWeek = tasks.filter((t) => {
      if (!t.due_date || t.column === 'done') return false;
      const d = differenceInCalendarDays(new Date(t.due_date), today);
      return d >= 0 && d <= 7;
    }).length;
    const overdue = tasks.filter((t) => {
      if (!t.due_date || t.column === 'done') return false;
      return differenceInCalendarDays(new Date(t.due_date), today) < 0;
    }).length;

    // Throughput: completed in last 7 days
    const weekAgo = subDays(today, 7);
    const recent = tasks.filter(
      (t) => t.column === 'done' && t.completed_at && new Date(t.completed_at) >= weekAgo,
    );
    const throughput = recent.length;

    // Median cycle time (days) over completed tasks with created_at
    const cycles = tasks
      .filter((t) => t.column === 'done' && t.completed_at && t.created_at)
      .map((t) => {
        const start = new Date(t.created_at!).getTime();
        const end = new Date(t.completed_at!).getTime();
        return (end - start) / (1000 * 60 * 60 * 24);
      })
      .sort((a, b) => a - b);
    const median = cycles.length
      ? cycles.length % 2 === 0
        ? (cycles[cycles.length / 2 - 1] + cycles[cycles.length / 2]) / 2
        : cycles[(cycles.length - 1) / 2]
      : null;

    // Last move: most recently updated non-archived task
    const lastMoved = [...tasks]
      .filter((t) => t.updated_at)
      .sort((a, b) => new Date(b.updated_at!).getTime() - new Date(a.updated_at!).getTime())[0];

    return { active, high, dueWeek, overdue, throughput, median, lastMoved };
  }, [tasks]);

  const lastMoveLabel = stats.lastMoved
    ? `${COLUMNS.find((c) => c.id === stats.lastMoved!.column)?.label ?? stats.lastMoved.column} · ${formatDistanceToNowStrict(
        new Date(stats.lastMoved.updated_at!),
        { addSuffix: false },
      )}`
    : null;

  return (
    <div
      className="flex items-center gap-[14px] flex-wrap px-[14px] py-[10px] rounded-lg mx-5 md:mx-7 mb-4 mt-[18px]"
      style={{
        background: 'var(--owl-dash)',
        fontFamily: 'var(--owl-font-mono)',
        fontSize: 11,
        color: 'var(--owl-text-muted)',
      }}
    >
      <Item>
        <b style={{ color: 'var(--owl-text-primary)', fontWeight: 500 }}>{stats.active}</b> active
      </Item>
      <Sep />
      <Item>
        <b style={{ color: 'var(--owl-negative)', fontWeight: 500 }}>{stats.high}</b> high
      </Item>
      <Sep />
      <Item>
        <b style={{ color: 'var(--owl-warning)', fontWeight: 500 }}>{stats.dueWeek}</b> due ≤ 7d
      </Item>
      <Sep />
      <Item>
        <b style={{ color: 'var(--owl-negative)', fontWeight: 500 }}>{stats.overdue}</b> overdue
      </Item>
      <Sep />
      <Item>
        throughput{' '}
        <b style={{ color: 'var(--owl-positive)', fontWeight: 500 }}>{stats.throughput}/wk</b>
      </Item>
      {stats.median !== null && (
        <>
          <Sep />
          <Item>
            median cycle{' '}
            <b style={{ color: 'var(--owl-text-primary)', fontWeight: 500 }}>
              {stats.median.toFixed(1)}d
            </b>
          </Item>
        </>
      )}
      {lastMoveLabel && (
        <>
          <Sep />
          <Item>
            last move <b style={{ color: 'var(--owl-text-primary)', fontWeight: 500 }}>{lastMoveLabel}</b>
          </Item>
        </>
      )}
    </div>
  );
}

function Item({ children }: { children: React.ReactNode }) {
  return <span className="inline-flex items-center gap-[6px]">{children}</span>;
}
function Sep() {
  return <span style={{ color: 'var(--owl-text-disabled)' }}>·</span>;
}
