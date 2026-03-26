import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Trash2, Check } from 'lucide-react';
import type { Tag } from '@/lib/types';

const PRESET_COLORS = [
  '#888888', '#E24B4A', '#EF9F27', '#639922', '#378ADD',
  '#7F77DD', '#D85A30', '#1D9E75', '#5DCAA5', '#E87BA8',
];

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  tags: Tag[];
  onUpdateTag: (id: string, updates: { name?: string; color?: string }) => void;
  onDeleteTag: (id: string) => void;
}

export function TagManagementModal({ open, onOpenChange, tags, onUpdateTag, onDeleteTag }: Props) {
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');
  const [editColor, setEditColor] = useState('');
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null);

  const startEdit = (tag: Tag) => {
    setEditingId(tag.id);
    setEditName(tag.name);
    setEditColor(tag.color || '#888888');
  };

  const saveEdit = () => {
    if (editingId && editName.trim()) {
      onUpdateTag(editingId, { name: editName.trim(), color: editColor });
      setEditingId(null);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="text-sm">Manage Tags</DialogTitle>
        </DialogHeader>
        <div className="space-y-2 max-h-96 overflow-y-auto">
          {tags.length === 0 && (
            <p className="text-xs text-muted-foreground text-center py-4">No tags created yet</p>
          )}
          {tags.map((tag) => (
            <div key={tag.id} className="border border-border rounded-lg p-2">
              {editingId === tag.id ? (
                <div className="space-y-2">
                  <Input
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    className="text-xs h-7"
                    autoFocus
                  />
                  <div className="flex gap-1 flex-wrap">
                    {PRESET_COLORS.map((c) => (
                      <button
                        key={c}
                        onClick={() => setEditColor(c)}
                        className="w-5 h-5 rounded-full border-2 transition-all"
                        style={{
                          backgroundColor: c,
                          borderColor: editColor === c ? 'hsl(var(--foreground))' : 'transparent',
                        }}
                      />
                    ))}
                  </div>
                  <div className="flex gap-1.5">
                    <Button size="sm" className="text-[10px] h-6 flex-1" onClick={saveEdit}>Save</Button>
                    <Button size="sm" variant="outline" className="text-[10px] h-6 flex-1" onClick={() => setEditingId(null)}>Cancel</Button>
                  </div>
                </div>
              ) : deleteConfirmId === tag.id ? (
                <div className="space-y-2">
                  <p className="text-[10px] text-destructive">Delete "{tag.name}"? This removes it from all tasks.</p>
                  <div className="flex gap-1.5">
                    <Button size="sm" variant="destructive" className="text-[10px] h-6 flex-1" onClick={() => { onDeleteTag(tag.id); setDeleteConfirmId(null); }}>
                      Delete
                    </Button>
                    <Button size="sm" variant="outline" className="text-[10px] h-6 flex-1" onClick={() => setDeleteConfirmId(null)}>Cancel</Button>
                  </div>
                </div>
              ) : (
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className="w-3 h-3 rounded-full" style={{ backgroundColor: tag.color || '#888' }} />
                    <span className="text-xs text-foreground">#{tag.name}</span>
                  </div>
                  <div className="flex items-center gap-1">
                    <Button variant="ghost" size="sm" className="h-6 w-6 p-0" onClick={() => startEdit(tag)}>
                      <Check className="w-3 h-3" />
                    </Button>
                    <Button variant="ghost" size="sm" className="h-6 w-6 p-0 text-destructive" onClick={() => setDeleteConfirmId(tag.id)}>
                      <Trash2 className="w-3 h-3" />
                    </Button>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
