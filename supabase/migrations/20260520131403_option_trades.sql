-- Single options trade ledger.
--
-- Replaces the gain_entries / expenses / put_protection trio with one table
-- representing the open ↔ close lifecycle of each options trade.
--
-- A "live position" = an open row where Σ(matching closes.contracts) < open.contracts.
-- Realized P&L on each close row = signed (premium delta × contracts × 100).
--
-- Direction stores which side of the trade you took at OPEN:
--   long  — you bought the contract (you paid premium)
--   short — you sold the contract  (you collected premium)
--
-- Closes always reverse the open: short opens are closed by buying back,
-- long opens are closed by selling. closes_trade_id points at the open.

CREATE TABLE IF NOT EXISTS public.option_trades (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticker          text NOT NULL,
  trade_date      date NOT NULL,
  action          text NOT NULL CHECK (action IN ('open', 'close')),
  option_type     text NOT NULL CHECK (option_type IN ('call', 'put')),
  direction       text NOT NULL CHECK (direction IN ('long', 'short')),
  contracts       integer NOT NULL CHECK (contracts > 0),
  strike          numeric NOT NULL CHECK (strike > 0),
  premium         numeric NOT NULL CHECK (premium >= 0),
  expiry          date NOT NULL,
  closes_trade_id uuid REFERENCES public.option_trades(id) ON DELETE SET NULL,
  note            text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS option_trades_ticker_idx       ON public.option_trades (ticker);
CREATE INDEX IF NOT EXISTS option_trades_date_idx         ON public.option_trades (trade_date DESC);
CREATE INDEX IF NOT EXISTS option_trades_closes_idx       ON public.option_trades (closes_trade_id) WHERE closes_trade_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS option_trades_open_position_idx
  ON public.option_trades (ticker, option_type, strike, expiry, direction)
  WHERE action = 'open';

-- Reuse the shared updated_at trigger from positions_v2.
CREATE TRIGGER option_trades_set_updated_at
  BEFORE UPDATE ON public.option_trades
  FOR EACH ROW EXECUTE FUNCTION public.positions_set_updated_at();

-- RLS — authenticated full access, anon none.
ALTER TABLE public.option_trades ENABLE ROW LEVEL SECURITY;

CREATE POLICY "option_trades: authenticated read"
  ON public.option_trades FOR SELECT TO authenticated USING (true);
CREATE POLICY "option_trades: authenticated insert"
  ON public.option_trades FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "option_trades: authenticated update"
  ON public.option_trades FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "option_trades: authenticated delete"
  ON public.option_trades FOR DELETE TO authenticated USING (true);

ALTER PUBLICATION supabase_realtime ADD TABLE public.option_trades;

-- Wipe the legacy tables. They were never used in their final form on prod.
-- Putting the DROPs here means a single migration cleanup; users who want to
-- preserve any data should copy it before applying.
DROP TABLE IF EXISTS public.put_protection CASCADE;
DROP TABLE IF EXISTS public.expenses       CASCADE;
DROP TABLE IF EXISTS public.gain_entries   CASCADE;
