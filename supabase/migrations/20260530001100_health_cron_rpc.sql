/* ============================================================
   get_cron_status() — RPC for the /health page.

   Exposes pg_cron's `cron.job` + the latest row from
   `cron.job_run_details` per job, so the page can show:
     - which mp-refresh-related jobs are scheduled
     - their schedule + active flag
     - when they last fired and whether it succeeded

   `cron.*` is restricted to superusers — the RPC runs as
   `security definer` so authenticated users can read it without
   granting direct table access. We only expose jobs whose name
   starts with `mp-` to scope the surface.

   Optional: the /health page falls back to a friendly "no cron data"
   message if this RPC isn't installed.
   ============================================================ */

create or replace function public.get_cron_status()
returns table (
  jobid       bigint,
  jobname     text,
  schedule    text,
  active      boolean,
  last_run    timestamptz,
  last_status text
)
language sql
security definer
set search_path = public, cron
as $$
  select
    j.jobid,
    j.jobname,
    j.schedule,
    j.active,
    d.last_run,
    d.last_status
  from cron.job j
  left join lateral (
    select start_time as last_run, status as last_status
    from cron.job_run_details
    where jobid = j.jobid
    order by start_time desc
    limit 1
  ) d on true
  where j.jobname like 'mp-%';
$$;

grant execute on function public.get_cron_status() to authenticated;
