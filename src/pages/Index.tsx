import { useState } from 'react';
import Auth from './Auth';
import { KanbanBoard } from '@/components/board/KanbanBoard';

export default function Index() {
  const [entered, setEntered] = useState(false);

  if (!entered) return <Auth onBypass={() => setEntered(true)} />;

  return <KanbanBoard />;
}
