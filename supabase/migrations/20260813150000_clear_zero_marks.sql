-- A mark of 0 is the absence of a price, not a price. Clear the zeros so the
-- feed rewrites them with a real quote, and stop them polluting the closes.
update public.nvda_option_marks set mark = null where mark is not null and mark <= 0;
update public.tlt_option_marks  set mark = null where mark is not null and mark <= 0;
delete from public.nvda_option_marks_eod where mark is not null and mark <= 0;
delete from public.tlt_option_marks_eod  where mark is not null and mark <= 0;

select 'nvda_option_marks'      t, count(*) filter (where mark is null) as null_marks, count(*) as rows from public.nvda_option_marks
union all select 'tlt_option_marks',  count(*) filter (where mark is null), count(*) from public.tlt_option_marks
union all select 'nvda_marks_eod',    count(*) filter (where mark is null), count(*) from public.nvda_option_marks_eod
union all select 'tlt_marks_eod',     count(*) filter (where mark is null), count(*) from public.tlt_option_marks_eod;
