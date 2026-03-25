import { useState, useEffect } from 'react';
import { X, RotateCcw, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import type { TaskWithDetail } from '@/lib/types';

interface Props {
  open: boolean;
  onClose: () => void;
  onRestore: (id: string) => void;
  onPermanentDelete: (id: string) => void;
}

export function ArchivePanel({ open, onClose, onRestore, onPermanentDelete }: Props) {
  const [tasks, setTasks] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [isClosing, setIsClosing] = useState(false);

  useEffect(() => {
    if (open) {
      setIsClosing(false);
      fetchArchived();
    }
  }, [open]);

  const fetchArchived = async () => {
    setLoading(true);
    const { data } = await supabase
      .from('tasks')
      .select('id, title, column, priority, archived_at')
      .eq('archived', true)
      .order('archived_at', { ascending: false });
    setTasks(data ?? []);
    setLoading(false);
  };

  const handleClose = () => {
    setIsClosing(true);
    setTimeout(onClose, 250);
  };

  if (!open) return null;

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
          <h2 className="text-sm font-medium text-foreground">Archive</h2>
          <button onClick={handleClose} className="text-muted-foreground hover:text-foreground">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-4 space-y-2">
          {loading ? (
            <p className="text-xs text-muted-foreground">Loading…</p>
          ) : tasks.length === 0 ? (
            <p className="text-xs text-muted-foreground">No archived tasks.</p>
          ) : (
            tasks.map((t) => (
              <div key={t.id} className="flex items-center gap-2 p-3 rounded-lg border border-border">
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-medium truncate">{t.title}</p>
                  <p className="text-[10px] text-muted-foreground">
                    {t.archived_at ? new Date(t.archived_at).toLocaleDateString() : ''}
                  </p>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 w-7 p-0"
                  onClick={() => {
                    onRestore(t.id);
                    setTasks((prev) => prev.filter((x) => x.id !== t.id));
                  }}
                  title="Restore"
                >
                  <RotateCcw className="w-3.5 h-3.5" />
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 w-7 p-0 text-destructive hover:text-destructive"
                  onClick={() => {
                    onPermanentDelete(t.id);
                    setTasks((prev) => prev.filter((x) => x.id !== t.id));
                  }}
                  title="Delete permanently"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </Button>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
