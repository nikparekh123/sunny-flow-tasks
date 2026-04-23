import { useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function InviteUserModal({ open, onOpenChange }: Props) {
  const [name, setName] = useState('');
  const [pincode, setPincode] = useState('');
  const [saving, setSaving] = useState(false);

  const handleSubmit = async () => {
    if (!name.trim() || !/^\d{6}$/.test(pincode)) {
      toast.error('Enter a name and a valid 6-digit pincode.');
      return;
    }
    setSaving(true);

    const { data, error } = await supabase.functions.invoke('create-user', {
      body: { name: name.trim(), pincode },
    });

    setSaving(false);

    if (error || data?.error) {
      toast.error(data?.error || 'Failed to create user.');
      return;
    }

    toast.success(`${name.trim()} has been added with code ${pincode}`);
    setName('');
    setPincode('');
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Invite User</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-1.5">
            <Label htmlFor="invite-name" className="text-xs">Name</Label>
            <Input
              id="invite-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="text-xs"
              placeholder="Full name"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="invite-pin" className="text-xs">6-digit login code</Label>
            <Input
              id="invite-pin"
              value={pincode}
              onChange={(e) => setPincode(e.target.value.replace(/\D/g, '').slice(0, 4))}
              className="text-xs"
              placeholder="e.g. 1234"
              maxLength={6}
            />
          </div>
          <Button onClick={handleSubmit} disabled={saving} className="w-full text-xs">
            {saving ? 'Creating…' : 'Create User'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
