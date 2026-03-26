import { useState, useEffect } from 'react';
import { X, Pencil, Search } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { Button } from '@/components/ui/button';
import { format, parseISO, startOfDay, isSameDay, addDays, isBefore } from 'date-fns';
import { COLUMNS, PRIORITY_COLORS } from '@/lib/constants';
import type { TaskWithDetail, Tag, TeamMember, TaskColumn, TaskPriority, RecurrenceFrequency } from '@/lib/types';

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
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(task.title);
  const [description, setDescription] = useState(task.description || '');
  const [brief, setBrief] = useState(task.brief || '');
  const [column, setColumn] = useState<TaskColumn>(task.column);
  const [priority, setPriority] = useState<TaskPriority>(task.priority);
  const [assigneeId, setAssigneeId] = useState(task.assignee_id || 'none');
  const [dueDate, setDueDate] = useState<Date | undefined>(task.due_date ? new Date(task.due_date) : undefined);
  const [editTagIds, setEditTagIds] = useState<string[]>((task.tags || []).map((t) => t.id));
  const [newTag, setNewTag] = useState('');
  const [tagSearch, setTagSearch] = useState('');
  const [isClosing, setIsClosing] = useState(false);
  const [isRecurring, setIsRecurring] = useState(!!task.recurrence);
  const [recurrence, setRecurrence] = useState<RecurrenceFrequency>((task.recurrence as RecurrenceFrequency) || 'weekly');

  useEffect(() => {
    setTitle(task.title);
    setDescription(task.description || '');
    setBrief(task.brief || '');
    setColumn(task.column);
    setPriority(task.priority);
    setAssigneeId(task.assignee_id || 'none');
    setDueDate(task.due_date ? new Date(task.due_date) : undefined);
    setEditTagIds((task.tags || []).map((t) => t.id));
    setIsRecurring(!!task.recurrence);
    setRecurrence((task.recurrence as RecurrenceFrequency) || 'weekly');
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
    setAssigneeId(task.assignee_id || 'none');
    setDueDate(task.due_date ? new Date(task.due_date) : undefined);
    setEditTagIds((task.tags || []).map((t) => t.id));
    setIsRecurring(!!task.recurrence);
    setRecurrence((task.recurrence as RecurrenceFrequency) || 'weekly');
    setEditing(false);
  };

  const handleSave = () => {
    const updates: { id: string } & Record<string, any> = { id: task.id };
    if (title.trim() !== task.title) updates.title = title.trim();
    if (description !== (task.description || '')) updates.description = description || null;
    if (brief !== (task.brief || '')) updates.brief = brief || null;
    if (column !== task.column) updates.column = column;
    if (priority !== task.priority) updates.priority = priority;
    const newAssignee = assigneeId === 'none' ? null : assigneeId;
    if (newAssignee !== task.assignee_id) updates.assignee_id = newAssignee;
    const newDue = dueDate ? format(dueDate, 'yyyy-MM-dd') : null;
    if (newDue !== task.due_date) updates.due_date = newDue;
    const newRecurrence = isRecurring ? recurrence : null;
    if (newRecurrence !== task.recurrence) updates.recurrence = newRecurrence;
    const origTagIds = (task.tags || []).map((t) => t.id).sort().join(',');
    const newTagIds = [...editTagIds].sort().join(',');
    if (origTagIds !== newTagIds) updates.tag_ids = editTagIds;

    if (Object.keys(updates).length > 1) {
      onUpdate(updates);
    }
    setEditing(false);
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

  // Due date display logic
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

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div
        className={`absolute inset-0 transition-opacity duration-250 ${isClosing ? 'opacity-0' : 'opacity-100'}`}
        style={{ backgroundColor: 'rgba(0,0,0,0.2)' }}
        onClick={handleClose}
      />
      <div
        className={`relative w-full max-w-md bg-card shadow-xl border-l border-border overflow-y-auto transition-transform duration-250 ease-out ${
          isClosing ? 'translate-x-full' : 'animate-slide-in-right'
        }`}
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

            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Assignee</Label>
              {editing ? (
                <Select value={assigneeId} onValueChange={setAssigneeId}>
                  <SelectTrigger className="text-xs h-7"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">Unassigned</SelectItem>
                    {members.map((m) => (
                      <SelectItem key={m.id} value={m.id}>{m.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <p className="text-xs text-foreground">{task.assignee_name || 'Unassigned'}</p>
              )}
            </div>

            <div className="space-y-1">
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
                <Select value={recurrence} onValueChange={(v) => setRecurrence(v as RecurrenceFrequency)}>
                  <SelectTrigger className="text-xs h-7"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="daily">Daily</SelectItem>
                    <SelectItem value="weekly">Weekly</SelectItem>
                    <SelectItem value="biweekly">Bi-weekly</SelectItem>
                    <SelectItem value="monthly">Monthly</SelectItem>
                  </SelectContent>
                </Select>
              )}
            </>
          )}
          {!editing && task.recurrence && (
            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Recurrence</Label>
              <p className="text-xs text-foreground capitalize">{task.recurrence === 'biweekly' ? 'Bi-weekly' : task.recurrence}</p>
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
    </div>
  );
}
