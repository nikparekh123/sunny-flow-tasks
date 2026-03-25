import { useState, useRef } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { toast } from 'sonner';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function UserSettingsModal({ open, onOpenChange }: Props) {
  const { user, member } = useAuth();
  const [name, setName] = useState(member?.name || '');
  const [emailNotifs, setEmailNotifs] = useState(
    (member as any)?.preferences?.email_notifications ?? true
  );
  const [saving, setSaving] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const [avatarUrl, setAvatarUrl] = useState((member as any)?.avatar_url || '');

  // Pincode change
  const [newPin, setNewPin] = useState('');
  const [confirmPin, setConfirmPin] = useState('');
  const [savingPin, setSavingPin] = useState(false);

  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !member) return;

    const ext = file.name.split('.').pop();
    const path = `${member.id}.${ext}`;

    const { error } = await supabase.storage
      .from('avatars')
      .upload(path, file, { upsert: true });

    if (error) {
      toast.error('Upload failed');
      return;
    }

    const { data: urlData } = supabase.storage.from('avatars').getPublicUrl(path);
    const url = urlData.publicUrl;
    setAvatarUrl(url);

    await supabase
      .from('team_members')
      .update({ avatar_url: url } as any)
      .eq('id', member.id);

    toast.success('Avatar updated');
  };

  const handleSave = async () => {
    if (!member) return;
    setSaving(true);

    const initials = name
      .split(' ')
      .filter(Boolean)
      .map((w) => w[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);

    const { error } = await supabase
      .from('team_members')
      .update({
        name,
        initials,
        preferences: { email_notifications: emailNotifs },
      } as any)
      .eq('id', member.id);

    setSaving(false);

    if (error) {
      toast.error('Failed to save');
    } else {
      toast.success('Settings saved');
      onOpenChange(false);
    }
  };

  const handlePincodeChange = async () => {
    if (!/^\d{4}$/.test(newPin)) {
      toast.error('Enter a valid 4-digit code.');
      return;
    }
    if (newPin !== confirmPin) {
      toast.error('Codes do not match.');
      return;
    }
    if (!member) return;
    setSavingPin(true);

    const { error } = await supabase
      .from('team_members')
      .update({ pincode: newPin } as any)
      .eq('id', member.id);

    setSavingPin(false);

    if (error) {
      toast.error('Failed to update code.');
    } else {
      toast.success('Login code updated.');
      setNewPin('');
      setConfirmPin('');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>User Settings</DialogTitle>
        </DialogHeader>

        <div className="space-y-5 py-2">
          {/* Avatar */}
          <div className="flex items-center gap-4">
            <Avatar className="h-14 w-14 cursor-pointer" onClick={() => fileRef.current?.click()}>
              <AvatarImage src={avatarUrl} />
              <AvatarFallback
                style={{ backgroundColor: member?.color || undefined }}
                className="text-primary-foreground text-sm font-medium"
              >
                {member?.initials}
              </AvatarFallback>
            </Avatar>
            <div>
              <Button variant="outline" size="sm" onClick={() => fileRef.current?.click()}>
                Upload Photo
              </Button>
              <input
                ref={fileRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={handleAvatarUpload}
              />
            </div>
          </div>

          {/* Name */}
          <div className="space-y-1.5">
            <Label htmlFor="name">Name</Label>
            <Input id="name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>

          {/* Email (read-only) */}
          <div className="space-y-1.5">
            <Label>Email</Label>
            <Input value={user?.email || ''} disabled />
          </div>

          {/* Status */}
          <div className="flex items-center justify-between">
            <Label>Status</Label>
            <span className="text-sm text-muted-foreground capitalize">
              {(member as any)?.status || 'active'}
            </span>
          </div>

          {/* Email notifications */}
          <div className="flex items-center justify-between">
            <Label>Email Notifications</Label>
            <Switch checked={emailNotifs} onCheckedChange={setEmailNotifs} />
          </div>

          <Button onClick={handleSave} disabled={saving} className="w-full">
            {saving ? 'Saving…' : 'Save Changes'}
          </Button>

          {/* Change pincode */}
          <div className="space-y-3 pt-3 border-t border-border">
            <p className="text-xs font-medium text-foreground">Change Login Code</p>
            <div className="grid grid-cols-2 gap-2">
              <div className="space-y-1">
                <Label className="text-[10px]">New code</Label>
                <Input
                  value={newPin}
                  onChange={(e) => setNewPin(e.target.value.replace(/\D/g, '').slice(0, 4))}
                  placeholder="4 digits"
                  maxLength={4}
                  className="text-xs"
                />
              </div>
              <div className="space-y-1">
                <Label className="text-[10px]">Confirm</Label>
                <Input
                  value={confirmPin}
                  onChange={(e) => setConfirmPin(e.target.value.replace(/\D/g, '').slice(0, 4))}
                  placeholder="4 digits"
                  maxLength={4}
                  className="text-xs"
                />
              </div>
            </div>
            <Button size="sm" variant="outline" onClick={handlePincodeChange} disabled={savingPin} className="text-xs">
              {savingPin ? 'Updating…' : 'Update Code'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
