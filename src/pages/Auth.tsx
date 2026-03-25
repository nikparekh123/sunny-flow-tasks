import { useState } from 'react';
import { InputOTP, InputOTPGroup, InputOTPSlot } from '@/components/ui/input-otp';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export default function Auth() {
  const [loading, setLoading] = useState(false);
  const [value, setValue] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = async (code: string) => {
    if (code.length !== 4) return;
    setLoading(true);
    setError('');

    try {
      const { data, error: fnError } = await supabase.functions.invoke('pincode-login', {
        body: { pincode: code },
      });

      if (fnError || data?.error) {
        setError(data?.error || 'Invalid code.');
        setValue('');
        setLoading(false);
        return;
      }

      if (data?.session) {
        await supabase.auth.setSession({
          access_token: data.session.access_token,
          refresh_token: data.session.refresh_token,
        });
      }
    } catch {
      setError('Something went wrong.');
      setValue('');
    }
    setLoading(false);
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-background">
      <div className="w-full max-w-xs space-y-6 px-4 text-center">
        <div className="space-y-1">
          <h1 className="text-xl font-medium tracking-tight text-foreground">SunnyFi</h1>
          <p className="text-sm text-muted-foreground">Enter your 4-digit code</p>
        </div>

        <div className="flex justify-center">
          <InputOTP
            maxLength={4}
            value={value}
            onChange={(v) => {
              setValue(v.replace(/\D/g, ''));
              setError('');
            }}
            onComplete={handleSubmit}
            disabled={loading}
          >
            <InputOTPGroup>
              <InputOTPSlot index={0} />
              <InputOTPSlot index={1} />
              <InputOTPSlot index={2} />
              <InputOTPSlot index={3} />
            </InputOTPGroup>
          </InputOTP>
        </div>

        {error && <p className="text-xs text-destructive">{error}</p>}
        {loading && <p className="text-xs text-muted-foreground">Signing in…</p>}
      </div>
    </div>
  );
}
