import { useAuth } from '@/hooks/useAuth';
import Auth from './Auth';
import { KanbanBoard } from '@/components/board/KanbanBoard';

export default function Index() {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <p className="text-sm text-muted-foreground">Loading…</p>
      </div>
    );
  }

  if (!user) return <Auth />;

  return <KanbanBoard />;
}
