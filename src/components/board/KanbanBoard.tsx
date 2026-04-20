import { useState, useMemo, useCallback, useRef } from 'react';
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
import { useTasks } from '@/hooks/useTasks';
import { useAuth } from '@/hooks/useAuth';
import { useSubtasks } from '@/hooks/useSubtasks';
import { TopBar, type ViewMode } from './TopBar';
import { Sidebar } from './Sidebar';
import { PriorityGrid } from './PriorityGrid';
import { TaskDetailPanel } from './TaskDetailPanel';
import { TaskCardContent } from './TaskCardContent';
import { ArchivePanel } from './ArchivePanel';
import { CalendarView } from './CalendarView';
import { GanttView } from './GanttView';
import { TagManagementModal } from '@/components/settings/TagManagementModal';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { toast } from 'sonner';
import type { TaskWithDetail, TaskColumn, TaskPriority } from '@/lib/types';

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
    createTask, updateTask, archiveTask, restoreTask, permanentlyDeleteTask, moveTask, createTag,
    updateTag, deleteTag,
  } = useTasks();
  const { completeAllSubtasks } = useSubtasks();

  const [activeAssignee, setActiveAssignee] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [activeTagIds, setActiveTagIds] = useState<string[]>([]);
  const [priorityFilter, setPriorityFilter] = useState<'high' | null>(null);
  const [selectedTask, setSelectedTask] = useState<TaskWithDetail | null>(null);
  const [draggedTask, setDraggedTask] = useState<TaskWithDetail | null>(null);
  const [overCellId, setOverCellId] = useState<string | null>(null);
  const [showArchive, setShowArchive] = useState(false);
  const [activeView, setActiveView] = useState<ViewMode>('board');
  const [showTagManagement, setShowTagManagement] = useState(false);
  const [pendingDragMove, setPendingDragMove] = useState<{ taskId: string; column: TaskColumn; position: number; task: TaskWithDetail } | null>(null);

  const undoTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } })
  );

  const filteredTasks = useMemo(() => {
    let result = tasks;
    if (activeAssignee) {
      result = result.filter((t) =>
        t.assignee_ids?.includes(activeAssignee) || t.assignee_id === activeAssignee
      );
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      result = result.filter((t) =>
        t.title.toLowerCase().includes(q) ||
        (t.description && t.description.toLowerCase().includes(q)) ||
        (t.brief && t.brief.toLowerCase().includes(q)) ||
        (t.tags && t.tags.some((tag) => tag.name.toLowerCase().includes(q))) ||
        (t.assignee_name && t.assignee_name.toLowerCase().includes(q)) ||
        (t.assignees && t.assignees.some((a) => a.name.toLowerCase().includes(q))) ||
        (t.category_name && t.category_name.toLowerCase().includes(q))
      );
    }
    if (activeTagIds.length > 0) {
      result = result.filter((t) =>
        activeTagIds.every((tagId) => t.tags?.some((tag) => tag.id === tagId))
      );
    }
    if (priorityFilter) {
      result = result.filter((t) => t.priority === priorityFilter);
    }
    return result;
  }, [tasks, activeAssignee, searchQuery, activeTagIds, priorityFilter]);

  const allTasksByColumn = useMemo(() => {
    const map: Record<TaskColumn, TaskWithDetail[]> = { backlog: [], todo: [], inprogress: [], review: [], done: [] };
    tasks.forEach((task) => map[task.column].push(task));
    Object.values(map).forEach((list) => list.sort((a, b) => a.position - b.position));
    return map;
  }, [tasks]);

  const handleDelete = useCallback((taskId: string) => {
    archiveTask.mutate(taskId);
    if (undoTimerRef.current) clearTimeout(undoTimerRef.current);
    toast('Task deleted', {
      action: {
        label: 'Undo',
        onClick: () => { restoreTask.mutate(taskId); },
      },
      duration: 30000,
      position: 'bottom-left',
    });
  }, [archiveTask, restoreTask]);

  const handleNavigateToTask = useCallback((taskId: string) => {
    const task = tasks.find((t) => t.id === taskId);
    if (task) setSelectedTask(task);
  }, [tasks]);

  const handleDragStart = useCallback((event: DragStartEvent) => {
    setDraggedTask((event.active.data.current?.task as TaskWithDetail) || null);
  }, []);

  const handleDragOver = useCallback((event: DragOverEvent) => {
    const overData = event.over?.data.current as { task?: TaskWithDetail; column?: TaskColumn; priority?: TaskPriority } | undefined;
    const overTask = overData?.task;
    const overId = event.over?.id as string | undefined;
    if (overTask) {
      setOverCellId(`${overTask.priority}:${overTask.column}`);
    } else if (overData?.column) {
      setOverCellId(overId ?? null);
    } else {
      setOverCellId(null);
    }
  }, []);

  const handleDragEnd = useCallback((event: DragEndEvent) => {
    setDraggedTask(null);
    setOverCellId(null);
    const activeTask = event.active.data.current?.task as TaskWithDetail;
    if (!activeTask || !event.over) return;
    const overData = event.over.data.current as { task?: TaskWithDetail; column?: TaskColumn; priority?: TaskPriority } | undefined;
    const overTask = overData?.task;

    let targetColumn: TaskColumn;
    let targetPriority: TaskPriority | undefined;
    if (overTask) {
      targetColumn = overTask.column;
      targetPriority = overTask.priority;
    } else if (overData?.column) {
      targetColumn = overData.column;
      targetPriority = overData.priority;
    } else {
      targetColumn = event.over.id as TaskColumn;
    }

    const targetColumnTasks = allTasksByColumn[targetColumn] ?? [];
    const sourceColumnTasks = allTasksByColumn[activeTask.column] ?? [];
    let targetPosition = targetColumnTasks.length;
    if (overTask) {
      const overIndex = targetColumnTasks.findIndex((t) => t.id === overTask.id);
      targetPosition = overIndex < 0 ? targetColumnTasks.length : overIndex;
    }
    const currentIndex = sourceColumnTasks.findIndex((t) => t.id === activeTask.id);
    if (currentIndex < 0) return;
    const priorityChanged = targetPriority && targetPriority !== activeTask.priority;
    if (
      !priorityChanged &&
      activeTask.column === targetColumn &&
      currentIndex === targetPosition
    )
      return;

    // Check for incomplete subtasks when moving to done
    const incompleteSubtasks = (activeTask.subtasks || []).filter(s => !s.done).length;
    if (targetColumn === 'done' && activeTask.column !== 'done' && incompleteSubtasks > 0) {
      setPendingDragMove({ taskId: activeTask.id, column: targetColumn, position: targetPosition, task: activeTask });
      return;
    }

    moveTask.mutate({
      taskId: activeTask.id,
      column: targetColumn,
      position: targetPosition,
      priority: priorityChanged ? targetPriority : undefined,
    });
  }, [allTasksByColumn, moveTask]);

  const handleDragCancel = useCallback(() => {
    setDraggedTask(null);
    setOverCellId(null);
  }, []);

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center" style={{ backgroundColor: 'var(--owl-page)' }}>
        <div className="flex flex-col items-center gap-3">
          <div className="h-6 w-6 rounded-full border-2 animate-spin" style={{ borderColor: 'var(--owl-dusk)', borderTopColor: 'var(--owl-neon)' }} />
          <p className="text-sm" style={{ color: 'var(--owl-text-secondary)' }}>Loading board…</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex" style={{ backgroundColor: 'var(--owl-page)' }}>
      <Sidebar
        tasks={tasks}
        members={members}
        currentMemberId={member?.id ?? null}
        activeAssignee={activeAssignee}
        onAssigneeFilter={setActiveAssignee}
        onFilterPriority={setPriorityFilter}
        activePriorityFilter={priorityFilter}
        onOpenArchive={() => setShowArchive(true)}
        showingArchive={showArchive}
      />
      <div className="flex-1 flex flex-col min-w-0">
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
        activeTagIds={activeTagIds}
        onTagFilter={setActiveTagIds}
        onOpenArchive={() => setShowArchive(true)}
        activeView={activeView}
        onViewChange={setActiveView}
        onNavigateToTask={handleNavigateToTask}
      />

      {activeView === 'board' && (
        <div className="flex-1 px-3 pb-4 md:px-5 overflow-x-auto" style={{ backgroundColor: 'var(--owl-page)' }}>
          <DndContext
            sensors={sensors}
            collisionDetection={customCollision}
            onDragStart={handleDragStart}
            onDragOver={handleDragOver}
            onDragEnd={handleDragEnd}
            onDragCancel={handleDragCancel}
          >
            <div className="pt-4 w-full">
              <PriorityGrid
                tasks={filteredTasks}
                overCellId={overCellId}
                onCardClick={(task) => setSelectedTask(task)}
                onCardEdit={(task) => setSelectedTask(task)}
                onCardDelete={handleDelete}
              />
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
      )}

      {activeView === 'gantt' && (
        <GanttView
          tasks={filteredTasks}
          members={members}
          onTaskClick={(task) => setSelectedTask(task)}
        />
      )}

      {activeView === 'calendar' && (
        <CalendarView
          tasks={filteredTasks}
          onTaskClick={(task) => setSelectedTask(task)}
        />
      )}

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
          onDelete={handleDelete}
          onCreateTag={(name) => createTag.mutate(name)}
        />
      )}

      <ArchivePanel
        open={showArchive}
        onClose={() => setShowArchive(false)}
        onRestore={(id) => restoreTask.mutate(id)}
        onPermanentDelete={(id) => permanentlyDeleteTask.mutate(id)}
      />

      <TagManagementModal
        open={showTagManagement}
        onOpenChange={setShowTagManagement}
        tags={tags}
        onUpdateTag={(id, updates) => updateTag.mutate({ id, ...updates })}
        onDeleteTag={(id) => deleteTag.mutate(id)}
      />

      {/* Subtask completion confirmation on drag-to-done */}
      <AlertDialog open={!!pendingDragMove} onOpenChange={(open) => { if (!open) setPendingDragMove(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Incomplete subtasks</AlertDialogTitle>
            <AlertDialogDescription>
              This task has {pendingDragMove ? (pendingDragMove.task.subtasks || []).filter(s => !s.done).length : 0} incomplete subtask(s). Mark them all as complete too?
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => {
              if (pendingDragMove) {
                moveTask.mutate({ taskId: pendingDragMove.taskId, column: pendingDragMove.column, position: pendingDragMove.position });
              }
              setPendingDragMove(null);
            }}>No</AlertDialogCancel>
            <AlertDialogAction onClick={() => {
              if (pendingDragMove) {
                completeAllSubtasks.mutate(pendingDragMove.taskId);
                moveTask.mutate({ taskId: pendingDragMove.taskId, column: pendingDragMove.column, position: pendingDragMove.position });
              }
              setPendingDragMove(null);
            }}>Yes</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      </div>
    </div>
  );
}
