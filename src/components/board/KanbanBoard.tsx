import { useState, useMemo, useCallback } from 'react';
import {
  DndContext,
  DragOverlay,
  closestCenter,
  pointerWithin,
  rectIntersection,
  PointerSensor,
  useSensor,
  useSensors,
  type DragStartEvent,
  type DragEndEvent,
  type DragOverEvent,
  type CollisionDetection,
} from '@dnd-kit/core';
import { arrayMove } from '@dnd-kit/sortable';
import { COLUMNS } from '@/lib/constants';
import { useTasks } from '@/hooks/useTasks';
import { useAuth } from '@/hooks/useAuth';
import { TopBar } from './TopBar';
import { BoardColumn } from './BoardColumn';
import { TaskDetailPanel } from './TaskDetailPanel';
import { TaskCardContent } from './TaskCardContent';
import type { TaskWithDetail, TaskColumn } from '@/lib/types';

// Custom collision detection: prefer droppable columns, fall back to closest center
const customCollision: CollisionDetection = (args) => {
  // First check if pointer is within a droppable
  const pointerCollisions = pointerWithin(args);
  if (pointerCollisions.length > 0) return pointerCollisions;

  // Fall back to rect intersection
  const rectCollisions = rectIntersection(args);
  if (rectCollisions.length > 0) return rectCollisions;

  return closestCenter(args);
};

export function KanbanBoard() {
  const { member } = useAuth();
  const {
    tasks, tags, members, isLoading,
    createTask, updateTask, deleteTask, moveTask, createTag,
  } = useTasks();

  const [activeAssignee, setActiveAssignee] = useState<string | null>(null);
  const [selectedTask, setSelectedTask] = useState<TaskWithDetail | null>(null);
  const [draggedTask, setDraggedTask] = useState<TaskWithDetail | null>(null);
  const [overColumn, setOverColumn] = useState<TaskColumn | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } })
  );

  const filteredTasks = useMemo(() => {
    if (!activeAssignee) return tasks;
    return tasks.filter((t) => t.assignee_id === activeAssignee);
  }, [tasks, activeAssignee]);

  const tasksByColumn = useMemo(() => {
    const map: Record<TaskColumn, TaskWithDetail[]> = {
      todo: [], inprogress: [], review: [], done: [],
    };
    filteredTasks.forEach((t) => {
      if (map[t.column]) map[t.column].push(t);
    });
    Object.values(map).forEach((arr) => arr.sort((a, b) => a.position - b.position));
    return map;
  }, [filteredTasks]);

  const handleDragStart = useCallback((event: DragStartEvent) => {
    const task = event.active.data.current?.task as TaskWithDetail;
    setDraggedTask(task || null);
  }, []);

  const handleDragOver = useCallback((event: DragOverEvent) => {
    const { over } = event;
    if (!over) {
      setOverColumn(null);
      return;
    }
    // Determine which column is being hovered
    const overTask = over.data.current?.task as TaskWithDetail | undefined;
    const col = overTask ? overTask.column : (over.id as TaskColumn);
    setOverColumn(col);
  }, []);

  const handleDragEnd = useCallback((event: DragEndEvent) => {
    setDraggedTask(null);
    setOverColumn(null);
    const { active, over } = event;
    if (!over) return;

    const activeTask = active.data.current?.task as TaskWithDetail;
    if (!activeTask) return;

    let targetColumn: TaskColumn;
    let targetPosition: number;

    const overTask = over.data.current?.task as TaskWithDetail | undefined;
    if (overTask) {
      targetColumn = overTask.column;
      // Place before the hovered task
      targetPosition = overTask.position;
    } else {
      // Dropped on column itself — append to end
      targetColumn = over.id as TaskColumn;
      targetPosition = tasksByColumn[targetColumn]?.length ?? 0;
    }

    if (activeTask.column === targetColumn && activeTask.position === targetPosition) return;

    moveTask.mutate({
      taskId: activeTask.id,
      column: targetColumn,
      position: targetPosition,
    });
  }, [tasksByColumn, moveTask]);

  const handleDragCancel = useCallback(() => {
    setDraggedTask(null);
    setOverColumn(null);
  }, []);

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-3">
          <div className="w-6 h-6 border-2 border-muted-foreground/30 border-t-foreground rounded-full animate-spin" />
          <p className="text-sm text-muted-foreground">Loading board…</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <TopBar
        tags={tags}
        members={members}
        activeAssignee={activeAssignee}
        onAssigneeFilter={setActiveAssignee}
        onCreateTask={(d) => createTask.mutate(d)}
        onCreateTag={(name) => createTag.mutate(name)}
        currentMemberId={member?.id ?? null}
      />

      <div className="flex-1 p-5 overflow-x-auto">
        <DndContext
          sensors={sensors}
          collisionDetection={customCollision}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDragEnd={handleDragEnd}
          onDragCancel={handleDragCancel}
        >
          <div className="flex gap-4 min-w-max">
            {COLUMNS.map((col) => (
              <BoardColumn
                key={col.id}
                id={col.id}
                label={col.label}
                color={col.color}
                tasks={tasksByColumn[col.id]}
                isOver={overColumn === col.id}
                onCardClick={(t) => setSelectedTask(t)}
                onCardEdit={(t) => setSelectedTask(t)}
                onCardDelete={(id) => deleteTask.mutate(id)}
              />
            ))}
          </div>

          <DragOverlay dropAnimation={{
            duration: 200,
            easing: 'cubic-bezier(0.18, 0.67, 0.6, 1.22)',
          }}>
            {draggedTask && (
              <TaskCardContent
                task={draggedTask}
                isDone={draggedTask.column === 'done'}
                isOverlay
                onClick={() => {}}
                onEdit={() => {}}
                onDelete={() => {}}
              />
            )}
          </DragOverlay>
        </DndContext>
      </div>

      {selectedTask && (
        <TaskDetailPanel
          task={selectedTask}
          tags={tags}
          members={members}
          onClose={() => setSelectedTask(null)}
          onUpdate={(data) => {
            if ('column' in data && data.column !== selectedTask.column) {
              moveTask.mutate({
                taskId: data.id,
                column: data.column as TaskColumn,
                position: tasksByColumn[data.column as TaskColumn]?.length ?? 0,
              });
            } else {
              updateTask.mutate(data);
            }
            const updated = { ...selectedTask, ...data };
            setSelectedTask(updated as TaskWithDetail);
          }}
          onCreateTag={(name) => createTag.mutate(name)}
        />
      )}
    </div>
  );
}
