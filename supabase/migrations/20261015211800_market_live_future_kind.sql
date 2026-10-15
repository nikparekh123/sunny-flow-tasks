-- 15 Oct 2026 · handoff 24 (block 09): market-tape now writes ES=F, NQ=F, RTY=F with kind 'future'.
-- Applied by Claude via the Management API at 21:18 UTC; the check rejected the new kind for ~3 min.
alter table public.market_live drop constraint market_live_kind_check;
alter table public.market_live add constraint market_live_kind_check
  check (kind = any (array['index', 'vix', 'global', 'watch', 'future']));
