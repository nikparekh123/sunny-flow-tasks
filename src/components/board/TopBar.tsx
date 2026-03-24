import { useState } from 'react';
import { Plus, Settings, Users, Palette, User, Shield, LogOut } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAuth } from '@/hooks/useAuth';
import { PROJECTS } from '@/lib/constants';
import type { Tag, TeamMember, TaskProject } from '@/lib/types';
import { NewTaskPanel } from './NewTaskPanel';

interface TopBarProps {
  tags: Tag[];
  members: TeamMember[];
  activeAssignee: string | null;
  activeProject: TaskProject | null;
  onAssigneeFilter: (id: string | null) => void;
  onProjectFilter: (project: TaskProject | null) => void;
  onCreateTask: (data: any) => Promise<void>;
  onCreateTag: (name: string) => void;
  currentMemberId: string | null;
}

export function TopBar({
  tags,
  members,
  activeAssignee,
  activeProject,
  onAssigneeFilter,
  onProjectFilter,
  onCreateTask,
  onCreateTag,
  currentMemberId,
}: TopBarProps) {
  const { signOut } = useAuth();
  const [showNewTask, setShowNewTask] = useState(false);

  return (
    <>
      <div className="flex items-center gap-3 px-5 py-3 border-b border-border bg-card">
        <h1 className="text-sm font-semibold text-foreground whitespace-nowrap">SunnyFi Board</h1>

        {/* Project filter tabs */}
        <div className="flex items-center gap-1 ml-4 overflow-x-auto">
          <button
            onClick={() => onProjectFilter(null)}
            className={`px-2.5 py-1 rounded-full text-[11px] font-medium whitespace-nowrap transition-colors ${
              activeProject === null
                ? 'bg-foreground text-primary-foreground'
                : 'bg-secondary text-muted-foreground hover:bg-accent'
            }`}
          >
            All
          </button>
          {PROJECTS.map((p) => (
            <button
              key={p.id}
              onClick={() => onProjectFilter(p.id)}
              className={`px-2.5 py-1 rounded-full text-[11px] font-medium whitespace-nowrap transition-colors ${
                activeProject === p.id
                  ? 'bg-foreground text-primary-foreground'
                  : 'bg-secondary text-muted-foreground hover:bg-accent'
              }`}
            >
              {p.label}
            </button>
          ))}
        </div>

        <div className="flex-1" />

        {/* User filter dropdown */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="sm" className="h-7 text-[11px] gap-1">
              <User className="w-3 h-3" />
              {activeAssignee
                ? members.find((m) => m.id === activeAssignee)?.name || 'User'
                : 'All Users'}
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => onAssigneeFilter(null)}>
              All Users
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            {members.map((m) => (
              <DropdownMenuItem key={m.id} onClick={() => onAssigneeFilter(m.id)}>
                <span
                  className="w-5 h-5 rounded-full flex items-center justify-center text-[9px] font-medium text-primary-foreground mr-2"
                  style={{ backgroundColor: m.color || '#378ADD' }}
                >
                  {m.initials}
                </span>
                {m.name}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>

        <Button size="sm" className="h-7 text-[11px] gap-1" onClick={() => setShowNewTask(true)}>
          <Plus className="w-3 h-3" />
          New task
        </Button>

        {/* Settings gear */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="sm" className="h-7 w-7 p-0">
              <Settings className="w-3.5 h-3.5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem disabled>
              <Users className="w-3.5 h-3.5 mr-2" /> Invite Users
            </DropdownMenuItem>
            <DropdownMenuItem disabled>
              <Palette className="w-3.5 h-3.5 mr-2" /> Personalization
            </DropdownMenuItem>
            <DropdownMenuItem disabled>
              <User className="w-3.5 h-3.5 mr-2" /> User Settings
            </DropdownMenuItem>
            <DropdownMenuItem disabled>
              <Shield className="w-3.5 h-3.5 mr-2" /> Admin Settings
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={signOut}>
              <LogOut className="w-3.5 h-3.5 mr-2" /> Sign Out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
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
