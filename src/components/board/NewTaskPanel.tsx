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
import type { Tag, TeamMember, TaskPriority } from '@/lib/types';

interface Props {
  tags: Tag[];
  members: TeamMember[];
  currentMemberId: string | null;
  onClose: () => void;
  onSave: (data: any) => void;
  onCreateTag: (name: string) => void;
}

export function NewTaskPanel({ tags, members, currentMemberId, onClose, onSave, onCreateTag }: Props) {
  const [title, setTitle] = useState('');
  const [priority, setPriority] = useState<TaskPriority>('med');
  const [assigneeId, setAssigneeId] = useState('none');
  const [dueDate, setDueDate] = useState<Date | undefined>();
  const [description, setDescription] = useState('');
  const [selectedTagIds, setSelectedTagIds] = useState<string[]>([]);
  const [newTag, setNewTag] = useState('');

  const toggleTag = (id: string) => {
    setSelectedTagIds((prev) =>
      prev.includes(id) ? prev.filter((t) => t !== id) : [...prev, id]
    );
  };

  const handleSave = () => {
    if (!title.trim()) return;
    onSave({
      title: title.trim(),
      priority,
      assignee_id: assigneeId === 'none' ? null : assigneeId,
      due_date: dueDate ? format(dueDate, 'yyyy-MM-dd') : null,
      description: description.trim() || null,
      created_by: currentMemberId,
      tag_ids: selectedTagIds,
    });
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/20" onClick={onClose} />
      <div className="relative w-full max-w-md bg-card shadow-xl border-l border-border overflow-y-auto">
        <div className="flex items-center justify-between p-4 border-b border-border">
          <h2 className="text-sm font-medium text-foreground">New task</h2>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground">
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="p-4 space-y-4">
          <div className="space-y-1">
            <Label className="text-[10px] text-muted-foreground">Title</Label>
            <Input value={title} onChange={(e) => setTitle(e.target.value)} className="text-xs" autoFocus />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Priority</Label>
              <div className="flex gap-1">
                {(['high', 'med', 'low'] as TaskPriority[]).map((p) => (
                  <button
                    key={p}
                    onClick={() => setPriority(p)}
                    className={`flex-1 text-[10px] py-1 rounded transition-colors ${
                      priority === p
                        ? 'bg-foreground text-primary-foreground'
                        : 'bg-secondary text-muted-foreground hover:bg-accent'
                    }`}
                  >
                    {p.charAt(0).toUpperCase() + p.slice(1)}
                  </button>
                ))}
              </div>
            </div>

            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Assignee</Label>
              <Select value={assigneeId} onValueChange={setAssigneeId}>
                <SelectTrigger className="text-xs h-7">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Unassigned</SelectItem>
                  {members.map((m) => (
                    <SelectItem key={m.id} value={m.id}>{m.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
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

          {/* Tags */}
          <div className="space-y-2">
            <Label className="text-[10px] text-muted-foreground">Tags</Label>
            <div className="flex flex-wrap gap-1.5">
              {tags.map((tag) => (
                <button
                  key={tag.id}
                  onClick={() => toggleTag(tag.id)}
                  className={`text-[10px] px-2 py-0.5 rounded border transition-colors ${
                    selectedTagIds.includes(tag.id)
                      ? 'bg-foreground text-primary-foreground border-foreground'
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
            <Button size="sm" className="text-xs h-7 flex-1" onClick={handleSave}>Save</Button>
            <Button size="sm" variant="outline" className="text-xs h-7 flex-1" onClick={onClose}>Cancel</Button>
          </div>
        </div>
      </div>
    </div>
  );
}
