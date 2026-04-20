import { useMemo } from 'react';
import { differenceInCalendarDays } from 'date-fns';
import type { TaskWithDetail, TeamMember } from '@/lib/types';

interface SidebarProps {
  tasks: TaskWithDetail[];
  members: TeamMember[];
  currentMemberId: string | null;
  activeAssignee: string | null;
  onAssigneeFilter: (id: string | null) => void;
  onFilterPriority?: (priority: 'high' | null) => void;
  onOpenArchive: () => void;
  activePriorityFilter?: 'high' | null;
  showingArchive?: boolean;
}

export function Sidebar({
  tasks,
  members,
  currentMemberId,
  activeAssignee,
  onAssigneeFilter,
  onFilterPriority,
  onOpenArchive,
  activePriorityFilter,
  showingArchive,
}: SidebarProps) {
  const counts = useMemo(() => {
    const active = tasks.filter((t) => t.column !== 'done').length;
    const mine = currentMemberId
      ? tasks.filter(
          (t) =>
            t.column !== 'done' &&
            (t.assignee_ids?.includes(currentMemberId) || t.assignee_id === currentMemberId),
        ).length
      : 0;
    const high = tasks.filter((t) => t.priority === 'high' && t.column !== 'done').length;
    const now = new Date();
    const dueWeek = tasks.filter((t) => {
      if (!t.due_date || t.column === 'done') return false;
      const d = differenceInCalendarDays(new Date(t.due_date), now);
      return d >= 0 && d <= 7;
    }).length;
    const stale = tasks.filter((t) => {
      if (t.column === 'done' || !t.updated_at) return false;
      return differenceInCalendarDays(now, new Date(t.updated_at)) >= 3;
    }).length;
    return { active, mine, high, dueWeek, stale };
  }, [tasks, currentMemberId]);

  const teamLimit = 5;
  const teamSlice = members.slice(0, teamLimit);

  const isMineActive = activeAssignee === currentMemberId && currentMemberId !== null;
  const noFilter = !activePriorityFilter && !isMineActive && !showingArchive;

  return (
    <aside
      className="hidden md:flex flex-col gap-[18px] sticky top-0 h-screen px-[14px] py-5 border-r"
      style={{
        background: 'var(--owl-dash)',
        borderRightColor: 'rgba(255,255,255,0.03)',
        width: 220,
        minWidth: 220,
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
        <div className="text-[13px] font-bold tracking-[0.5px]" style={{ color: 'var(--owl-text-primary)' }}>
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

      {/* Workspace */}
      <div>
        <div
          className="text-[8px] font-semibold uppercase tracking-[3px] mx-[4px] mt-2 mb-1"
          style={{ color: 'var(--owl-elevated)' }}
        >
          Workspace
        </div>
        <nav className="flex flex-col gap-[2px]">
          <NavItem
            active={noFilter}
            onClick={() => {
              onAssigneeFilter(null);
              onFilterPriority?.(null);
            }}
            dotColor="var(--owl-neon)"
            count={counts.active}
          >
            Team to do's
          </NavItem>
          <NavItem
            active={isMineActive}
            onClick={() => onAssigneeFilter(isMineActive ? null : currentMemberId)}
            count={counts.mine}
          >
            My tasks
          </NavItem>
          <NavItem active={!!showingArchive} onClick={onOpenArchive}>
            Archived
          </NavItem>
        </nav>
      </div>

      {/* Filters */}
      <div>
        <div
          className="text-[8px] font-semibold uppercase tracking-[3px] mx-[4px] mt-2 mb-1"
          style={{ color: 'var(--owl-elevated)' }}
        >
          Filters
        </div>
        <nav className="flex flex-col gap-[2px]">
          <NavItem
            active={activePriorityFilter === 'high'}
            onClick={() =>
              onFilterPriority?.(activePriorityFilter === 'high' ? null : 'high')
            }
            dotColor="var(--owl-negative)"
            count={counts.high}
          >
            High priority
          </NavItem>
          <NavItem dotColor="var(--owl-warning)" count={counts.dueWeek}>
            Due this week
          </NavItem>
          <NavItem dotColor="var(--owl-text-muted)" count={counts.stale}>
            Stale ≥ 3d
          </NavItem>
        </nav>
      </div>

      {/* Team card */}
      <div
        className="mt-auto rounded-lg p-[10px_12px]"
        style={{
          border: '1px solid var(--owl-line)',
          background: 'rgba(15,51,51,0.4)',
        }}
      >
        <div
          className="text-[8px] font-semibold uppercase tracking-[2px] mb-[6px]"
          style={{ color: 'var(--owl-elevated)' }}
        >
          Team · {members.length} online
        </div>
        <div className="flex items-center mb-[8px]">
          {teamSlice.map((m, i) => (
            <span
              key={m.id}
              title={m.name}
              className="inline-flex items-center justify-center rounded-full"
              style={{
                width: 24,
                height: 24,
                fontFamily: 'var(--owl-font-mono)',
                fontSize: 10,
                fontWeight: 500,
                background: m.id === currentMemberId ? 'var(--owl-neon)' : 'var(--owl-elevated)',
                color: m.id === currentMemberId ? '#0a2828' : 'var(--owl-text-primary)',
                border: '1.5px solid var(--owl-dash)',
                marginLeft: i === 0 ? 0 : -6,
              }}
            >
              {m.initials}
            </span>
          ))}
        </div>
        <div
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            color: 'var(--owl-text-muted)',
            lineHeight: 1.5,
          }}
        >
          <div>
            ● <span style={{ color: 'var(--owl-neon)' }}>{counts.active}</span> active cards
          </div>
          {counts.high > 0 && (
            <div>
              !! <span style={{ color: 'var(--owl-negative)' }}>{counts.high}</span> high priority
            </div>
          )}
        </div>
      </div>
    </aside>
  );
}

interface NavItemProps {
  children: React.ReactNode;
  active?: boolean;
  onClick?: () => void;
  dotColor?: string;
  count?: number;
}

function NavItem({ children, active, onClick, dotColor, count }: NavItemProps) {
  return (
    <button
      onClick={onClick}
      className="relative flex items-center gap-[10px] px-[8px] py-[7px] rounded-md text-[13px] text-left transition-colors"
      style={{
        color: active ? 'var(--owl-text-primary)' : 'var(--owl-text-muted)',
        background: active ? 'rgba(210,230,50,0.07)' : 'transparent',
      }}
      onMouseEnter={(e) => {
        if (!active) {
          e.currentTarget.style.color = 'var(--owl-text-secondary)';
          e.currentTarget.style.background = 'rgba(30,90,80,0.14)';
        }
      }}
      onMouseLeave={(e) => {
        if (!active) {
          e.currentTarget.style.color = 'var(--owl-text-muted)';
          e.currentTarget.style.background = 'transparent';
        }
      }}
    >
      {active && (
        <span
          className="absolute top-[7px] bottom-[7px] left-[-14px] w-[2px]"
          style={{ background: 'var(--owl-neon)' }}
        />
      )}
      <span
        className="rounded-full"
        style={{
          width: 6,
          height: 6,
          background: dotColor ?? 'currentColor',
          opacity: dotColor ? 1 : 0.65,
        }}
      />
      <span className="flex-1">{children}</span>
      {count !== undefined && count > 0 && (
        <span
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            color: 'var(--owl-text-disabled)',
          }}
        >
          {count}
        </span>
      )}
    </button>
  );
}
