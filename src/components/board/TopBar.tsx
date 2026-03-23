import { useState } from 'react';
import { Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/hooks/useAuth';
import type { Tag, TeamMember } from '@/lib/types';
import { NewTaskPanel } from './NewTaskPanel';

interface TopBarProps {
  tags: Tag[];
  members: TeamMember[];
  activeAssignee: string | null;
  onAssigneeFilter: (id: string | null) => void;
  onCreateTask: (data: any) => Promise<void>;
  onCreateTag: (name: string) => void;
  currentMemberId: string | null;
}

export function TopBar({
  tags,
  members,
  activeAssignee,
  onAssigneeFilter,
  onCreateTask,
  onCreateTag,
  currentMemberId,
}: TopBarProps) {
  const { member, signOut } = useAuth();
  const [showNewTask, setShowNewTask] = useState(false);

  return (
    <>
      <div className="flex items-center gap-3 px-5 py-3 border-b border-border bg-card">
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

        {/* Person filter pills */}
        <div className="flex items-center gap-1.5 ml-4 overflow-x-auto">
          <button
            onClick={() => onAssigneeFilter(null)}
            className={`px-2.5 py-1 rounded-full text-[11px] font-medium whitespace-nowrap transition-colors ${
              activeAssignee === null
                ? 'bg-foreground text-primary-foreground'
                : 'bg-secondary text-muted-foreground hover:bg-accent'
            }`}
          >
            All
          </button>
          {members.map((m) => (
            <button
              key={m.id}
              onClick={() => onAssigneeFilter(m.id)}
              className={`px-2.5 py-1 rounded-full text-[11px] font-medium whitespace-nowrap transition-colors ${
                activeAssignee === m.id
                  ? 'bg-foreground text-primary-foreground'
                  : 'bg-secondary text-muted-foreground hover:bg-accent'
              }`}
            >
              {m.name}
            </button>
          ))}
        </div>

        <div className="flex-1" />

        <span className="text-[11px] text-muted-foreground mr-2">{member?.name}</span>
        <button onClick={signOut} className="text-[11px] text-muted-foreground hover:text-foreground underline mr-3">
          Sign out
        </button>

        <Button size="sm" className="h-7 text-[11px] gap-1" onClick={() => setShowNewTask(true)}>
          <Plus className="w-3 h-3" />
          New task
        </Button>
      </div>

      {showNewTask && (
        <NewTaskPanel
          tags={tags}
          members={members}
          currentMemberId={currentMemberId}
          onClose={() => setShowNewTask(false)}
          onSave={onCreateTask}
          onCreateTag={onCreateTag}
        />
      )}
    </>
  );
}
