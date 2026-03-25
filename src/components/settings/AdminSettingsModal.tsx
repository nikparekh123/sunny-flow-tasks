import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { toast } from 'sonner';
import type { TeamMember } from '@/lib/types';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function AdminSettingsModal({ open, onOpenChange }: Props) {
  const [members, setMembers] = useState<(TeamMember & { status?: string; avatar_url?: string })[]>([]);
  const [loading, setLoading] = useState(true);

  // Create user form
  const [newName, setNewName] = useState('');
  const [newPincode, setNewPincode] = useState('');
  const [creating, setCreating] = useState(false);

  const fetchMembers = async () => {
    setLoading(true);
    const { data } = await supabase.from('team_members').select('*').order('name');
    setMembers((data as any) ?? []);
    setLoading(false);
  };

  useEffect(() => {
    if (open) fetchMembers();
  }, [open]);

  const handleRoleChange = async (memberId: string, newRole: 'admin' | 'member') => {
    const { error } = await supabase
      .from('team_members')
      .update({ role: newRole } as any)
      .eq('id', memberId);

    if (error) {
      toast.error('Failed to update role');
    } else {
      toast.success('Role updated');
      setMembers((prev) =>
        prev.map((m) => (m.id === memberId ? { ...m, role: newRole } : m))
      );
    }
  };

  const handleStatusToggle = async (memberId: string, currentStatus: string) => {
    const newStatus = currentStatus === 'active' ? 'inactive' : 'active';
    const { error } = await supabase
      .from('team_members')
      .update({ status: newStatus } as any)
      .eq('id', memberId);

    if (error) {
      toast.error('Failed to update status');
    } else {
      toast.success(`User ${newStatus}`);
      setMembers((prev) =>
        prev.map((m) => (m.id === memberId ? { ...m, status: newStatus } : m))
      );
    }
  };

  const handleCreateUser = async () => {
    if (!newName.trim() || !/^\d{4}$/.test(newPincode)) {
      toast.error('Enter a name and a valid 4-digit pincode.');
      return;
    }
    setCreating(true);

    const { data, error } = await supabase.functions.invoke('create-user', {
      body: { name: newName.trim(), pincode: newPincode },
    });

    setCreating(false);

    if (error || data?.error) {
      toast.error(data?.error || 'Failed to create user.');
      return;
    }

    toast.success(`${newName.trim()} added`);
    setNewName('');
    setNewPincode('');
    fetchMembers();
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Admin Settings — User Management</DialogTitle>
        </DialogHeader>

        {/* Create user section */}
        <div className="space-y-3 p-3 rounded-lg border border-border bg-secondary/30">
          <p className="text-xs font-medium">Add New User</p>
          <div className="grid grid-cols-2 gap-2">
            <div className="space-y-1">
              <Label className="text-[10px]">Name</Label>
              <Input
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                className="text-xs h-8"
                placeholder="Full name"
              />
            </div>
            <div className="space-y-1">
              <Label className="text-[10px]">4-digit code</Label>
              <Input
                value={newPincode}
                onChange={(e) => setNewPincode(e.target.value.replace(/\D/g, '').slice(0, 4))}
                className="text-xs h-8"
                placeholder="e.g. 1234"
                maxLength={4}
              />
            </div>
          </div>
          <Button size="sm" className="text-xs" onClick={handleCreateUser} disabled={creating}>
            {creating ? 'Creating…' : 'Add User'}
          </Button>
        </div>

        {loading ? (
          <p className="text-sm text-muted-foreground py-4">Loading…</p>
        ) : (
          <div className="space-y-3 py-2 max-h-[400px] overflow-y-auto">
            {members.map((m) => (
              <div
                key={m.id}
                className="flex items-center gap-3 p-3 rounded-lg border border-border"
              >
                <Avatar className="h-9 w-9">
                  <AvatarImage src={(m as any).avatar_url || ''} />
                  <AvatarFallback
                    style={{ backgroundColor: m.color || undefined }}
                    className="text-primary-foreground text-[10px] font-medium"
                  >
                    {m.initials}
                  </AvatarFallback>
                </Avatar>

                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">{m.name}</p>
                  <Badge
                    variant="outline"
                    className={`text-[10px] ${
                      (m as any).status === 'inactive'
                        ? 'text-destructive border-destructive/30'
                        : 'text-green-600 border-green-300'
                    }`}
                  >
                    {(m as any).status || 'active'}
                  </Badge>
                </div>

                <Select
                  value={m.role}
                  onValueChange={(v) => handleRoleChange(m.id, v as 'admin' | 'member')}
                >
                  <SelectTrigger className="w-[100px] h-8 text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="admin">Admin</SelectItem>
                    <SelectItem value="member">Member</SelectItem>
                  </SelectContent>
                </Select>

                <Button
                  variant="outline"
                  size="sm"
                  className="h-8 text-xs"
                  onClick={() =>
                    handleStatusToggle(m.id, (m as any).status || 'active')
                  }
                >
                  {(m as any).status === 'inactive' ? 'Activate' : 'Deactivate'}
                </Button>
              </div>
            ))}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
