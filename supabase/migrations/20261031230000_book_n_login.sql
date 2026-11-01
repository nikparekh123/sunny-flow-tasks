-- Book N's login (31 Oct 2026, step 2 of the cousin's book).
--
-- The auth user book-n@sunnyfi.co was made through the Auth admin API with a
-- long random password nobody knows (an auth user is not made in SQL). Nik
-- then sets the cousin's own 10-digit code with the SQL below, in the SQL
-- Editor, so the code never passes through chat. The app's sign-in screen
-- tries a code against nik@sunnyfi.co first and then against this login, so
-- the two codes must differ; the SQL refuses Nik's own code.
--
-- The login is a VIEWER of book N and nothing else: my_books() returns N
-- only, is_admin() is false, and every book-S reader refuses it.

insert into public.book_members (user_id, book_id, role)
select id, 'N', 'viewer' from auth.users where email = 'book-n@sunnyfi.co'
on conflict (user_id, book_id) do update set role = excluded.role;

-- Setting (or changing) the code. Put the 10 digits in place of the text.
--
-- do $$
-- declare
--   code text := 'PUT 10 DIGITS HERE';
--   mine text;
-- begin
--   if code !~ '^[0-9]{10}$' then raise exception 'The code must be exactly 10 digits.'; end if;
--   select encrypted_password into mine from auth.users where email = 'nik@sunnyfi.co';
--   if extensions.crypt(code, mine) = mine then raise exception 'That is your own code. Pick a different one.'; end if;
--   update auth.users set encrypted_password = extensions.crypt(code, extensions.gen_salt('bf', 10)), updated_at = now()
--    where email = 'book-n@sunnyfi.co';
--   if not found then raise exception 'The book N login is missing.'; end if;
-- end $$;
