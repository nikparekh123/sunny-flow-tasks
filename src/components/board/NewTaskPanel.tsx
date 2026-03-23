import { useState } from 'react';
import { X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { format } from 'date-fns';
import type { TaskCategory, TeamMember, TaskPriority } from '@/lib/types';

interface Props {
  categories: TaskCategory[];
  members: TeamMember[];
  currentMemberId: string | null;
  onClose: () => void;
  onSave: (data: any) => void;
}

export function NewTaskPanel({ categories, members, currentMemberId, onClose, onSave }: Props) {
  const [title, setTitle] = useState('');
  const [priority, setPriority] = useState<TaskPriority>('med');
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [assigneeId, setAssigneeId] = useState<string | null>(null);
  const [dueDate, setDueDate] = useState<Date | undefined>();
  const [description, setDescription] = useState('');

  const handleSave = () => {
    if (!title.trim()) return;
    onSave({
      title: title.trim(),
      priority,
      category_id: categoryId,
      assignee_id: assigneeId,
      due_date: dueDate ? format(dueDate, 'yyyy-MM-dd') : null,
      description: description || null,
      created_by: currentMemberId,
    });
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/20" onClick={onClose} />
      <div className="relative w-full max-w-md bg-card shadow-xl border-l border-border overflow-y-auto">
        <div className="flex items-center justify-between p-4 border-b border-border">
          <h2 className="text-sm font-medium">New Task</h2>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground">
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="p-4 space-y-4">
          <div className="space-y-1.5">
            <Label className="text-[11px]">Title</Label>
            <Input
              autoFocus
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Task title"
              className="text-xs"
            />
          </div>

          <div className="space-y-1.5">
            <Label className="text-[11px]">Category</Label>
            <Select value={categoryId || 'none'} onValueChange={(v) => setCategoryId(v === 'none' ? null : v)}>
              <SelectTrigger className="text-xs h-8">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">None</SelectItem>
                {categories.map((c) => (
                  <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label className="text-[11px]">Priority</Label>
            <div className="flex gap-1">
              {(['high', 'med', 'low'] as TaskPriority[]).map((p) => (
                <button
                  key={p}
                  onClick={() => setPriority(p)}
                  className={`px-3 py-1 rounded text-[11px] font-medium transition-colors ${
                    priority === p
                      ? 'bg-foreground text-primary-foreground'
                      : 'bg-secondary text-muted-foreground'
                  }`}
                >
                  {p.charAt(0).toUpperCase() + p.slice(1)}
                </button>
              ))}
            </div>
          </div>

          <div className="space-y-1.5">
            <Label className="text-[11px]">Due date</Label>
            <Popover>
              <PopoverTrigger asChild>
                <Button variant="outline" className="w-full justify-start text-xs h-8 font-normal">
                  {dueDate ? format(dueDate, 'MMM d, yyyy') : 'Pick a date'}
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0" align="start">
                <Calendar mode="single" selected={dueDate} onSelect={setDueDate} />
              </PopoverContent>
            </Popover>
          </div>

          <div className="space-y-1.5">
            <Label className="text-[11px]">Assignee</Label>
            <Select value={assigneeId || 'none'} onValueChange={(v) => setAssigneeId(v === 'none' ? null : v)}>
              <SelectTrigger className="text-xs h-8">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">Unassigned</SelectItem>
                {members.map((m) => (
                  <SelectItem key={m.id} value={m.id}>
                    <span className="flex items-center gap-2">
                      <span
                        className="w-4 h-4 rounded-full flex items-center justify-center text-[7px] text-primary-foreground font-medium"
                        style={{ backgroundColor: m.color || '#378ADD' }}
                      >
                        {m.initials}
                      </span>
                      {m.name}
                    </span>
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label className="text-[11px]">Description</Label>
            <Textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Add a description..."
              className="text-xs min-h-[80px]"
            />
          </div>

          <div className="flex gap-2 pt-2">
            <Button className="flex-1 text-xs h-8" onClick={handleSave}>Save</Button>
            <Button variant="outline" className="flex-1 text-xs h-8" onClick={onClose}>Cancel</Button>
          </div>
        </div>
      </div>
    </div>
  );
}
