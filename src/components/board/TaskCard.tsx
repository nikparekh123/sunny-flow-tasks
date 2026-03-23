import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { TaskCardContent } from './TaskCardContent';
import type { TaskWithDetail } from '@/lib/types';

interface Props {
  task: TaskWithDetail;
  isDone: boolean;
  onClick: () => void;
  onEdit: () => void;
  onDelete: () => void;
}

export function TaskCard({ task, isDone, onClick, onEdit, onDelete }: Props) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: task.id, data: { task } });

  const style: React.CSSProperties = {
    transform: CSS.Translate.toString(transform),
    transition: transition || 'transform 200ms cubic-bezier(0.25, 1, 0.5, 1)',
    willChange: isDragging ? 'transform' : undefined,
    zIndex: isDragging ? 1 : undefined,
    opacity: isDragging ? 0 : undefined,
    pointerEvents: isDragging ? 'none' : undefined,
  };

  return (
    <div
      ref={setNodeRef}
      {...attributes}
      {...listeners}
      style={style}
    >
      <TaskCardContent
        task={task}
        isDone={isDone}
        isDragging={isDragging}
        onClick={onClick}
        onEdit={onEdit}
        onDelete={onDelete}
      />
    </div>
  );
}
