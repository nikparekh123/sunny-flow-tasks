-- 2026-10-08 cleanup. ALREADY APPLIED via the Management API; this file is the record.
-- Nothing was dropped: dead objects were MOVED to the `archive` schema so any one can be
-- restored with `alter table archive.<name> set schema public` (or alter view / function).
-- archive.retired_objects lists every moved object with drop_after = 2026-11-07.
-- archive.retired_cron holds the schedule + command of the 19 unscheduled cron jobs.
--
-- Crons unscheduled: planner-ingest-30min, refresh-put-quotes-hourly, nvda-mirror-3min, nvda-eod,
--   nvda-accumulate-daily, nvda-iv-30min, nvda-marks-60s, planner-score-nightly, ticker-stats-daily,
--   grade-open-quarter-daily, daily-theta-snapshot, position-snapshot, tlt-eod, tlt-mirror-3min,
--   tlt-planner-daily, sunny-rail-delta-snapshot, income-scanner-open, income-scanner-close,
--   positions-daily-refresh (failed daily: null url; refresh-prices-hourly covers it).
-- Tables moved (60): nvda_* (11), planner_* (6), tlt_* (14), income_card_seen, income_week_seen,
--   income_scanner_results, scanner_closes, scanner_option_history, income_sleeve_settings,
--   daily_theta_snapshot, position_history, delta_history, rates_daily, earnings_reactions,
--   macro_events, ticker_stats, share_lot_consumptions, position_reconciliation,
--   tasks, subtasks, tags, task_tags, task_assignees, task_categories, automation_rules,
--   notifications, reports, snowball, snowball_sector_defaults, watching, math_snapshots, member_pincodes.
-- Views moved: option_iv_daily_change, ticker_iv_summary, scanner_persistence, tasks_with_detail, tag_stats.
-- Functions moved: nvda_mirror, nvda_eod, tlt_mirror, tlt_eod, grade_open_quarter, nvda_fiscal_quarter,
--   ibkr_alerts_recent, reorder_task, related_tags, is_member, ensure_tags_exist, current_member_id,
--   update_updated_at, snowball_* (18).

create schema if not exists archive;
revoke all on schema archive from anon, authenticated;
create table if not exists archive.retired_cron (jobname text primary key, schedule text, command text, retired_at timestamptz default now());
create table if not exists archive.retired_objects (name text primary key, kind text, archived_at timestamptz default now(), drop_after date default (current_date + 30));

-- To finish the job after 2026-11-07 (run in the SQL Editor once nothing has broken):
--   drop schema archive cascade;
