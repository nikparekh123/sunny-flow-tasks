import { useState, useEffect, useCallback } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useTasks } from '@/hooks/useTasks';
import { supabase } from '@/integrations/supabase/client';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { PROJECTS } from '@/lib/constants';
import type { TaskWithDetail } from '@/lib/types';

const COLUMN_LABELS: Record<string, string> = {
  todo: 'To Do',
  inprogress: 'In Progress',
  review: 'Review',
  done: 'Done',
};

const PRIORITY_COLORS: Record<string, string> = {
  high: 'bg-destructive/10 text-destructive border-destructive/20',
  med: 'bg-orange-50 text-orange-700 border-orange-200',
  low: 'bg-green-50 text-green-700 border-green-200',
};

export default function Dashboard() {
  const { user, member } = useAuth();
  const { tasks } = useTasks();
  const [notes, setNotes] = useState('');
  const [noteId, setNoteId] = useState<string | null>(null);
  const [saveTimeout, setSaveTimeout] = useState<ReturnType<typeof setTimeout> | null>(null);

  // Fetch user notes
  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data } = await supabase
        .from('user_notes')
        .select('*')
        .eq('user_id', user.id)
        .limit(1)
        .maybeSingle();
      if (data) {
        setNotes(data.content);
        setNoteId(data.id);
      }
    })();
  }, [user]);

  const saveNotes = useCallback(
    (content: string) => {
      if (!user) return;
      if (saveTimeout) clearTimeout(saveTimeout);
      const timeout = setTimeout(async () => {
        if (noteId) {
          await supabase.from('user_notes').update({ content, updated_at: new Date().toISOString() }).eq('id', noteId);
        } else {
          const { data } = await supabase
            .from('user_notes')
            .insert({ user_id: user.id, content })
            .select('id')
            .single();
          if (data) setNoteId(data.id);
        }
      }, 800);
      setSaveTimeout(timeout);
    },
    [user, noteId, saveTimeout]
  );

  const handleNotesChange = (value: string) => {
    setNotes(value);
    saveNotes(value);
  };

  // Filter tasks assigned to current member
  const myTasks = member
    ? tasks.filter((t) => t.assignee_id === member.id)
    : [];

  const grouped: Record<string, TaskWithDetail[]> = {
    todo: [],
    inprogress: [],
    review: [],
    done: [],
  };
  myTasks.forEach((t) => {
    if (grouped[t.column]) grouped[t.column].push(t);
  });

  const projectLabel = (project: string | null) =>
    PROJECTS.find((p) => p.id === project)?.label || '—';

  return (
    <div className="flex-1 overflow-auto p-6 space-y-6 bg-background">
      <div>
        <h1 className="text-xl font-bold text-foreground">
          Welcome back, {member?.name || 'User'}
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Here's an overview of your tasks
        </p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {(['todo', 'inprogress', 'review', 'done'] as const).map((col) => (
          <Card key={col}>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs font-medium text-muted-foreground uppercase">
                {COLUMN_LABELS[col]}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-2xl font-bold text-foreground">{grouped[col].length}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Task list */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm">My Tasks</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {myTasks.length === 0 && (
            <p className="text-sm text-muted-foreground">No tasks assigned to you yet.</p>
          )}
          {myTasks
            .filter((t) => t.column !== 'done')
            .sort((a, b) => {
              const order = { todo: 0, inprogress: 1, review: 2, done: 3 };
              return (order[a.column] ?? 0) - (order[b.column] ?? 0);
            })
            .map((task) => (
              <div
                key={task.id}
                className="flex items-center gap-3 p-2.5 rounded-md border border-border bg-card hover:bg-accent/30 transition-colors"
              >
                <Badge variant="outline" className="text-[10px] shrink-0">
                  {COLUMN_LABELS[task.column]}
                </Badge>
                <span className="text-sm flex-1 truncate">{task.title}</span>
                <Badge
                  variant="outline"
                  className={`text-[10px] ${PRIORITY_COLORS[task.priority] || ''}`}
                >
                  {task.priority}
                </Badge>
                <span className="text-[10px] text-muted-foreground shrink-0">
                  {projectLabel(task.project)}
                </span>
              </div>
            ))}
        </CardContent>
      </Card>

      {/* Private Notes */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Private Notes</CardTitle>
        </CardHeader>
        <CardContent>
          <Textarea
            placeholder="Write your private notes here... Auto-saves as you type."
            value={notes}
            onChange={(e) => handleNotesChange(e.target.value)}
            className="min-h-[150px] resize-y"
          />
          <p className="text-[10px] text-muted-foreground mt-1">Auto-saved • Only visible to you</p>
        </CardContent>
      </Card>
    </div>
  );
}
