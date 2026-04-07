import { useState } from 'react';
import { X, Search } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { Switch } from '@/components/ui/switch';
import { Checkbox } from '@/components/ui/checkbox';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { format } from 'date-fns';
import { toast } from 'sonner';
import type { Tag, TeamMember, TaskPriority, RecurrenceFrequency } from '@/lib/types';

const DAYS_OF_WEEK = [
  { id: 'mon', label: 'Mon' },
  { id: 'tue', label: 'Tue' },
  { id: 'wed', label: 'Wed' },
  { id: 'thu', label: 'Thu' },
  { id: 'fri', label: 'Fri' },
  { id: 'sat', label: 'Sat' },
  { id: 'sun', label: 'Sun' },
];

interface Props {
  tags: Tag[];
  members: TeamMember[];
  currentMemberId: string | null;
  onClose: () => void;
  onSave: (data: any) => Promise<void>;
  onCreateTag: (name: string) => void;
}

export function NewTaskPanel({ tags, members, currentMemberId, onClose, onSave, onCreateTag }: Props) {
  const [title, setTitle] = useState('');
  const [priority, setPriority] = useState<TaskPriority>('med');
  const [assigneeIds, setAssigneeIds] = useState<string[]>(currentMemberId ? [currentMemberId] : []);
  const [dueDate, setDueDate] = useState<Date | undefined>();
  const [description, setDescription] = useState('');
  const [brief, setBrief] = useState('');
  const [selectedTagIds, setSelectedTagIds] = useState<string[]>([]);
  const [newTag, setNewTag] = useState('');
  const [tagSearch, setTagSearch] = useState('');
  const [isClosing, setIsClosing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [isRecurring, setIsRecurring] = useState(false);
  const [recurrence, setRecurrence] = useState<RecurrenceFrequency>('weekly');
  const [customDays, setCustomDays] = useState<string[]>([]);
  const [customDayOfMonth, setCustomDayOfMonth] = useState('');

  const toggleAssignee = (id: string) => {
    setAssigneeIds((prev) =>
      prev.includes(id) ? prev.filter((a) => a !== id) : [...prev, id]
    );
  };

  const toggleTag = (id: string) => {
    setSelectedTagIds((prev) =>
      prev.includes(id) ? prev.filter((t) => t !== id) : [...prev, id]
    );
  };

  const handleClose = () => {
    setIsClosing(true);
    setTimeout(onClose, 250);
  };

  const filteredTags = tags.filter((t) =>
    !tagSearch || t.name.toLowerCase().includes(tagSearch.toLowerCase())
  );

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

  const handleSave = async () => {
    if (!title.trim()) return;
    setSaving(true);
    try {
      await onSave({
        title: title.trim(),
        priority,
        assignee_ids: assigneeIds,
        due_date: dueDate ? format(dueDate, 'yyyy-MM-dd') : null,
        description: description.trim() || null,
        brief: brief.trim() || null,
        created_by: currentMemberId,
        tag_ids: selectedTagIds,
        recurrence: getRecurrenceValue(),
      });
      toast.success('Task created');
      handleClose();
    } catch {
      toast.error('Failed to create task');
    } finally {
      setSaving(false);
    }
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
          <h2 className="text-sm font-medium text-foreground">New task</h2>
          <button onClick={handleClose} className="text-muted-foreground hover:text-foreground transition-colors">
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="p-4 space-y-4">
          <div className="space-y-1">
            <Label className="text-[10px] text-muted-foreground">Title</Label>
            <Input value={title} onChange={(e) => setTitle(e.target.value)} className="text-xs" autoFocus />
          </div>

          <div className="space-y-1">
            <Label className="text-[10px] text-muted-foreground">Brief (preview on card)</Label>
            <Input
              value={brief}
              onChange={(e) => setBrief(e.target.value.slice(0, 150))}
              className="text-xs"
              placeholder="Short summary (max 150 chars)"
              maxLength={150}
            />
            <span className="text-[9px] text-muted-foreground">{brief.length}/150</span>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Priority</Label>
              <div className="flex gap-1">
                {(['high', 'med', 'low'] as TaskPriority[]).map((p) => (
                  <button
                    key={p}
                    onClick={() => setPriority(p)}
                    className={`flex-1 text-[10px] py-1 rounded transition-all duration-150 ${
                      priority === p
                        ? 'bg-foreground text-primary-foreground scale-105'
                        : 'bg-secondary text-muted-foreground hover:bg-accent'
                    }`}
                  >
                    {p.charAt(0).toUpperCase() + p.slice(1)}
                  </button>
                ))}
              </div>
            </div>

            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Assignees</Label>
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
            </div>

            <div className="col-span-2 space-y-1">
              <Label className="text-[10px] text-muted-foreground">Due date</Label>
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
            </div>
          </div>

          {/* Recurring toggle */}
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

          {/* Tags with search */}
          <div className="space-y-2">
            <Label className="text-[10px] text-muted-foreground">Tags</Label>
            <div className="flex items-center gap-1.5">
              <Search className="w-3 h-3 text-muted-foreground" />
              <Input
                value={tagSearch}
                onChange={(e) => setTagSearch(e.target.value)}
                placeholder="Search tags…"
                className="text-xs h-6 flex-1"
              />
            </div>
            <div className="flex flex-wrap gap-1.5">
              {filteredTags.map((tag) => (
                <button
                  key={tag.id}
                  onClick={() => toggleTag(tag.id)}
                  className={`text-[10px] px-2 py-0.5 rounded border transition-all duration-150 ${
                    selectedTagIds.includes(tag.id)
                      ? 'bg-foreground text-primary-foreground border-foreground scale-105'
                      : 'bg-secondary text-muted-foreground border-border hover:border-foreground/30'
                  }`}
                >
                  #{tag.name}
                </button>
              ))}
            </div>
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
          </div>

          <div className="space-y-1">
            <Label className="text-[10px] text-muted-foreground">Description</Label>
            <Textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Add a description..."
              className="text-xs min-h-[80px]"
            />
          </div>

          <div className="flex gap-2 pt-2">
            <Button size="sm" className="text-xs h-7 flex-1" onClick={handleSave} disabled={saving}>
              {saving ? 'Saving…' : 'Save'}
            </Button>
            <Button size="sm" variant="outline" className="text-xs h-7 flex-1" onClick={handleClose}>Cancel</Button>
          </div>
        </div>
      </div>
    </div>
  );
}
