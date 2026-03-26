import { useState, useMemo } from 'react';
import {
  startOfMonth, endOfMonth, startOfWeek, endOfWeek, eachDayOfInterval,
  format, isSameMonth, isSameDay, addMonths, subMonths, parseISO
} from 'date-fns';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { PRIORITY_COLORS } from '@/lib/constants';
import type { TaskWithDetail } from '@/lib/types';

interface Props {
  tasks: TaskWithDetail[];
  onTaskClick: (task: TaskWithDetail) => void;
}

export function CalendarView({ tasks, onTaskClick }: Props) {
  const [currentMonth, setCurrentMonth] = useState(new Date());

  const days = useMemo(() => {
    const monthStart = startOfMonth(currentMonth);
    const monthEnd = endOfMonth(currentMonth);
    return eachDayOfInterval({ start: startOfWeek(monthStart), end: endOfWeek(monthEnd) });
  }, [currentMonth]);

  const tasksByDate = useMemo(() => {
    const map: Record<string, TaskWithDetail[]> = {};
    tasks.forEach((t) => {
      if (!t.due_date) return;
      const key = t.due_date;
      if (!map[key]) map[key] = [];
      map[key].push(t);
    });
    return map;
  }, [tasks]);

  return (
    <div className="flex-1 p-4">
      <div className="flex items-center justify-between mb-4">
        <Button variant="ghost" size="sm" onClick={() => setCurrentMonth(subMonths(currentMonth, 1))}>
          <ChevronLeft className="w-4 h-4" />
        </Button>
        <h2 className="text-sm font-medium text-foreground">{format(currentMonth, 'MMMM yyyy')}</h2>
        <Button variant="ghost" size="sm" onClick={() => setCurrentMonth(addMonths(currentMonth, 1))}>
          <ChevronRight className="w-4 h-4" />
        </Button>
      </div>

      <div className="grid grid-cols-7 gap-px bg-border rounded-lg overflow-hidden">
        {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((d) => (
          <div key={d} className="bg-card px-2 py-1.5 text-[10px] font-medium text-muted-foreground text-center">
            {d}
          </div>
        ))}
        {days.map((day) => {
          const key = format(day, 'yyyy-MM-dd');
          const dayTasks = tasksByDate[key] || [];
          const isCurrentMonth = isSameMonth(day, currentMonth);
          const isToday = isSameDay(day, new Date());

          return (
            <div
              key={key}
              className={`bg-card min-h-[80px] p-1 ${!isCurrentMonth ? 'opacity-40' : ''}`}
            >
              <div className={`text-[10px] font-medium mb-0.5 w-5 h-5 flex items-center justify-center rounded-full ${
                isToday ? 'bg-primary text-primary-foreground' : 'text-muted-foreground'
              }`}>
                {format(day, 'd')}
              </div>
              <div className="space-y-0.5">
                {dayTasks.slice(0, 3).map((t) => (
                  <button
                    key={t.id}
                    onClick={() => onTaskClick(t)}
                    className="w-full text-left px-1 py-0.5 rounded text-[9px] truncate hover:opacity-80 transition-opacity"
                    style={{
                      backgroundColor: PRIORITY_COLORS[t.priority] + '20',
                      color: PRIORITY_COLORS[t.priority],
                      borderLeft: `2px solid ${PRIORITY_COLORS[t.priority]}`,
                    }}
                  >
                    {t.title}
                  </button>
                ))}
                {dayTasks.length > 3 && (
                  <span className="text-[9px] text-muted-foreground pl-1">+{dayTasks.length - 3} more</span>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
