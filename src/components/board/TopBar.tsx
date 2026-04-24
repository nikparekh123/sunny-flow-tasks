import { useEffect, useRef, useState } from 'react';
import {
  Plus,
  Settings,
  User,
  Shield,
  LogOut,
  Search,
  SlidersHorizontal,
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAuth } from '@/hooks/useAuth';
import type { Tag as TagType, TeamMember } from '@/lib/types';
import { NewTaskPanel } from './NewTaskPanel';
import { UserSettingsModal } from '@/components/settings/UserSettingsModal';
import { AdminSettingsModal } from '@/components/settings/AdminSettingsModal';
import { NotificationBell } from './NotificationBell';

export type ViewMode = 'board' | 'people';

type AssigneeScope = 'all' | 'mine' | 'unassigned';

export interface FilterState {
  scope: AssigneeScope;
  priorityHigh: boolean;
  dueWeek: boolean;
  stale: boolean;
  tagIds: string[];
}

interface TopBarProps {
  tags: TagType[];
  members: TeamMember[];
  activeAssignee: string | null;
  onAssigneeFilter: (id: string | null) => void;
  onCreateTask: (data: any) => Promise<void>;
  onCreateTag: (name: string) => void;
  currentMemberId: string | null;
  searchQuery: string;
  onSearchChange: (query: string) => void;
  onNavigateToTask?: (taskId: string) => void;
  filters: FilterState;
  onFiltersChange: (next: FilterState) => void;
}

export function TopBar({
  tags,
  members,
  activeAssignee,
  onAssigneeFilter,
  onCreateTask,
  onCreateTag,
  currentMemberId,
  searchQuery,
  onSearchChange,
  onNavigateToTask,
  filters,
  onFiltersChange,
}: TopBarProps) {
  const { signOut, member } = useAuth();
  const [showNewTask, setShowNewTask] = useState(false);
  const [showUserSettings, setShowUserSettings] = useState(false);
  const [showAdminSettings, setShowAdminSettings] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);

  const isAdmin = member?.role === 'admin';

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = document.activeElement as HTMLElement | null;
      const inField =
        t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
      if (e.key === '/' && !inField) {
        e.preventDefault();
        searchRef.current?.focus();
      }
      if ((e.key === 'n' || e.key === 'N') && !e.metaKey && !e.ctrlKey && !inField) {
        e.preventDefault();
        setShowNewTask(true);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <>
      <div className="flex items-center gap-[10px] flex-wrap px-5 md:px-7 pt-4 pb-3">
        {/* Search */}
        <div
          className="flex items-center gap-2 rounded-lg flex-1"
          style={{
            minWidth: 220,
            maxWidth: 360,
            padding: '8px 12px',
            background: 'rgba(15,51,51,0.6)',
          }}
        >
          <Search
            className="w-[13px] h-[13px]"
            style={{ color: 'var(--owl-text-muted)' }}
          />
          <input
            ref={searchRef}
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder="Search cards, people, tags…"
            className="flex-1 bg-transparent outline-none text-[13px]"
            style={{ color: 'var(--owl-text-primary)' }}
          />
          <Kbd>/</Kbd>
        </div>

        <div className="flex-1" />

        <NotificationBell onNavigateToTask={onNavigateToTask} />

        {/* Settings — only account + sign out. Rules + Invite removed. */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              className="inline-flex items-center justify-center rounded-md transition-colors"
              style={{
                width: 32,
                height: 32,
                background: 'transparent',
                color: 'var(--owl-text-muted)',
                border: 'none',
                cursor: 'pointer',
              }}
              aria-label="Settings"
            >
              <Settings className="w-4 h-4" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => setShowUserSettings(true)}>
              <User className="w-3.5 h-3.5 mr-2" /> User settings
            </DropdownMenuItem>
            {isAdmin && (
              <DropdownMenuItem onClick={() => setShowAdminSettings(true)}>
                <Shield className="w-3.5 h-3.5 mr-2" /> Admin settings
              </DropdownMenuItem>
            )}
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={signOut}>
              <LogOut className="w-3.5 h-3.5 mr-2" /> Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>

        <button
          onClick={() => setShowNewTask(true)}
          className="inline-flex items-center gap-[6px] rounded-lg transition-colors"
          style={{
            fontSize: 13,
            fontWeight: 500,
            padding: '9px 16px',
            background: 'var(--owl-neon)',
            color: '#0a2828',
            border: 'none',
            cursor: 'pointer',
          }}
        >
          <Plus className="w-3.5 h-3.5" />
          New card
          <span
            style={{
              fontFamily: 'var(--owl-font-mono)',
              fontSize: 10,
              opacity: 0.7,
              border: '1px solid rgba(10,40,40,0.35)',
              padding: '0 4px',
              borderRadius: 3,
              marginLeft: 2,
            }}
          >
            N
          </span>
        </button>
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

      <UserSettingsModal open={showUserSettings} onOpenChange={setShowUserSettings} />
      {isAdmin && (
        <AdminSettingsModal open={showAdminSettings} onOpenChange={setShowAdminSettings} />
      )}
    </>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <span
      style={{
        fontFamily: 'var(--owl-font-mono)',
        fontSize: 10,
        color: 'var(--owl-text-label)',
        border: '1px solid var(--owl-text-label)',
        padding: '1px 5px',
        borderRadius: 3,
      }}
    >
      {children}
    </span>
  );
}
