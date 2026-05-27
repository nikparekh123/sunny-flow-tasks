/**
 * Frontend-side BNF universe metadata.
 *
 * Re-exports the same UNIVERSE + ETF_UNIVERSE arrays the bnf-scan edge
 * function uses, so the New Strategy page can render all ~1030 tickers
 * (not just the BNF survivors persisted in bnf_candidates) without
 * duplicating the data.
 *
 * The .ts files live under supabase/functions/bnf-scan/ because that's
 * where the edge function imports them from at deploy time. We expose
 * them to the Vite frontend by adding those two specific files to
 * tsconfig.app.json's `include` list. Anything else inside supabase/
 * stays out of the frontend build.
 */
import {
  UNIVERSE as EQUITY_UNIVERSE_RAW,
  type UniverseEntry as EquityUniverseEntry,
} from '../../../supabase/functions/bnf-scan/universe.ts';
import {
  ETF_UNIVERSE as ETF_UNIVERSE_RAW,
  type EtfEntry,
} from '../../../supabase/functions/bnf-scan/etf-universe.ts';

export type UniverseKind = 'EQUITY' | 'ETF';

export interface UniverseMember {
  ticker: string;
  universe: UniverseKind;
  name: string | null;          // ETFs always have a name; equities resolve via bnf_candidates lookup
  sector: string | null;        // equity only
  sectorEtf: string | null;     // equity only
  category: EtfEntry['category'] | null;   // ETF only
}

/** Combined list — equities first, then ETFs. Order is stable, so the
 *  table can render in a deterministic sequence regardless of which
 *  candidates happened to match today. */
export const BNF_UNIVERSE: UniverseMember[] = [
  ...EQUITY_UNIVERSE_RAW.map((u: EquityUniverseEntry): UniverseMember => ({
    ticker: u.ticker,
    universe: 'EQUITY',
    name: null,
    sector: u.sector,
    sectorEtf: u.sectorEtf,
    category: null,
  })),
  ...ETF_UNIVERSE_RAW.map((e: EtfEntry): UniverseMember => ({
    ticker: e.ticker,
    universe: 'ETF',
    name: e.name,
    sector: null,
    sectorEtf: null,
    category: e.category,
  })),
];

/** Quick lookup by ticker — used to merge the latest-price view rows
 *  (which only carry ticker + price data) with their universe metadata. */
export const BNF_UNIVERSE_BY_TICKER: Map<string, UniverseMember> = new Map(
  BNF_UNIVERSE.map((m) => [m.ticker, m]),
);
