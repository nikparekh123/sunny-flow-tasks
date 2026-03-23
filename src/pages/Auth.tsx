import { Button } from '@/components/ui/button';

export default function Auth({ onBypass }: { onBypass: () => void }) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background">
      <div className="w-full max-w-sm space-y-6 px-4">
        <div className="text-center space-y-1">
          <h1 className="text-xl font-medium tracking-tight">SunnyFi</h1>
          <p className="text-sm text-muted-foreground">Sign in to your account</p>
        </div>
        <Button className="w-full text-xs" onClick={onBypass}>
          Sign in
        </Button>
      </div>
    </div>
  );
}