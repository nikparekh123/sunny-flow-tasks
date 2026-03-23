import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

export default function Auth() {
  const [loading, setLoading] = useState(false);

  const handleDummySignIn = async () => {
    setLoading(true);
    try {
      const { error } = await supabase.auth.signInAnonymously();
      if (error) throw error;
    } catch (err: any) {
      toast.error(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-background">
      <div className="w-full max-w-sm space-y-6 px-4">
        <div className="text-center space-y-1">
          <h1 className="text-xl font-medium tracking-tight">SunnyFi</h1>
          <p className="text-sm text-muted-foreground">Sign in to your account</p>
        </div>
        <Button className="w-full text-xs" onClick={handleDummySignIn} disabled={loading}>
          {loading ? 'Signing in...' : 'Sign in'}
        </Button>
      </div>
    </div>
  );
}
