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
} from '@dnd-kit/core';
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
    tasks, tags, members, isLoading,
    createTask, updateTask, deleteTask, moveTask, createTag,
  } = useTasks();

  const [activeAssignee, setActiveAssignee] = useState<string | null>(null);
  const [selectedTask, setSelectedTask] = useState<TaskWithDetail | null>(null);
  const [draggedTask, setDraggedTask] = useState<TaskWithDetail | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } })
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

    let targetColumn: TaskColumn;
    let targetPosition: number;

    const overTask = over.data.current?.task as TaskWithDetail | undefined;
    if (overTask) {
      targetColumn = overTask.column;
      targetPosition = overTask.position;
    } else {
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
