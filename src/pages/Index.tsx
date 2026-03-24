import { useAuth } from '@/hooks/useAuth';
import { useLocation } from 'react-router-dom';
import Auth from './Auth';
import Dashboard from './Dashboard';
import { KanbanBoard } from '@/components/board/KanbanBoard';
import { SidebarProvider, SidebarTrigger } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/layout/AppSidebar';

export default function Index() {
  const { user, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <p className="text-sm text-muted-foreground">Loading…</p>
      </div>
    );
  }

  if (!user) return <Auth />;

  const isBoard = location.pathname === '/board';

  return (
    <SidebarProvider>
      <div className="min-h-screen flex w-full">
        <AppSidebar />
        <div className="flex-1 flex flex-col min-w-0">
          <header className="h-10 flex items-center border-b border-border bg-card px-2">
            <SidebarTrigger />
          </header>
          {isBoard ? <KanbanBoard /> : <Dashboard />}
        </div>
      </div>
    </SidebarProvider>
  );
}
