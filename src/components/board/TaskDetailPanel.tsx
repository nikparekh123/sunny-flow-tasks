import { useState, useEffect } from 'react';
import { X } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { Button } from '@/components/ui/button';
import { format } from 'date-fns';
import { COLUMNS, PRIORITY_COLORS } from '@/lib/constants';
import type { TaskWithDetail, Tag, TeamMember, TaskColumn, TaskPriority } from '@/lib/types';

interface Props {
  task: TaskWithDetail;
  tags: Tag[];
  members: TeamMember[];
  onClose: () => void;
  onUpdate: (data: { id: string } & Record<string, any>) => void;
  onCreateTag: (name: string) => void;
}

export function TaskDetailPanel({ task, tags, members, onClose, onUpdate, onCreateTag }: Props) {
  const [title, setTitle] = useState(task.title);
  const [description, setDescription] = useState(task.description || '');
  const [newTag, setNewTag] = useState('');
  const [isClosing, setIsClosing] = useState(false);

  useEffect(() => {
    setTitle(task.title);
    setDescription(task.description || '');
  }, [task]);

  const handleClose = () => {
    setIsClosing(true);
    setTimeout(onClose, 250);
  };

  const handleTitleBlur = () => {
    if (title.trim() && title !== task.title) {
      onUpdate({ id: task.id, title: title.trim() });
    }
  };

  const handleDescBlur = () => {
    if (description !== (task.description || '')) {
      onUpdate({ id: task.id, description: description || null });
    }
  };

  const currentTagIds = (task.tags || []).map((t) => t.id);

  const toggleTag = (tagId: string) => {
    const newIds = currentTagIds.includes(tagId)
      ? currentTagIds.filter((id) => id !== tagId)
      : [...currentTagIds, tagId];
    onUpdate({ id: task.id, tag_ids: newIds });
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
          <button onClick={handleClose} className="text-muted-foreground hover:text-foreground transition-colors">
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="p-4 space-y-4">
          <Input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onBlur={handleTitleBlur}
            className="text-sm font-medium border-none shadow-none px-0 focus-visible:ring-0"
          />

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Status</Label>
              <Select
                value={task.column}
                onValueChange={(v) => onUpdate({ id: task.id, column: v as TaskColumn })}
              >
                <SelectTrigger className="text-xs h-7">
                  <SelectValue />
                </SelectTrigger>
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
            </div>

            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Priority</Label>
              <Select
                value={task.priority}
                onValueChange={(v) => onUpdate({ id: task.id, priority: v as TaskPriority })}
              >
                <SelectTrigger className="text-xs h-7">
                  <SelectValue />
                </SelectTrigger>
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
            </div>

            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Assignee</Label>
              <Select
                value={task.assignee_id || 'none'}
                onValueChange={(v) => onUpdate({ id: task.id, assignee_id: v === 'none' ? null : v })}
              >
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

            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Due date</Label>
              <Popover>
                <PopoverTrigger asChild>
                  <Button variant="outline" className="w-full justify-start text-xs h-7 font-normal">
                    {task.due_date ? format(new Date(task.due_date), 'MMM d, yyyy') : 'No due date'}
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-auto p-0" align="start">
                  <Calendar
                    mode="single"
                    selected={task.due_date ? new Date(task.due_date) : undefined}
                    onSelect={(d) => onUpdate({ id: task.id, due_date: d ? format(d, 'yyyy-MM-dd') : null })}
                  />
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
                  className={`text-[10px] px-2 py-0.5 rounded border transition-all duration-150 ${
                    currentTagIds.includes(tag.id)
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
              onBlur={handleDescBlur}
              placeholder="Add a description..."
              className="text-xs min-h-[100px]"
            />
          </div>
        </div>
      </div>
    </div>
  );
}
