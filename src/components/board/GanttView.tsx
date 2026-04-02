import { useMemo, useState, useEffect, useCallback } from 'react';
import {
  startOfWeek, endOfWeek, addDays, differenceInDays, format,
  parseISO, max as dateMax, min as dateMin, eachDayOfInterval, isSameDay, subDays
} from 'date-fns';
import { COLUMNS, PRIORITY_COLORS } from '@/lib/constants';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { Maximize2, Minimize2, ChevronLeft, ChevronRight } from 'lucide-react';
import type { TaskWithDetail, TeamMember } from '@/lib/types';

interface Props {
  tasks: TaskWithDetail[];
  members: TeamMember[];
  onTaskClick: (task: TaskWithDetail) => void;
}

type GanttViewMode = 'auto' | 'week';

export function GanttView({ tasks, members, onTaskClick }: Props) {
  const [groupBy, setGroupBy] = useState<'status' | 'assignee'>('status');
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [viewMode, setViewMode] = useState<GanttViewMode>('auto');
  const [weekStart, setWeekStart] = useState(() => startOfWeek(new Date(), { weekStartsOn: 1 }));

  const scheduledTasks = useMemo(() => tasks.filter((t) => t.due_date), [tasks]);
  const unscheduledTasks = useMemo(() => tasks.filter((t) => !t.due_date), [tasks]);

  // Escape key listener for fullscreen
  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.key === 'Escape' && isFullscreen) setIsFullscreen(false);
  }, [isFullscreen]);

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  const { timelineStart, timelineDays } = useMemo(() => {
    if (viewMode === 'week') {
      return { timelineStart: weekStart, timelineDays: 7 };
    }
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
  }, [scheduledTasks, viewMode, weekStart]);

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
        if (t.assignee_ids?.length > 0) {
          t.assignee_ids.forEach((aId) => {
            const list = assigned.get(aId) || [];
            list.push(t);
            assigned.set(aId, list);
          });
        } else if (t.assignee_id) {
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

  const DAY_WIDTH = viewMode === 'week' ? 80 : 32;
  const today = new Date();

  const content = (
    <div className={`flex-1 p-4 overflow-auto ${isFullscreen ? 'fixed inset-0 z-50 bg-background' : ''}`}>
      {/* Toolbar */}
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        <span className="text-xs text-muted-foreground">Group by:</span>
        <button
          onClick={() => setGroupBy('status')}
          className={`text-xs px-2.5 py-1 rounded ${groupBy === 'status' ? 'bg-foreground text-primary-foreground' : 'bg-secondary text-muted-foreground'}`}
        >
          Status
        </button>
        <button
          onClick={() => setGroupBy('assignee')}
          className={`text-xs px-2.5 py-1 rounded ${groupBy === 'assignee' ? 'bg-foreground text-primary-foreground' : 'bg-secondary text-muted-foreground'}`}
        >
          Assignee
        </button>

        <div className="w-px h-4 bg-border mx-1" />

        <span className="text-xs text-muted-foreground">View:</span>
        <button
          onClick={() => setViewMode('auto')}
          className={`text-xs px-2.5 py-1 rounded ${viewMode === 'auto' ? 'bg-foreground text-primary-foreground' : 'bg-secondary text-muted-foreground'}`}
        >
          Overview
        </button>
        <button
          onClick={() => { setViewMode('week'); setWeekStart(startOfWeek(new Date(), { weekStartsOn: 1 })); }}
          className={`text-xs px-2.5 py-1 rounded ${viewMode === 'week' ? 'bg-foreground text-primary-foreground' : 'bg-secondary text-muted-foreground'}`}
        >
          Week
        </button>

        {viewMode === 'week' && (
          <>
            <div className="w-px h-4 bg-border mx-1" />
            <Button variant="ghost" size="sm" className="h-6 w-6 p-0" onClick={() => setWeekStart(subDays(weekStart, 7))}>
              <ChevronLeft className="w-3.5 h-3.5" />
            </Button>
            <Button
              variant="outline"
              size="sm"
              className="h-6 text-[10px] px-2"
              onClick={() => setWeekStart(startOfWeek(new Date(), { weekStartsOn: 1 }))}
            >
              Today
            </Button>
            <Button variant="ghost" size="sm" className="h-6 w-6 p-0" onClick={() => setWeekStart(addDays(weekStart, 7))}>
              <ChevronRight className="w-3.5 h-3.5" />
            </Button>
            <span className="text-xs text-muted-foreground">
              {format(weekStart, 'MMM d')} – {format(addDays(weekStart, 6), 'MMM d, yyyy')}
            </span>
          </>
        )}

        <div className="ml-auto">
          <Button
            variant="ghost"
            size="sm"
            className="h-7 w-7 p-0"
            onClick={() => setIsFullscreen(!isFullscreen)}
          >
            {isFullscreen ? <Minimize2 className="w-3.5 h-3.5" /> : <Maximize2 className="w-3.5 h-3.5" />}
          </Button>
        </div>
      </div>

      <div className="border border-border rounded-lg overflow-hidden">
        {/* Header */}
        <div className="flex border-b border-border bg-card">
          <div className="w-52 shrink-0 px-3 py-1.5 text-xs font-medium text-muted-foreground border-r border-border">
            Task
          </div>
          <div className="flex">
            {timelineDates.map((d) => (
              <div
                key={d.toISOString()}
                className={`text-center border-r border-border ${
                  isSameDay(d, today) ? 'bg-primary/10 font-bold text-primary' : 'text-muted-foreground'
                }`}
                style={{ width: DAY_WIDTH, fontSize: viewMode === 'week' ? '11px' : '10px' }}
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
              <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: group.color }} />
              <span className="text-xs font-medium text-foreground">{group.label}</span>
              <span className="text-xs text-muted-foreground">({group.tasks.length})</span>
            </div>
            {group.tasks.map((task) => {
              const startDate = task.created_at ? new Date(task.created_at) : addDays(parseISO(task.due_date!), -3);
              const endDate = parseISO(task.due_date!);
              const startOffset = Math.max(0, differenceInDays(startDate, timelineStart));
              const barWidth = Math.max(1, differenceInDays(endDate, startDate) + 1) * DAY_WIDTH;

              const assignees = task.assignees || [];

              return (
                <div key={task.id} className="flex border-b border-border last:border-0 hover:bg-accent/30">
                  <div className="w-52 shrink-0 px-3 py-1.5 border-r border-border flex items-center gap-1.5">
                    {assignees.length > 0 ? (
                      <div className="flex -space-x-1">
                        {assignees.slice(0, 2).map((a) => (
                          <Avatar key={a.id} className="h-4 w-4 border border-card">
                            <AvatarImage src={a.avatar_url || ''} />
                            <AvatarFallback style={{ backgroundColor: a.color || '#888' }} className="text-[6px] text-primary-foreground">
                              {a.initials}
                            </AvatarFallback>
                          </Avatar>
                        ))}
                      </div>
                    ) : task.assignee_initials ? (
                      <Avatar className="h-4 w-4">
                        <AvatarImage src={task.assignee_avatar_url || ''} />
                        <AvatarFallback style={{ backgroundColor: task.assignee_color || '#888' }} className="text-[6px] text-primary-foreground">
                          {task.assignee_initials}
                        </AvatarFallback>
                      </Avatar>
                    ) : null}
                    <span className="text-xs text-foreground truncate">{task.title}</span>
                  </div>
                  <div className="relative flex-1" style={{ minWidth: timelineDays * DAY_WIDTH }}>
                    {/* Today highlight column */}
                    {viewMode === 'week' && timelineDates.map((d, i) => (
                      isSameDay(d, today) && (
                        <div
                          key="today-highlight"
                          className="absolute top-0 bottom-0 bg-primary/5"
                          style={{ left: i * DAY_WIDTH, width: DAY_WIDTH }}
                        />
                      )
                    ))}
                    <button
                      onClick={() => onTaskClick(task)}
                      className="absolute top-1 h-5 rounded text-[10px] text-primary-foreground px-1.5 truncate hover:opacity-90 transition-opacity"
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
                className="w-full text-left px-3 py-1.5 bg-card border border-border rounded text-xs text-foreground hover:bg-accent/50 transition-colors truncate"
              >
                {t.title}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );

  return content;
}
