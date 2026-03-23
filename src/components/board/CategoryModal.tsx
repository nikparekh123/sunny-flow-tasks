import { useState } from 'react';
import { X, Pencil } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { CATEGORY_COLOR_SEQUENCE } from '@/lib/constants';
import type { TaskCategory } from '@/lib/types';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';

interface Props {
  categories: TaskCategory[];
  onClose: () => void;
  onCreate: (data: { name: string; color: string; position: number }) => void;
  onUpdate: (data: { id: string; name: string }) => void;
  onDelete: (id: string) => void;
}

export function CategoryModal({ categories, onClose, onCreate, onUpdate, onDelete }: Props) {
  const [newName, setNewName] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');
  const [deleteId, setDeleteId] = useState<string | null>(null);

  const handleAdd = () => {
    if (!newName.trim()) return;
    const colorIdx = categories.length % CATEGORY_COLOR_SEQUENCE.length;
    onCreate({
      name: newName.trim(),
      color: CATEGORY_COLOR_SEQUENCE[colorIdx],
      position: categories.length,
    });
    setNewName('');
  };

  const handleRename = (id: string) => {
    if (!editName.trim()) return;
    onUpdate({ id, name: editName.trim() });
    setEditingId(null);
  };

  return (
    <>
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
        <div className="bg-card rounded-lg shadow-lg w-full max-w-sm mx-4">
          <div className="flex items-center justify-between p-4 border-b border-border">
            <h2 className="text-sm font-medium">Manage Categories</h2>
            <button onClick={onClose} className="text-muted-foreground hover:text-foreground">
              <X className="w-4 h-4" />
            </button>
          </div>
          <div className="p-4 space-y-1.5 max-h-80 overflow-y-auto">
            {categories.map((cat) => (
              <div key={cat.id} className="group flex items-center gap-2 py-1.5 px-2 rounded hover:bg-secondary">
                <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ backgroundColor: cat.color }} />
                {editingId === cat.id ? (
                  <Input
                    autoFocus
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    onKeyDown={(e) => e.key === 'Enter' && handleRename(cat.id)}
                    onBlur={() => handleRename(cat.id)}
                    className="h-6 text-xs flex-1"
                  />
                ) : (
                  <>
                    <span className="text-xs flex-1">{cat.name}</span>
                    <button
                      onClick={() => { setEditingId(cat.id); setEditName(cat.name); }}
                      className="opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-foreground"
                    >
                      <Pencil className="w-3 h-3" />
                    </button>
                    <button
                      onClick={() => setDeleteId(cat.id)}
                      className="opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-destructive"
                    >
                      <X className="w-3 h-3" />
                    </button>
                  </>
                )}
              </div>
            ))}
          </div>
          <div className="p-4 border-t border-border flex gap-2">
            <Input
              placeholder="New category name"
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
              className="h-7 text-xs flex-1"
            />
            <Button size="sm" className="h-7 text-[11px]" onClick={handleAdd}>Add</Button>
          </div>
        </div>
      </div>

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete category?</AlertDialogTitle>
            <AlertDialogDescription>
              Tasks in this category will have their category removed.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => { if (deleteId) onDelete(deleteId); setDeleteId(null); }}>
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
