-- Retire the Backlog column. Any tasks currently in Backlog get moved to Todo
-- (they stay on the board; users just won't see a Backlog column anymore).
-- The 'backlog' enum value is left in place because removing it requires
-- recreating the enum; it just becomes unreachable from the UI.

update public.tasks
   set "column" = 'todo'
 where "column" = 'backlog';
