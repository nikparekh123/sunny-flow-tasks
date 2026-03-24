import { useState, useMemo, useCallback } from 'react';
import {
  DndContext,
  DragOverlay,
  pointerWithin,
  rectIntersection,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
  type DragStartEvent,
  type DragEndEvent,
  type DragOverEvent,
  type CollisionDetection,
} from '@dnd-kit/core';
import { COLUMNS } from '@/lib/constants';
import { useTasks } from '@/hooks/useTasks';
import { useAuth } from '@/hooks/useAuth';
import { TopBar } from './TopBar';
import { BoardColumn } from './BoardColumn';
import { TaskDetailPanel } from './TaskDetailPanel';
import { TaskCardContent } from './TaskCardContent';
import type { TaskWithDetail, TaskColumn } from '@/lib/types';

const customCollision: CollisionDetection = (args) => {
  const pointerCollisions = pointerWithin(args);
  if (pointerCollisions.length > 0) return pointerCollisions;
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
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedTask, setSelectedTask] = useState<TaskWithDetail | null>(null);
  const [draggedTask, setDraggedTask] = useState<TaskWithDetail | null>(null);
  const [overColumn, setOverColumn] = useState<TaskColumn | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } })
  );

  const filteredTasks = useMemo(() => {
    let result = tasks;
    if (activeAssignee) result = result.filter((t) => t.assignee_id === activeAssignee);
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      result = result.filter((t) =>
        t.title.toLowerCase().includes(q) ||
        (t.description && t.description.toLowerCase().includes(q)) ||
        (t.tags && t.tags.some((tag) => tag.name.toLowerCase().includes(q))) ||
        (t.assignee_name && t.assignee_name.toLowerCase().includes(q)) ||
        (t.category_name && t.category_name.toLowerCase().includes(q))
      );
    }
    return result;
  }, [tasks, activeAssignee, searchQuery]);

  const allTasksByColumn = useMemo(() => {
    const map: Record<TaskColumn, TaskWithDetail[]> = { todo: [], inprogress: [], review: [], done: [] };
    tasks.forEach((task) => map[task.column].push(task));
    Object.values(map).forEach((list) => list.sort((a, b) => a.position - b.position));
    return map;
  }, [tasks]);

  const visibleTasksByColumn = useMemo(() => {
    const map: Record<TaskColumn, TaskWithDetail[]> = { todo: [], inprogress: [], review: [], done: [] };
    filteredTasks.forEach((task) => map[task.column].push(task));
    Object.values(map).forEach((list) => list.sort((a, b) => a.position - b.position));
    return map;
  }, [filteredTasks]);

  const handleDragStart = useCallback((event: DragStartEvent) => {
    setDraggedTask((event.active.data.current?.task as TaskWithDetail) || null);
  }, []);

  const handleDragOver = useCallback((event: DragOverEvent) => {
    const overTask = event.over?.data.current?.task as TaskWithDetail | undefined;
    setOverColumn(overTask ? overTask.column : (event.over?.id as TaskColumn | undefined) ?? null);
  }, []);

  const handleDragEnd = useCallback((event: DragEndEvent) => {
    setDraggedTask(null);
    setOverColumn(null);
    const activeTask = event.active.data.current?.task as TaskWithDetail;
    if (!activeTask || !event.over) return;
    const overTask = event.over.data.current?.task as TaskWithDetail | undefined;
    const targetColumn = overTask ? overTask.column : (event.over.id as TaskColumn);
    const targetColumnTasks = allTasksByColumn[targetColumn] ?? [];
    const sourceColumnTasks = allTasksByColumn[activeTask.column] ?? [];
    let targetPosition = targetColumnTasks.length;
    if (overTask) {
      const overIndex = targetColumnTasks.findIndex((t) => t.id === overTask.id);
      targetPosition = overIndex < 0 ? targetColumnTasks.length : overIndex;
    }
    const currentIndex = sourceColumnTasks.findIndex((t) => t.id === activeTask.id);
    if (currentIndex < 0) return;
    if (activeTask.column === targetColumn && currentIndex === targetPosition) return;
    moveTask.mutate({ taskId: activeTask.id, column: targetColumn, position: targetPosition });
  }, [allTasksByColumn, moveTask]);

  const handleDragCancel = useCallback(() => {
    setDraggedTask(null);
    setOverColumn(null);
  }, []);

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-3">
          <div className="h-6 w-6 rounded-full border-2 border-ring/20 border-t-ring animate-spin" />
          <p className="text-sm text-muted-foreground">Loading board…</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 bg-background flex flex-col">
      <TopBar
        tags={tags}
        members={members}
        activeAssignee={activeAssignee}
        onAssigneeFilter={setActiveAssignee}
        onCreateTask={(data) => createTask.mutateAsync(data)}
        onCreateTag={(name) => createTag.mutate(name)}
        currentMemberId={member?.id ?? null}
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
      />

      <div className="flex-1 px-3 pb-4 md:px-5 overflow-x-auto">
        <DndContext
          sensors={sensors}
          collisionDetection={customCollision}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDragEnd={handleDragEnd}
          onDragCancel={handleDragCancel}
        >
          <div className="grid grid-cols-4 gap-4 min-w-[980px] w-full pt-4 items-start">
            {COLUMNS.map((column) => (
              <BoardColumn
                key={column.id}
                id={column.id}
                label={column.label}
                color={column.color}
                tasks={visibleTasksByColumn[column.id]}
                isOver={overColumn === column.id}
                onCardClick={(task) => setSelectedTask(task)}
                onCardEdit={(task) => setSelectedTask(task)}
                onCardDelete={(taskId) => deleteTask.mutate(taskId)}
              />
            ))}
          </div>

          <DragOverlay dropAnimation={null}>
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
                position: allTasksByColumn[data.column as TaskColumn]?.length ?? 0,
              });
            } else {
              updateTask.mutate(data);
            }
            setSelectedTask({ ...selectedTask, ...data } as TaskWithDetail);
          }}
          onCreateTag={(name) => createTag.mutate(name)}
        />
      )}
    </div>
  );
}
