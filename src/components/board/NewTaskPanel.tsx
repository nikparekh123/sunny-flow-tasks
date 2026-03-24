import { useState } from 'react';
import { X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { format } from 'date-fns';
import { toast } from 'sonner';
import { PROJECTS } from '@/lib/constants';
import type { Tag, TeamMember, TaskPriority, TaskProject } from '@/lib/types';

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
  const [assigneeId, setAssigneeId] = useState(currentMemberId || 'none');
  const [project, setProject] = useState<TaskProject | null>(null);
  const [dueDate, setDueDate] = useState<Date | undefined>();
  const [description, setDescription] = useState('');
  const [selectedTagIds, setSelectedTagIds] = useState<string[]>([]);
  const [newTag, setNewTag] = useState('');
  const [isClosing, setIsClosing] = useState(false);
  const [saving, setSaving] = useState(false);

  const toggleTag = (id: string) => {
    setSelectedTagIds((prev) =>
      prev.includes(id) ? prev.filter((t) => t !== id) : [...prev, id]
    );
  };

  const handleClose = () => {
    setIsClosing(true);
    setTimeout(onClose, 250);
  };

  const handleSave = async () => {
    if (!title.trim()) return;
    setSaving(true);
    try {
      await onSave({
        title: title.trim(),
        priority,
        assignee_id: assigneeId === 'none' ? null : assigneeId,
        project,
        due_date: dueDate ? format(dueDate, 'yyyy-MM-dd') : null,
        description: description.trim() || null,
        created_by: currentMemberId,
        tag_ids: selectedTagIds,
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
        style={{ backgroundColor: 'rgba(0,0,0,0.2)' }}
        onClick={handleClose}
      />
      <div
        className={`relative w-full max-w-md bg-card shadow-xl border-l border-border overflow-y-auto transition-transform duration-250 ease-out ${
          isClosing ? 'translate-x-full' : 'animate-slide-in-right'
        }`}
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

          {/* Project */}
          <div className="space-y-1">
            <Label className="text-[10px] text-muted-foreground">Project</Label>
            <div className="flex flex-wrap gap-1">
              <button
                onClick={() => setProject(null)}
                className={`text-[10px] px-2 py-1 rounded transition-all duration-150 ${
                  project === null
                    ? 'bg-foreground text-primary-foreground scale-105'
                    : 'bg-secondary text-muted-foreground hover:bg-accent'
                }`}
              >
                None
              </button>
              {PROJECTS.map((p) => (
                <button
                  key={p.id}
                  onClick={() => setProject(p.id)}
                  className={`text-[10px] px-2 py-1 rounded transition-all duration-150 ${
                    project === p.id
                      ? 'bg-foreground text-primary-foreground scale-105'
                      : 'bg-secondary text-muted-foreground hover:bg-accent'
                  }`}
                >
                  {p.label}
                </button>
              ))}
            </div>
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
              <Label className="text-[10px] text-muted-foreground">Assignee</Label>
              <div className="flex flex-wrap gap-1">
                <button
                  onClick={() => setAssigneeId('none')}
                  className={`text-[10px] px-2 py-1 rounded transition-all duration-150 ${
                    assigneeId === 'none'
                      ? 'bg-foreground text-primary-foreground scale-105'
                      : 'bg-secondary text-muted-foreground hover:bg-accent'
                  }`}
                >
                  None
                </button>
                {members.map((m) => (
                  <button
                    key={m.id}
                    onClick={() => setAssigneeId(m.id)}
                    className={`text-[10px] px-2 py-1 rounded transition-all duration-150 ${
                      assigneeId === m.id
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

          {/* Tags */}
          <div className="space-y-2">
            <Label className="text-[10px] text-muted-foreground">Tags</Label>
            <div className="flex flex-wrap gap-1.5">
              {tags.map((tag) => (
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
