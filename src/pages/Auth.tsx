import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export default function Auth() {
  const [loading, setLoading] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');

  const handleSignIn = async () => {
    if (!email || !password) return;
    setLoading(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) toast.error(error.message);
    setLoading(false);
  };

  const handleSignUp = async () => {
    if (!email || !password || !firstName) return;
    setLoading(true);
    const fullName = `${firstName.trim()} ${lastName.trim()}`.trim();
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName },
        emailRedirectTo: window.location.origin,
      },
    });
    if (error) {
      toast.error(error.message);
    } else {
      toast.success('Check your email for a confirmation link');
    }
    setLoading(false);
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-background">
      <div className="w-full max-w-sm space-y-6 px-4">
        <div className="text-center space-y-1">
          <h1 className="text-xl font-medium tracking-tight">SunnyFi</h1>
          <p className="text-sm text-muted-foreground">Sign in to your account</p>
        </div>

        <Tabs defaultValue="signin" className="w-full">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="signin" className="text-xs">Sign In</TabsTrigger>
            <TabsTrigger value="signup" className="text-xs">Sign Up</TabsTrigger>
          </TabsList>

          <TabsContent value="signin" className="space-y-3 pt-2">
            <div className="space-y-1">
              <Label className="text-xs">Email</Label>
              <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} className="text-xs" />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Password</Label>
              <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} className="text-xs" />
            </div>
            <Button className="w-full text-xs" onClick={handleSignIn} disabled={loading}>
              {loading ? 'Signing in…' : 'Sign In'}
            </Button>
          </TabsContent>

          <TabsContent value="signup" className="space-y-3 pt-2">
            <div className="grid grid-cols-2 gap-2">
              <div className="space-y-1">
                <Label className="text-xs">First name</Label>
                <Input value={firstName} onChange={(e) => setFirstName(e.target.value)} className="text-xs" />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Last name</Label>
                <Input value={lastName} onChange={(e) => setLastName(e.target.value)} className="text-xs" />
              </div>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Email</Label>
              <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} className="text-xs" />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Password</Label>
              <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} className="text-xs" />
            </div>
            <Button className="w-full text-xs" onClick={handleSignUp} disabled={loading}>
              {loading ? 'Creating account…' : 'Sign Up'}
            </Button>
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
}
