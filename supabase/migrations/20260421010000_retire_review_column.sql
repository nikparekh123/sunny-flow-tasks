-- Retire the Review column. Any Review tasks move back into In progress
-- so nothing becomes unreachable. The 'review' enum value stays in place
-- (Postgres removes are disruptive); the UI just never writes to it again.

update public.tasks
   set "column" = 'inprogress'
 where "column" = 'review';
