import { useState } from 'react';
import { Plus, Settings, Users, Palette, User, Shield, LogOut, Eye, Search, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { useAuth } from '@/hooks/useAuth';
import type { Tag, TeamMember } from '@/lib/types';
import { NewTaskPanel } from './NewTaskPanel';
import { UserSettingsModal } from '@/components/settings/UserSettingsModal';
import { AdminSettingsModal } from '@/components/settings/AdminSettingsModal';

interface TopBarProps {
  tags: Tag[];
  members: TeamMember[];
  activeAssignee: string | null;
  onAssigneeFilter: (id: string | null) => void;
  onCreateTask: (data: any) => Promise<void>;
  onCreateTag: (name: string) => void;
  currentMemberId: string | null;
  searchQuery: string;
  onSearchChange: (query: string) => void;
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
}: TopBarProps) {
  const { signOut, member } = useAuth();
  const [showNewTask, setShowNewTask] = useState(false);
  const [showUserSettings, setShowUserSettings] = useState(false);
  const [showAdminSettings, setShowAdminSettings] = useState(false);
  const [showSearch, setShowSearch] = useState(false);

  const isAdmin = member?.role === 'admin';

  return (
    <>
      <div className="flex items-center gap-3 px-5 py-3 border-b border-border bg-card">
        <h1 className="text-sm font-semibold text-foreground whitespace-nowrap">SunnyFi Board</h1>

        <div className="flex-1" />

        {/* Search */}
        {showSearch ? (
          <div className="flex items-center gap-1.5 max-w-xs w-full">
            <Search className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
            <Input
              value={searchQuery}
              onChange={(e) => onSearchChange(e.target.value)}
              placeholder="Search tasks…"
              className="h-7 text-xs"
              autoFocus
            />
            <button
              onClick={() => { setShowSearch(false); onSearchChange(''); }}
              className="text-muted-foreground hover:text-foreground"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        ) : (
          <Button variant="ghost" size="sm" className="h-7 w-7 p-0" onClick={() => setShowSearch(true)}>
            <Search className="w-3.5 h-3.5" />
          </Button>
        )}

        {/* User avatar circles */}
        <div className="flex items-center -space-x-1.5">
          {members.map((m) => (
            <Avatar
              key={m.id}
              className={`h-7 w-7 border-2 cursor-pointer transition-all ${
                activeAssignee === m.id
                  ? 'border-primary ring-2 ring-primary/30'
                  : 'border-card hover:border-primary/50'
              }`}
              onClick={() => onAssigneeFilter(activeAssignee === m.id ? null : m.id)}
              title={m.name}
            >
              <AvatarImage src={(m as any).avatar_url || ''} />
              <AvatarFallback
                style={{ backgroundColor: m.color || undefined }}
                className="text-primary-foreground text-[8px] font-medium"
              >
                {m.initials}
              </AvatarFallback>
            </Avatar>
          ))}
        </div>

        {/* Eye icon filter dropdown */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="sm" className="h-7 w-7 p-0">
              <Eye className="w-3.5 h-3.5" />
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
            <DropdownMenuItem onClick={() => setShowUserSettings(true)}>
              <User className="w-3.5 h-3.5 mr-2" /> User Settings
            </DropdownMenuItem>
            {isAdmin && (
              <DropdownMenuItem onClick={() => setShowAdminSettings(true)}>
                <Shield className="w-3.5 h-3.5 mr-2" /> Admin Settings
              </DropdownMenuItem>
            )}
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

      <UserSettingsModal open={showUserSettings} onOpenChange={setShowUserSettings} />
      {isAdmin && (
        <AdminSettingsModal open={showAdminSettings} onOpenChange={setShowAdminSettings} />
      )}
    </>
  );
}
