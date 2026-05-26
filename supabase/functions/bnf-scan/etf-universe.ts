/**
 * Second BNF universe — sector and industry ETFs (~30 names).
 *
 * Mean-reversion behaves differently for ETFs than for single names:
 *   • no earnings / insider / 8-K risk to filter out
 *   • universally liquid → no ADV gate
 *   • broader-market guard is SPY itself (not a sector ETF), since the
 *     candidate IS a sector ETF
 *
 * Categories used by the UI to color/group rows:
 *   • Sector     — the 11 SPDR Select Sector ETFs (XLK / XLF / …)
 *   • Industry   — narrower thematic / industry slices (SMH, KRE, …)
 *   • Style      — size and style benchmarks (IWM, QQQ, …)
 */

export interface EtfEntry {
  ticker: string;
  name: string;
  category: 'Sector' | 'Industry' | 'Style';
}

export const ETF_UNIVERSE: EtfEntry[] = [
  // ── 11 broad SPDR sector ETFs ──
  { ticker: 'XLE',  name: 'Energy Select Sector SPDR',                category: 'Sector' },
  { ticker: 'XLF',  name: 'Financial Select Sector SPDR',             category: 'Sector' },
  { ticker: 'XLK',  name: 'Technology Select Sector SPDR',            category: 'Sector' },
  { ticker: 'XLV',  name: 'Health Care Select Sector SPDR',           category: 'Sector' },
  { ticker: 'XLY',  name: 'Consumer Discretionary Select Sector SPDR', category: 'Sector' },
  { ticker: 'XLP',  name: 'Consumer Staples Select Sector SPDR',      category: 'Sector' },
  { ticker: 'XLI',  name: 'Industrial Select Sector SPDR',            category: 'Sector' },
  { ticker: 'XLB',  name: 'Materials Select Sector SPDR',             category: 'Sector' },
  { ticker: 'XLU',  name: 'Utilities Select Sector SPDR',             category: 'Sector' },
  { ticker: 'XLRE', name: 'Real Estate Select Sector SPDR',           category: 'Sector' },
  { ticker: 'XLC',  name: 'Communication Services Select Sector SPDR', category: 'Sector' },

  // ── 15 industry / thematic ──
  { ticker: 'SMH',  name: 'VanEck Semiconductor ETF',                 category: 'Industry' },
  { ticker: 'KRE',  name: 'SPDR S&P Regional Banking ETF',            category: 'Industry' },
  { ticker: 'KBE',  name: 'SPDR S&P Bank ETF',                        category: 'Industry' },
  { ticker: 'KWEB', name: 'KraneShares CSI China Internet ETF',       category: 'Industry' },
  { ticker: 'XBI',  name: 'SPDR S&P Biotech ETF',                     category: 'Industry' },
  { ticker: 'IBB',  name: 'iShares Biotechnology ETF',                category: 'Industry' },
  { ticker: 'ITB',  name: 'iShares U.S. Home Construction ETF',       category: 'Industry' },
  { ticker: 'XHB',  name: 'SPDR S&P Homebuilders ETF',                category: 'Industry' },
  { ticker: 'XOP',  name: 'SPDR S&P Oil & Gas E&P ETF',               category: 'Industry' },
  { ticker: 'OIH',  name: 'VanEck Oil Services ETF',                  category: 'Industry' },
  { ticker: 'GDX',  name: 'VanEck Gold Miners ETF',                   category: 'Industry' },
  { ticker: 'GDXJ', name: 'VanEck Junior Gold Miners ETF',            category: 'Industry' },
  { ticker: 'XRT',  name: 'SPDR S&P Retail ETF',                      category: 'Industry' },
  { ticker: 'JETS', name: 'U.S. Global Jets ETF',                     category: 'Industry' },
  { ticker: 'ARKK', name: 'ARK Innovation ETF',                       category: 'Industry' },

  // ── 4 style / size ──
  { ticker: 'IWM',  name: 'iShares Russell 2000 ETF',                 category: 'Style' },
  { ticker: 'MDY',  name: 'SPDR S&P MidCap 400 ETF',                  category: 'Style' },
  { ticker: 'IWB',  name: 'iShares Russell 1000 ETF',                 category: 'Style' },
  { ticker: 'QQQ',  name: 'Invesco QQQ Trust',                        category: 'Style' },
];
