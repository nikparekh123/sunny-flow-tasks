-- Together (book T), Nik 24 Nov 2026: "the default view for me will always be Together", every account added up.
-- Book T owns no ledger rows; sunny-home builds it from every real book (BOOKS / partsOf in sunny-home/index.ts).
-- Its members are the people who own every real book (today nik@ and hello@), as owners.
insert into public.books (id, name, ibkr_accounts) values ('T', 'Together', '{}') on conflict (id) do nothing;
insert into public.book_members (user_id, book_id, role)
select s.user_id, 'T', 'owner'
from public.book_members s
join public.book_members n on n.user_id = s.user_id and n.book_id = 'N' and n.role = 'owner'
where s.book_id = 'S' and s.role = 'owner'
on conflict do nothing;

-- Together's crons: Home every minute (as sunny-home and sunny-home-N), its account history after the other books'.
select cron.schedule('sunny-home-T', '* * * * *', $$SELECT public.cron_invoke_function_body('sunny-home', '{"book":"T"}'::jsonb)$$);
select cron.schedule('account-history-daily-T', '50 10,13 * * *', $$SELECT public.cron_invoke_function_body('sunny-home', '{"mode":"history","book":"T"}'::jsonb, 120000)$$);
