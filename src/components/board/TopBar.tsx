import { useState } from 'react';
import { Settings, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/hooks/useAuth';
import type { TaskCategory, TeamMember } from '@/lib/types';
import { CategoryModal } from './CategoryModal';
import { NewTaskPanel } from './NewTaskPanel';

interface TopBarProps {
  categories: TaskCategory[];
  members: TeamMember[];
  activeCategory: string | null;
  onCategoryFilter: (id: string | null) => void;
  onCreateCategory: (data: { name: string; color: string; position: number }) => void;
  onUpdateCategory: (data: { id: string; name: string }) => void;
  onDeleteCategory: (id: string) => void;
  onCreateTask: (data: any) => void;
  currentMemberId: string | null;
}

export function TopBar({
  categories,
  members,
  activeCategory,
  onCategoryFilter,
  onCreateCategory,
  onUpdateCategory,
  onDeleteCategory,
  onCreateTask,
  currentMemberId,
}: TopBarProps) {
  const { member, signOut } = useAuth();
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [showNewTask, setShowNewTask] = useState(false);
  const isAdmin = member?.role === 'admin';

  return (
    <>
      <div className="flex items-center gap-3 px-5 py-3 border-b border-border bg-card">
        {/* Title */}
        <h1 className="text-sm font-medium text-foreground whitespace-nowrap">Team Board</h1>

        {/* Avatar stack */}
        <div className="flex -space-x-1.5 ml-2">
          {members.slice(0, 6).map((m) => (
            <div
              key={m.id}
              className="w-[26px] h-[26px] rounded-full border-2 border-card flex items-center justify-center text-[9px] font-medium text-primary-foreground"
              style={{ backgroundColor: m.color || '#378ADD' }}
              title={m.name}
            >
              {m.initials}
            </div>
          ))}
        </div>

        {/* Category filter pills */}
        <div className="flex items-center gap-1.5 ml-4 overflow-x-auto">
          <button
            onClick={() => onCategoryFilter(null)}
            className={`px-2.5 py-1 rounded-full text-[11px] font-medium whitespace-nowrap transition-colors ${
              activeCategory === null
                ? 'bg-foreground text-primary-foreground'
                : 'bg-secondary text-muted-foreground hover:bg-accent'
            }`}
          >
            All
          </button>
          {categories.map((cat) => (
            <button
              key={cat.id}
              onClick={() => onCategoryFilter(cat.id)}
              className={`px-2.5 py-1 rounded-full text-[11px] font-medium whitespace-nowrap transition-colors ${
                activeCategory === cat.id
                  ? 'bg-foreground text-primary-foreground'
                  : 'bg-secondary text-muted-foreground hover:bg-accent'
              }`}
            >
              {cat.name}
            </button>
          ))}
        </div>

        {/* Admin gear */}
        {isAdmin && (
          <button
            onClick={() => setShowCategoryModal(true)}
            className="p-1 text-muted-foreground hover:text-foreground transition-colors ml-1"
            title="Manage categories"
          >
            <Settings className="w-3.5 h-3.5" />
          </button>
        )}

        <div className="flex-1" />

        {/* User menu */}
        {member && (
          <span className="text-[11px] text-muted-foreground mr-2">{member.name}</span>
        )}
        <button onClick={signOut} className="text-[11px] text-muted-foreground hover:text-foreground underline mr-3">
          Sign out
        </button>

        {/* New task button */}
        <Button size="sm" className="h-7 text-[11px] gap-1" onClick={() => setShowNewTask(true)}>
          <Plus className="w-3 h-3" />
          New task
        </Button>
      </div>

      {showCategoryModal && (
        <CategoryModal
          categories={categories}
          onClose={() => setShowCategoryModal(false)}
          onCreate={onCreateCategory}
          onUpdate={onUpdateCategory}
          onDelete={onDeleteCategory}
        />
      )}

      {showNewTask && (
        <NewTaskPanel
          categories={categories}
          members={members}
          currentMemberId={currentMemberId}
          onClose={() => setShowNewTask(false)}
          onSave={onCreateTask}
        />
      )}
    </>
  );
}
