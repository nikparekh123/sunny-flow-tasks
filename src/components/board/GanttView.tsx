import { useMemo, useState } from 'react';
import {
  startOfWeek, endOfWeek, addDays, differenceInDays, format,
  parseISO, max as dateMax, min as dateMin, eachDayOfInterval, isSameDay
} from 'date-fns';
import { COLUMNS, PRIORITY_COLORS } from '@/lib/constants';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import type { TaskWithDetail, TeamMember } from '@/lib/types';

interface Props {
  tasks: TaskWithDetail[];
  members: TeamMember[];
  onTaskClick: (task: TaskWithDetail) => void;
}

export function GanttView({ tasks, members, onTaskClick }: Props) {
  const [groupBy, setGroupBy] = useState<'status' | 'assignee'>('status');

  const scheduledTasks = useMemo(() => tasks.filter((t) => t.due_date), [tasks]);
  const unscheduledTasks = useMemo(() => tasks.filter((t) => !t.due_date), [tasks]);

  const { timelineStart, timelineDays } = useMemo(() => {
    if (scheduledTasks.length === 0) {
      const today = new Date();
      return { timelineStart: startOfWeek(today), timelineDays: 28 };
    }
    const dates = scheduledTasks.map((t) => parseISO(t.due_date!));
    const createdDates = scheduledTasks
      .filter((t) => t.created_at)
      .map((t) => new Date(t.created_at!));
    const allDates = [...dates, ...createdDates, new Date()];
    const minDate = startOfWeek(dateMin(allDates));
    const maxDate = endOfWeek(dateMax(allDates));
    const days = Math.max(differenceInDays(maxDate, minDate) + 7, 14);
    return { timelineStart: minDate, timelineDays: days };
  }, [scheduledTasks]);

  const timelineDates = useMemo(() =>
    eachDayOfInterval({ start: timelineStart, end: addDays(timelineStart, timelineDays - 1) }),
    [timelineStart, timelineDays]
  );

  const grouped = useMemo(() => {
    const groups: { label: string; color: string; tasks: TaskWithDetail[] }[] = [];
    if (groupBy === 'status') {
      COLUMNS.forEach((col) => {
        const colTasks = scheduledTasks.filter((t) => t.column === col.id);
        if (colTasks.length > 0) groups.push({ label: col.label, color: col.color, tasks: colTasks });
      });
    } else {
      const assigned = new Map<string, TaskWithDetail[]>();
      const unassigned: TaskWithDetail[] = [];
      scheduledTasks.forEach((t) => {
        if (t.assignee_id) {
          const list = assigned.get(t.assignee_id) || [];
          list.push(t);
          assigned.set(t.assignee_id, list);
        } else {
          unassigned.push(t);
        }
      });
      assigned.forEach((tks, memberId) => {
        const m = members.find((m) => m.id === memberId);
        groups.push({ label: m?.name || 'Unknown', color: m?.color || '#888', tasks: tks });
      });
      if (unassigned.length > 0) groups.push({ label: 'Unassigned', color: '#888', tasks: unassigned });
    }
    return groups;
  }, [scheduledTasks, groupBy, members]);

  const DAY_WIDTH = 32;
  const today = new Date();

  return (
    <div className="flex-1 p-4 overflow-auto">
      <div className="flex items-center gap-2 mb-4">
        <span className="text-xs text-muted-foreground">Group by:</span>
        <button
          onClick={() => setGroupBy('status')}
          className={`text-[10px] px-2 py-0.5 rounded ${groupBy === 'status' ? 'bg-foreground text-primary-foreground' : 'bg-secondary text-muted-foreground'}`}
        >
          Status
        </button>
        <button
          onClick={() => setGroupBy('assignee')}
          className={`text-[10px] px-2 py-0.5 rounded ${groupBy === 'assignee' ? 'bg-foreground text-primary-foreground' : 'bg-secondary text-muted-foreground'}`}
        >
          Assignee
        </button>
      </div>

      <div className="border border-border rounded-lg overflow-hidden">
        {/* Header */}
        <div className="flex border-b border-border bg-card">
          <div className="w-48 shrink-0 px-3 py-1.5 text-[10px] font-medium text-muted-foreground border-r border-border">
            Task
          </div>
          <div className="flex">
            {timelineDates.map((d) => (
              <div
                key={d.toISOString()}
                className={`text-[8px] text-center border-r border-border ${
                  isSameDay(d, today) ? 'bg-primary/10 font-bold text-primary' : 'text-muted-foreground'
                }`}
                style={{ width: DAY_WIDTH }}
              >
                <div>{format(d, 'dd')}</div>
                <div>{format(d, 'EEE')}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Groups */}
        {grouped.map((group) => (
          <div key={group.label}>
            <div className="flex items-center gap-2 px-3 py-1 bg-accent/50 border-b border-border">
              <span className="w-2 h-2 rounded-full" style={{ backgroundColor: group.color }} />
              <span className="text-[10px] font-medium text-foreground">{group.label}</span>
              <span className="text-[10px] text-muted-foreground">({group.tasks.length})</span>
            </div>
            {group.tasks.map((task) => {
              const startDate = task.created_at ? new Date(task.created_at) : addDays(parseISO(task.due_date!), -3);
              const endDate = parseISO(task.due_date!);
              const startOffset = Math.max(0, differenceInDays(startDate, timelineStart));
              const barWidth = Math.max(1, differenceInDays(endDate, startDate) + 1) * DAY_WIDTH;

              return (
                <div key={task.id} className="flex border-b border-border last:border-0 hover:bg-accent/30">
                  <div className="w-48 shrink-0 px-3 py-1.5 border-r border-border flex items-center gap-1.5">
                    {task.assignee_initials && (
                      <Avatar className="h-4 w-4">
                        <AvatarImage src={task.assignee_avatar_url || ''} />
                        <AvatarFallback style={{ backgroundColor: task.assignee_color || '#888' }} className="text-[6px] text-primary-foreground">
                          {task.assignee_initials}
                        </AvatarFallback>
                      </Avatar>
                    )}
                    <span className="text-[10px] text-foreground truncate">{task.title}</span>
                  </div>
                  <div className="relative flex-1" style={{ minWidth: timelineDays * DAY_WIDTH }}>
                    <button
                      onClick={() => onTaskClick(task)}
                      className="absolute top-1 h-5 rounded text-[8px] text-primary-foreground px-1 truncate hover:opacity-90 transition-opacity"
                      style={{
                        left: startOffset * DAY_WIDTH,
                        width: barWidth,
                        backgroundColor: PRIORITY_COLORS[task.priority],
                      }}
                    >
                      {task.title}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        ))}
      </div>

      {/* Unscheduled */}
      {unscheduledTasks.length > 0 && (
        <div className="mt-4">
          <h3 className="text-xs font-medium text-muted-foreground mb-2">Unscheduled ({unscheduledTasks.length})</h3>
          <div className="space-y-1">
            {unscheduledTasks.map((t) => (
              <button
                key={t.id}
                onClick={() => onTaskClick(t)}
                className="w-full text-left px-3 py-1.5 bg-card border border-border rounded text-[10px] text-foreground hover:bg-accent/50 transition-colors truncate"
              >
                {t.title}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
