import { useEffect, useRef, useState } from 'react';
import {
  Plus,
  Settings,
  Users,
  User,
  Shield,
  LogOut,
  Search,
  Archive,
  Zap,
  LayoutGrid,
  UsersRound,
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAuth } from '@/hooks/useAuth';
import { useNavigate } from 'react-router-dom';
import type { Tag as TagType, TeamMember } from '@/lib/types';
import { NewTaskPanel } from './NewTaskPanel';
import { UserSettingsModal } from '@/components/settings/UserSettingsModal';
import { AdminSettingsModal } from '@/components/settings/AdminSettingsModal';
import { InviteUserModal } from '@/components/settings/InviteUserModal';
import { NotificationBell } from './NotificationBell';

export type ViewMode = 'board' | 'people';

type AssigneeScope = 'all' | 'mine' | 'unassigned';

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
  activeTagIds: string[];
  onTagFilter: (ids: string[]) => void;
  onOpenArchive: () => void;
  activeView: ViewMode;
  onViewChange: (view: ViewMode) => void;
  onNavigateToTask?: (taskId: string) => void;
  assigneeScope?: AssigneeScope;
  onAssigneeScopeChange?: (scope: AssigneeScope) => void;
}

export function TopBar({
  tags,
  members,
  onCreateTask,
  onCreateTag,
  currentMemberId,
  searchQuery,
  onSearchChange,
  onOpenArchive,
  activeView,
  onViewChange,
  onNavigateToTask,
  assigneeScope = 'all',
  onAssigneeScopeChange,
}: TopBarProps) {
  const { signOut, member } = useAuth();
  const navigate = useNavigate();
  const [showNewTask, setShowNewTask] = useState(false);
  const [showUserSettings, setShowUserSettings] = useState(false);
  const [showAdminSettings, setShowAdminSettings] = useState(false);
  const [showInvite, setShowInvite] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);

  const isAdmin = member?.role === 'admin';

  // Keyboard shortcuts
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = document.activeElement as HTMLElement | null;
      const inField =
        t &&
        (t.tagName === 'INPUT' ||
          t.tagName === 'TEXTAREA' ||
          t.isContentEditable);
      if (e.key === '/' && !inField) {
        e.preventDefault();
        searchRef.current?.focus();
      }
      if (
        (e.key === 'n' || e.key === 'N') &&
        !e.metaKey &&
        !e.ctrlKey &&
        !inField
      ) {
        e.preventDefault();
        setShowNewTask(true);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const viewButtons: { mode: ViewMode; icon: typeof LayoutGrid; label: string }[] = [
    { mode: 'board', icon: LayoutGrid, label: 'Grid' },
    { mode: 'people', icon: UsersRound, label: 'People' },
  ];

  return (
    <>
      <div
        className="flex items-center gap-[10px] flex-wrap px-5 md:px-7 pt-4 pb-3"
      >
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
          <Search className="w-[13px] h-[13px]" style={{ color: 'var(--owl-text-muted)' }} />
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

        {/* View toggle */}
        <div
          className="inline-flex rounded-lg"
          style={{ background: 'rgba(15,51,51,0.6)', padding: 3 }}
        >
          {viewButtons.map(({ mode, icon: Icon, label }) => {
            const on = activeView === mode;
            return (
              <button
                key={label}
                onClick={() => onViewChange(mode)}
                className="inline-flex items-center gap-[6px] rounded-md transition-colors"
                style={{
                  fontSize: 12,
                  fontWeight: 500,
                  padding: '6px 12px',
                  background: on ? 'var(--owl-elevated)' : 'transparent',
                  color: on ? 'var(--owl-text-primary)' : 'var(--owl-text-muted)',
                  border: 'none',
                  cursor: 'pointer',
                }}
              >
                <Icon className="w-3 h-3" />
                {label}
              </button>
            );
          })}
        </div>

        {/* Assignee scope pills */}
        <Pill
          active={assigneeScope === 'all'}
          onClick={() => onAssigneeScopeChange?.('all')}
        >
          All
        </Pill>
        <Pill
          active={assigneeScope === 'mine'}
          onClick={() => onAssigneeScopeChange?.('mine')}
        >
          Mine
        </Pill>
        <Pill
          active={assigneeScope === 'unassigned'}
          onClick={() => onAssigneeScopeChange?.('unassigned')}
        >
          Unassigned
        </Pill>

        <div className="flex-1" />

        {/* Secondary actions */}
        <NotificationBell onNavigateToTask={onNavigateToTask} />

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
            <DropdownMenuItem onClick={onOpenArchive}>
              <Archive className="w-3.5 h-3.5 mr-2" /> Archive
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => navigate('/rules')}>
              <Zap className="w-3.5 h-3.5 mr-2" /> Rules
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={() => setShowInvite(true)}>
              <Users className="w-3.5 h-3.5 mr-2" /> Invite users
            </DropdownMenuItem>
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

        {/* New card CTA */}
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
      <InviteUserModal open={showInvite} onOpenChange={setShowInvite} />
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
        color: 'var(--owl-text-disabled)',
        border: '1px solid var(--owl-text-disabled)',
        padding: '1px 5px',
        borderRadius: 3,
      }}
    >
      {children}
    </span>
  );
}

function Pill({
  active,
  onClick,
  children,
}: {
  active?: boolean;
  onClick?: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className="rounded-full transition-colors"
      style={{
        fontSize: 12,
        fontWeight: 500,
        padding: '7px 14px',
        background: active ? 'rgba(210,230,50,0.1)' : 'rgba(15,51,51,0.5)',
        color: active ? 'var(--owl-neon)' : 'var(--owl-text-muted)',
        border: 'none',
        cursor: 'pointer',
      }}
    >
      {children}
    </button>
  );
}
