import { useState, useEffect } from 'react';
import { X, Pencil, Search, Trash2, Plus } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Checkbox } from '@/components/ui/checkbox';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { Button } from '@/components/ui/button';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Progress } from '@/components/ui/progress';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { format, parseISO, startOfDay, isSameDay, addDays, isBefore } from 'date-fns';
import { COLUMNS, PRIORITY_COLORS } from '@/lib/constants';
import { useSubtasks } from '@/hooks/useSubtasks';
import type { TaskWithDetail, Tag, TeamMember, TaskColumn, TaskPriority, RecurrenceFrequency, Subtask } from '@/lib/types';

const DAYS_OF_WEEK = [
  { id: 'mon', label: 'Mon' },
  { id: 'tue', label: 'Tue' },
  { id: 'wed', label: 'Wed' },
  { id: 'thu', label: 'Thu' },
  { id: 'fri', label: 'Fri' },
  { id: 'sat', label: 'Sat' },
  { id: 'sun', label: 'Sun' },
];

function parseRecurrence(rec: string | null): { frequency: RecurrenceFrequency; customDays: string[]; customDayOfMonth: string } {
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
  return { frequency: rec as RecurrenceFrequency, customDays: [], customDayOfMonth: '' };
}

interface Props {
  task: TaskWithDetail;
  tags: Tag[];
  members: TeamMember[];
  onClose: () => void;
  onUpdate: (data: { id: string } & Record<string, any>) => void;
  onDelete: (id: string) => void;
  onCreateTag: (name: string) => void;
}

export function TaskDetailPanel({ task, tags, members, onClose, onUpdate, onDelete, onCreateTag }: Props) {
  const { createSubtask, toggleSubtask, deleteSubtask, completeAllSubtasks } = useSubtasks();
  const [newSubtaskTitle, setNewSubtaskTitle] = useState('');
  const [showSubtaskConfirm, setShowSubtaskConfirm] = useState(false);
  const [pendingColumnChange, setPendingColumnChange] = useState<TaskColumn | null>(null);
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(task.title);
  const [description, setDescription] = useState(task.description || '');
  const [brief, setBrief] = useState(task.brief || '');
  const [column, setColumn] = useState<TaskColumn>(task.column);
  const [priority, setPriority] = useState<TaskPriority>(task.priority);
  const [assigneeIds, setAssigneeIds] = useState<string[]>(task.assignee_ids || []);
  const [dueDate, setDueDate] = useState<Date | undefined>(task.due_date ? new Date(task.due_date) : undefined);
  const [editTagIds, setEditTagIds] = useState<string[]>((task.tags || []).map((t) => t.id));
  const [newTag, setNewTag] = useState('');
  const [tagSearch, setTagSearch] = useState('');
  const [isClosing, setIsClosing] = useState(false);
  const [isRecurring, setIsRecurring] = useState(!!task.recurrence);

  const parsed = parseRecurrence(task.recurrence);
  const [recurrence, setRecurrence] = useState<RecurrenceFrequency>(parsed.frequency);
  const [customDays, setCustomDays] = useState<string[]>(parsed.customDays);
  const [customDayOfMonth, setCustomDayOfMonth] = useState(parsed.customDayOfMonth);

  useEffect(() => {
    setTitle(task.title);
    setDescription(task.description || '');
    setBrief(task.brief || '');
    setColumn(task.column);
    setPriority(task.priority);
    setAssigneeIds(task.assignee_ids || []);
    setDueDate(task.due_date ? new Date(task.due_date) : undefined);
    setEditTagIds((task.tags || []).map((t) => t.id));
    setIsRecurring(!!task.recurrence);
    const p = parseRecurrence(task.recurrence);
    setRecurrence(p.frequency);
    setCustomDays(p.customDays);
    setCustomDayOfMonth(p.customDayOfMonth);
    setEditing(false);
  }, [task]);

  const handleClose = () => {
    setIsClosing(true);
    setTimeout(onClose, 250);
  };

  const handleCancel = () => {
    setTitle(task.title);
    setDescription(task.description || '');
    setBrief(task.brief || '');
    setColumn(task.column);
    setPriority(task.priority);
    setAssigneeIds(task.assignee_ids || []);
    setDueDate(task.due_date ? new Date(task.due_date) : undefined);
    setEditTagIds((task.tags || []).map((t) => t.id));
    setIsRecurring(!!task.recurrence);
    const p = parseRecurrence(task.recurrence);
    setRecurrence(p.frequency);
    setCustomDays(p.customDays);
    setCustomDayOfMonth(p.customDayOfMonth);
    setEditing(false);
  };

  const getRecurrenceValue = () => {
    if (!isRecurring) return null;
    if (recurrence === 'custom') {
      const config: Record<string, any> = {};
      if (customDays.length > 0) config.days = customDays;
      if (customDayOfMonth) config.dayOfMonth = parseInt(customDayOfMonth);
      return `custom:${JSON.stringify(config)}`;
    }
    return recurrence;
  };

  const handleSave = () => {
    const updates: { id: string } & Record<string, any> = { id: task.id };
    if (title.trim() !== task.title) updates.title = title.trim();
    if (description !== (task.description || '')) updates.description = description || null;
    if (brief !== (task.brief || '')) updates.brief = brief || null;
    if (column !== task.column) updates.column = column;
    if (priority !== task.priority) updates.priority = priority;

    const origAssignees = (task.assignee_ids || []).sort().join(',');
    const newAssignees = [...assigneeIds].sort().join(',');
    if (origAssignees !== newAssignees) updates.assignee_ids = assigneeIds;

    const newDue = dueDate ? format(dueDate, 'yyyy-MM-dd') : null;
    if (newDue !== task.due_date) updates.due_date = newDue;
    const newRecurrence = getRecurrenceValue();
    if (newRecurrence !== task.recurrence) updates.recurrence = newRecurrence;
    const origTagIds = (task.tags || []).map((t) => t.id).sort().join(',');
    const newTagIds = [...editTagIds].sort().join(',');
    if (origTagIds !== newTagIds) updates.tag_ids = editTagIds;

    // Check if moving to done with incomplete subtasks
    const subtasks = task.subtasks || [];
    const incompleteCount = subtasks.filter(s => !s.done).length;
    if (column === 'done' && task.column !== 'done' && incompleteCount > 0) {
      setPendingColumnChange(column);
      setShowSubtaskConfirm(true);
      return;
    }

    if (Object.keys(updates).length > 1) {
      onUpdate(updates);
    }
    setEditing(false);
  };

  const executeSaveWithSubtaskChoice = (completeSubtasks: boolean) => {
    const updates: { id: string } & Record<string, any> = { id: task.id };
    if (title.trim() !== task.title) updates.title = title.trim();
    if (description !== (task.description || '')) updates.description = description || null;
    if (brief !== (task.brief || '')) updates.brief = brief || null;
    if (pendingColumnChange) updates.column = pendingColumnChange;
    if (priority !== task.priority) updates.priority = priority;
    const origAssignees = (task.assignee_ids || []).sort().join(',');
    const newAssignees = [...assigneeIds].sort().join(',');
    if (origAssignees !== newAssignees) updates.assignee_ids = assigneeIds;
    const newDue = dueDate ? format(dueDate, 'yyyy-MM-dd') : null;
    if (newDue !== task.due_date) updates.due_date = newDue;
    const newRecurrence = getRecurrenceValue();
    if (newRecurrence !== task.recurrence) updates.recurrence = newRecurrence;
    const origTagIds = (task.tags || []).map((t) => t.id).sort().join(',');
    const newTagIds = [...editTagIds].sort().join(',');
    if (origTagIds !== newTagIds) updates.tag_ids = editTagIds;

    if (completeSubtasks) {
      completeAllSubtasks.mutate(task.id);
    }

    if (Object.keys(updates).length > 1) {
      onUpdate(updates);
    }
    setEditing(false);
    setPendingColumnChange(null);
    setShowSubtaskConfirm(false);
  };

  const toggleAssignee = (id: string) => {
    setAssigneeIds((prev) =>
      prev.includes(id) ? prev.filter((a) => a !== id) : [...prev, id]
    );
  };

  const currentTagIds = editing ? editTagIds : (task.tags || []).map((t) => t.id);
  const filteredTags = tags.filter((t) =>
    !tagSearch || t.name.toLowerCase().includes(tagSearch.toLowerCase())
  );

  const toggleTag = (tagId: string) => {
    if (editing) {
      setEditTagIds((prev) =>
        prev.includes(tagId) ? prev.filter((id) => id !== tagId) : [...prev, tagId]
      );
    } else {
      const newIds = currentTagIds.includes(tagId)
        ? currentTagIds.filter((id) => id !== tagId)
        : [...currentTagIds, tagId];
      onUpdate({ id: task.id, tag_ids: newIds });
    }
  };

  const today = startOfDay(new Date());
  const dueDay = task.due_date ? startOfDay(parseISO(task.due_date)) : null;
  const isToday = dueDay ? isSameDay(dueDay, today) : false;
  const isTomorrow = dueDay ? isSameDay(dueDay, addDays(today, 1)) : false;
  const isOverdue = dueDay ? isBefore(dueDay, today) && task.column !== 'done' : false;

  const dueDateDisplayText = () => {
    if (!task.due_date) return 'No due date';
    if (task.column === 'done') return format(new Date(task.due_date), 'MMM d, yyyy');
    if (isToday) return 'Today';
    if (isTomorrow) return 'Tomorrow';
    if (isOverdue) return `${format(new Date(task.due_date), 'MMM d, yyyy')} — overdue`;
    return format(new Date(task.due_date), 'MMM d, yyyy');
  };

  const recurrenceDisplayText = () => {
    if (!task.recurrence) return null;
    if (task.recurrence.startsWith('custom:')) {
      try {
        const config = JSON.parse(task.recurrence.slice(7));
        const parts: string[] = [];
        if (config.days?.length) parts.push(`on ${config.days.join(', ')}`);
        if (config.dayOfMonth) parts.push(`day ${config.dayOfMonth} of month`);
        return `Custom: ${parts.join(', ')}`;
      } catch {
        return 'Custom';
      }
    }
    return task.recurrence === 'biweekly' ? 'Bi-weekly' : task.recurrence;
  };

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div
        className={`absolute inset-0 transition-opacity duration-250 ${isClosing ? 'opacity-0' : 'opacity-100'}`}
        style={{ backgroundColor: 'rgba(0,0,0,0.4)' }}
        onClick={handleClose}
      />
      <div
        className={`relative w-full max-w-md shadow-xl overflow-y-auto transition-transform duration-250 ease-out ${
          isClosing ? 'translate-x-full' : 'animate-slide-in-right'
        }`}
        style={{ backgroundColor: 'var(--owl-surface)', borderLeft: '1px solid var(--owl-border)' }}
      >
        <div className="flex items-center justify-between p-4 border-b border-border">
          <h2 className="text-sm font-medium text-muted-foreground">Task details</h2>
          <div className="flex items-center gap-2">
            {!editing && (
              <Button variant="outline" size="sm" className="h-7 text-xs gap-1" onClick={() => setEditing(true)}>
                <Pencil className="w-3 h-3" /> Edit Task
              </Button>
            )}
            <button onClick={handleClose} className="text-muted-foreground hover:text-foreground transition-colors">
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>
        <div className="p-4 space-y-4">
          {editing ? (
            <Input value={title} onChange={(e) => setTitle(e.target.value)} className="text-sm font-medium" />
          ) : (
            <p className="text-sm font-medium">{task.title}</p>
          )}

          {/* Brief */}
          <div className="space-y-1">
            <Label className="text-[10px] text-muted-foreground">Brief</Label>
            {editing ? (
              <>
                <Input
                  value={brief}
                  onChange={(e) => setBrief(e.target.value.slice(0, 150))}
                  className="text-xs"
                  placeholder="Short summary (max 150 chars)"
                  maxLength={150}
                />
                <span className="text-[9px] text-muted-foreground">{brief.length}/150</span>
              </>
            ) : (
              <p className="text-xs text-muted-foreground">{task.brief || 'No brief'}</p>
            )}
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Status</Label>
              {editing ? (
                <Select value={column} onValueChange={(v) => setColumn(v as TaskColumn)}>
                  <SelectTrigger className="text-xs h-7"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {COLUMNS.map((col) => (
                      <SelectItem key={col.id} value={col.id}>
                        <span className="flex items-center gap-1.5">
                          <span className="w-2 h-2 rounded-full" style={{ backgroundColor: col.color }} />
                          {col.label}
                        </span>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <p className="text-xs text-foreground">{COLUMNS.find((c) => c.id === task.column)?.label}</p>
              )}
            </div>

            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Priority</Label>
              {editing ? (
                <Select value={priority} onValueChange={(v) => setPriority(v as TaskPriority)}>
                  <SelectTrigger className="text-xs h-7"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {(['high', 'med', 'low'] as TaskPriority[]).map((p) => (
                      <SelectItem key={p} value={p}>
                        <span className="flex items-center gap-1.5">
                          <span className="w-2 h-2 rounded-full" style={{ backgroundColor: PRIORITY_COLORS[p] }} />
                          {p.charAt(0).toUpperCase() + p.slice(1)}
                        </span>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <p className="text-xs text-foreground capitalize">{task.priority}</p>
              )}
            </div>

            <div className="col-span-2 space-y-1">
              <Label className="text-[10px] text-muted-foreground">Assignees</Label>
              {editing ? (
                <div className="flex flex-wrap gap-1">
                  {members.map((m) => (
                    <button
                      key={m.id}
                      onClick={() => toggleAssignee(m.id)}
                      className={`text-[10px] px-2 py-1 rounded transition-all duration-150 ${
                        assigneeIds.includes(m.id)
                          ? 'bg-foreground text-primary-foreground scale-105'
                          : 'bg-secondary text-muted-foreground hover:bg-accent'
                      }`}
                    >
                      {m.name}
                    </button>
                  ))}
                </div>
              ) : (
                <div className="flex items-center gap-1.5 flex-wrap">
                  {(task.assignees || []).length > 0 ? (
                    task.assignees.map((a) => (
                      <div key={a.id} className="flex items-center gap-1">
                        <Avatar className="h-4 w-4">
                          <AvatarImage src={a.avatar_url || ''} />
                          <AvatarFallback style={{ backgroundColor: a.color || '#378ADD', fontSize: '7px', color: '#fff' }}>
                            {a.initials}
                          </AvatarFallback>
                        </Avatar>
                        <span className="text-xs text-foreground">{a.name}</span>
                      </div>
                    ))
                  ) : (
                    <p className="text-xs text-foreground">Unassigned</p>
                  )}
                </div>
              )}
            </div>

            <div className="col-span-2 space-y-1">
              <Label className="text-[10px] text-muted-foreground">Due date</Label>
              {editing ? (
                <Popover>
                  <PopoverTrigger asChild>
                    <Button variant="outline" className="w-full justify-start text-xs h-7 font-normal">
                      {dueDate ? format(dueDate, 'MMM d, yyyy') : 'No due date'}
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0" align="start">
                    <Calendar mode="single" selected={dueDate} onSelect={setDueDate} />
                  </PopoverContent>
                </Popover>
              ) : (
                <p className={`text-xs ${isOverdue ? 'text-destructive font-medium' : isToday ? 'text-[#639922] font-medium' : 'text-foreground'}`}>
                  {dueDateDisplayText()}
                </p>
              )}
            </div>
          </div>

          {/* Recurring */}
          {editing && (
            <>
              <div className="flex items-center justify-between">
                <Label className="text-[10px] text-muted-foreground">Recurring task</Label>
                <Switch checked={isRecurring} onCheckedChange={setIsRecurring} />
              </div>
              {isRecurring && (
                <div className="space-y-2">
                  <Select value={recurrence} onValueChange={(v) => setRecurrence(v as RecurrenceFrequency)}>
                    <SelectTrigger className="text-xs h-7"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="daily">Daily</SelectItem>
                      <SelectItem value="weekly">Weekly</SelectItem>
                      <SelectItem value="biweekly">Bi-weekly</SelectItem>
                      <SelectItem value="monthly">Monthly</SelectItem>
                      <SelectItem value="custom">Custom</SelectItem>
                    </SelectContent>
                  </Select>
                  {recurrence === 'custom' && (
                    <div className="space-y-2 p-2 border border-border rounded bg-secondary/50">
                      <Label className="text-[10px] text-muted-foreground">Repeat on days</Label>
                      <div className="flex flex-wrap gap-2">
                        {DAYS_OF_WEEK.map((day) => (
                          <label key={day.id} className="flex items-center gap-1 text-[10px]">
                            <Checkbox
                              checked={customDays.includes(day.id)}
                              onCheckedChange={(checked) => {
                                setCustomDays((prev) =>
                                  checked ? [...prev, day.id] : prev.filter((d) => d !== day.id)
                                );
                              }}
                              className="h-3 w-3"
                            />
                            {day.label}
                          </label>
                        ))}
                      </div>
                      <Label className="text-[10px] text-muted-foreground">Or day of month</Label>
                      <Input
                        type="number"
                        min={1}
                        max={31}
                        value={customDayOfMonth}
                        onChange={(e) => setCustomDayOfMonth(e.target.value)}
                        className="text-xs h-7 w-20"
                        placeholder="1-31"
                      />
                    </div>
                  )}
                </div>
              )}
            </>
          )}
          {!editing && task.recurrence && (
            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Recurrence</Label>
              <p className="text-xs text-foreground capitalize">{recurrenceDisplayText()}</p>
            </div>
          )}

          {/* Tags */}
          <div className="space-y-2">
            <Label className="text-[10px] text-muted-foreground">Tags</Label>
            {editing && (
              <div className="flex items-center gap-1.5">
                <Search className="w-3 h-3 text-muted-foreground" />
                <Input
                  value={tagSearch}
                  onChange={(e) => setTagSearch(e.target.value)}
                  placeholder="Search tags…"
                  className="text-xs h-6 flex-1"
                />
              </div>
            )}
            <div className="flex flex-wrap gap-1.5">
              {filteredTags.map((tag) => (
                <button
                  key={tag.id}
                  onClick={() => toggleTag(tag.id)}
                  disabled={!editing}
                  className={`text-[10px] px-2 py-0.5 rounded border transition-all duration-150 ${
                    currentTagIds.includes(tag.id)
                      ? 'bg-foreground text-primary-foreground border-foreground scale-105'
                      : 'bg-secondary text-muted-foreground border-border hover:border-foreground/30'
                  } ${!editing ? 'cursor-default' : 'cursor-pointer'}`}
                >
                  #{tag.name}
                </button>
              ))}
            </div>
            {editing && (
              <div className="flex gap-1.5">
                <Input
                  value={newTag}
                  onChange={(e) => setNewTag(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && newTag.trim()) {
                      onCreateTag(newTag.trim().toLowerCase());
                      setNewTag('');
                    }
                  }}
                  placeholder="Add new tag..."
                  className="text-xs h-7 flex-1"
                />
              </div>
            )}
          </div>

          <div className="space-y-1">
            <Label className="text-[10px] text-muted-foreground">Description</Label>
            {editing ? (
              <Textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Add a description..."
                className="text-xs min-h-[100px]"
              />
            ) : (
              <p className="text-xs text-foreground whitespace-pre-wrap">
                {task.description || 'No description'}
              </p>
            )}
          </div>

          {/* Subtasks */}
          <div className="space-y-2">
            <Label className="text-[10px] text-muted-foreground">
              Subtasks {(task.subtasks || []).length > 0 && (
                <span className="ml-1">({(task.subtasks || []).filter(s => s.done).length}/{(task.subtasks || []).length})</span>
              )}
            </Label>
            {(task.subtasks || []).length > 0 && (
              <Progress
                value={(task.subtasks || []).length > 0 ? ((task.subtasks || []).filter(s => s.done).length / (task.subtasks || []).length) * 100 : 0}
                className="h-1.5"
              />
            )}
            <div className="space-y-1">
              {(task.subtasks || []).map((subtask) => {
                const assignee = subtask.assignee_id ? members.find(m => m.id === subtask.assignee_id) : null;
                return (
                  <div key={subtask.id} className="group/subtask flex items-center gap-2 py-1 px-1 rounded hover:bg-secondary/50">
                    <Checkbox
                      checked={subtask.done}
                      onCheckedChange={(checked) => toggleSubtask.mutate({ id: subtask.id, done: !!checked })}
                      className="h-3.5 w-3.5"
                    />
                    <span className={`text-xs flex-1 ${subtask.done ? 'line-through text-muted-foreground' : 'text-foreground'}`}>
                      {subtask.title}
                    </span>
                    {assignee && (
                      <Avatar className="h-4 w-4">
                        <AvatarImage src={assignee.avatar_url || ''} />
                        <AvatarFallback style={{ backgroundColor: assignee.color || '#378ADD', fontSize: '7px', color: '#fff' }}>
                          {assignee.initials}
                        </AvatarFallback>
                      </Avatar>
                    )}
                    <button
                      className="opacity-0 group-hover/subtask:opacity-100 transition-opacity text-muted-foreground hover:text-destructive"
                      onClick={() => deleteSubtask.mutate(subtask.id)}
                    >
                      <Trash2 className="w-3 h-3" />
                    </button>
                  </div>
                );
              })}
            </div>
            <div className="flex items-center gap-1.5">
              <Plus className="w-3 h-3 text-muted-foreground" />
              <Input
                value={newSubtaskTitle}
                onChange={(e) => setNewSubtaskTitle(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && newSubtaskTitle.trim()) {
                    createSubtask.mutate({ task_id: task.id, title: newSubtaskTitle.trim() });
                    setNewSubtaskTitle('');
                  }
                }}
                placeholder="Add subtask…"
                className="text-xs h-7 flex-1"
              />
            </div>
          </div>

          {editing && (
            <div className="flex gap-2 pt-2">
              <Button size="sm" className="flex-1 text-xs" onClick={handleSave}>Save Changes</Button>
              <Button size="sm" variant="outline" className="flex-1 text-xs" onClick={handleCancel}>Cancel</Button>
            </div>
          )}

          <div className="pt-2 border-t border-border">
            <Button
              variant="ghost"
              size="sm"
              className="text-xs text-destructive hover:text-destructive"
              onClick={() => { onDelete(task.id); handleClose(); }}
            >
              Delete Task
            </Button>
          </div>
        </div>
      </div>

      {/* Subtask completion confirmation */}
      <AlertDialog open={showSubtaskConfirm} onOpenChange={setShowSubtaskConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Incomplete subtasks</AlertDialogTitle>
            <AlertDialogDescription>
              This task has {(task.subtasks || []).filter(s => !s.done).length} incomplete subtask(s). Mark them all as complete too?
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => executeSaveWithSubtaskChoice(false)}>No</AlertDialogCancel>
            <AlertDialogAction onClick={() => executeSaveWithSubtaskChoice(true)}>Yes</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
