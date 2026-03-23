import { useState, useMemo } from 'react';
import {
  DndContext,
  DragOverlay,
  closestCorners,
  PointerSensor,
  useSensor,
  useSensors,
  type DragStartEvent,
  type DragEndEvent,
  type DragOverEvent,
} from '@dnd-kit/core';
import { arrayMove } from '@dnd-kit/sortable';
import { COLUMNS } from '@/lib/constants';
import { useTasks } from '@/hooks/useTasks';
import { useAuth } from '@/hooks/useAuth';
import { TopBar } from './TopBar';
import { BoardColumn } from './BoardColumn';
import { TaskDetailPanel } from './TaskDetailPanel';
import { TaskCard } from './TaskCard';
import type { TaskWithDetail, TaskColumn } from '@/lib/types';

export function KanbanBoard() {
  const { member } = useAuth();
  const {
    tasks, categories, members, isLoading,
    createTask, updateTask, deleteTask, moveTask,
    createCategory, updateCategory, deleteCategory,
  } = useTasks();

  const [activeCategory, setActiveCategory] = useState<string | null>(null);
  const [selectedTask, setSelectedTask] = useState<TaskWithDetail | null>(null);
  const [draggedTask, setDraggedTask] = useState<TaskWithDetail | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } })
  );

  const filteredTasks = useMemo(() => {
    if (!activeCategory) return tasks;
    return tasks.filter((t) => t.category_id === activeCategory);
  }, [tasks, activeCategory]);

  const tasksByColumn = useMemo(() => {
    const map: Record<TaskColumn, TaskWithDetail[]> = {
      todo: [], inprogress: [], review: [], done: [],
    };
    filteredTasks.forEach((t) => {
      if (map[t.column]) map[t.column].push(t);
    });
    // Sort by position within each column
    Object.values(map).forEach((arr) => arr.sort((a, b) => a.position - b.position));
    return map;
  }, [filteredTasks]);

  const handleDragStart = (event: DragStartEvent) => {
    const task = event.active.data.current?.task as TaskWithDetail;
    setDraggedTask(task || null);
  };

  const handleDragEnd = (event: DragEndEvent) => {
    setDraggedTask(null);
    const { active, over } = event;
    if (!over) return;

    const activeTask = active.data.current?.task as TaskWithDetail;
    if (!activeTask) return;

    // Determine target column
    let targetColumn: TaskColumn;
    let targetPosition: number;

    // Check if dropped over a column (droppable) or a task
    const overTask = over.data.current?.task as TaskWithDetail | undefined;
    if (overTask) {
      targetColumn = overTask.column;
      targetPosition = overTask.position;
    } else {
      // Dropped on column itself
      targetColumn = over.id as TaskColumn;
      targetPosition = tasksByColumn[targetColumn]?.length ?? 0;
    }

    if (activeTask.column === targetColumn && activeTask.position === targetPosition) return;

    moveTask.mutate({
      taskId: activeTask.id,
      column: targetColumn,
      position: targetPosition,
    });
  };

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <p className="text-sm text-muted-foreground">Loading board...</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <TopBar
        categories={categories}
        members={members}
        activeCategory={activeCategory}
        onCategoryFilter={setActiveCategory}
        onCreateCategory={(d) => createCategory.mutate(d)}
        onUpdateCategory={(d) => updateCategory.mutate(d)}
        onDeleteCategory={(id) => deleteCategory.mutate(id)}
        onCreateTask={(d) => createTask.mutate(d)}
        currentMemberId={member?.id ?? null}
      />

      <div className="flex-1 p-5 overflow-x-auto">
        <DndContext
          sensors={sensors}
          collisionDetection={closestCorners}
          onDragStart={handleDragStart}
          onDragEnd={handleDragEnd}
        >
          <div className="flex gap-4 min-w-max">
            {COLUMNS.map((col) => (
              <BoardColumn
                key={col.id}
                id={col.id}
                label={col.label}
                color={col.color}
                tasks={tasksByColumn[col.id]}
                onCardClick={(t) => setSelectedTask(t)}
                onCardEdit={(t) => setSelectedTask(t)}
                onCardDelete={(id) => deleteTask.mutate(id)}
                onQuickAdd={col.id === 'todo' ? (title) => createTask.mutate({
                  title,
                  created_by: member?.id ?? null,
                }) : undefined}
              />
            ))}
          </div>

          <DragOverlay>
            {draggedTask && (
              <div className="opacity-80">
                <TaskCard
                  task={draggedTask}
                  isDone={draggedTask.column === 'done'}
                  onClick={() => {}}
                  onEdit={() => {}}
                  onDelete={() => {}}
                />
              </div>
            )}
          </DragOverlay>
        </DndContext>
      </div>

      {selectedTask && (
        <TaskDetailPanel
          task={selectedTask}
          categories={categories}
          members={members}
          onClose={() => setSelectedTask(null)}
          onUpdate={(data) => {
            // If column changed via detail panel, use moveTask
            if ('column' in data && data.column !== selectedTask.column) {
              moveTask.mutate({
                taskId: data.id,
                column: data.column as TaskColumn,
                position: tasksByColumn[data.column as TaskColumn]?.length ?? 0,
              });
            } else {
              updateTask.mutate(data);
            }
            // Update local selected task reference
            const updated = { ...selectedTask, ...data };
            setSelectedTask(updated as TaskWithDetail);
          }}
        />
      )}
    </div>
  );
}
