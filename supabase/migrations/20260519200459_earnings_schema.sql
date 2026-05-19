-- /earnings page schema. Two new tables:
--
--   earnings_events  — both upcoming and past events. A future event is just
--                       a row with no summary yet. Same shape across the
--                       lifecycle; flipping from "upcoming" to "past" is
--                       implicit in the date.
--   ticker_peers     — manual peer relationships. (FIG, ADBE) means ADBE is
--                       a peer of FIG. Directional; we don't auto-mirror to
--                       (ADBE, FIG) — peers are not necessarily symmetric.
--
-- Both follow the same RLS pattern as positions/strategy_overlay/etc:
-- authenticated users can read and write everything; anon has no access.

CREATE TABLE IF NOT EXISTS public.earnings_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticker        text NOT NULL,
  earnings_date date NOT NULL,
  fiscal_period text,
  summary       text,
  beat_status   text CHECK (beat_status IN ('beat','met','missed')),
  sentiment     text CHECK (sentiment IN ('bullish','cautious','bearish')),
  rev_reported  numeric,
  eps_reported  numeric,
  guidance_note text,
  source_url    text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT earnings_events_ticker_date_unique UNIQUE (ticker, earnings_date)
);

CREATE INDEX IF NOT EXISTS earnings_events_ticker_date_idx
  ON public.earnings_events (ticker, earnings_date DESC);
CREATE INDEX IF NOT EXISTS earnings_events_date_idx
  ON public.earnings_events (earnings_date);

CREATE TABLE IF NOT EXISTS public.ticker_peers (
  ticker     text NOT NULL,
  peer       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ticker, peer),
  CONSTRAINT ticker_peers_no_self CHECK (ticker <> peer)
);

CREATE INDEX IF NOT EXISTS ticker_peers_peer_idx ON public.ticker_peers (peer);

-- Reuse the existing trigger from positions_v2_schema. The function exists
-- as public.positions_set_updated_at — we bind it to earnings_events too.
CREATE TRIGGER earnings_events_set_updated_at
  BEFORE UPDATE ON public.earnings_events
  FOR EACH ROW EXECUTE FUNCTION public.positions_set_updated_at();

-- RLS
ALTER TABLE public.earnings_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticker_peers     ENABLE ROW LEVEL SECURITY;

CREATE POLICY "earnings_events: authenticated read"
  ON public.earnings_events FOR SELECT TO authenticated USING (true);
CREATE POLICY "earnings_events: authenticated insert"
  ON public.earnings_events FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "earnings_events: authenticated update"
  ON public.earnings_events FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "earnings_events: authenticated delete"
  ON public.earnings_events FOR DELETE TO authenticated USING (true);

CREATE POLICY "ticker_peers: authenticated read"
  ON public.ticker_peers FOR SELECT TO authenticated USING (true);
CREATE POLICY "ticker_peers: authenticated insert"
  ON public.ticker_peers FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "ticker_peers: authenticated delete"
  ON public.ticker_peers FOR DELETE TO authenticated USING (true);

-- Realtime broadcasts
ALTER PUBLICATION supabase_realtime ADD TABLE public.earnings_events;
ALTER PUBLICATION supabase_realtime ADD TABLE public.ticker_peers;
