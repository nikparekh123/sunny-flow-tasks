/* One response from nvda-planner. Conviction is the main number: 0 to 100, off a neutral 50,
   with what moved it stated in the open. Conviction does not just describe the week — it SIZES
   the sale. High conviction shrinks it: fewer contracts, further strike.
   Nothing here is computed in the app. */
window.PLAN2 = {
  asOf: { dow: "Monday", label: "10 Aug", short: "Mon 10 Aug", iso: "2026-08-10", spot: 220.47 },
  ticker: "NVDA",
  /* the shares the calls are written against: the payoff is the whole position, not one leg */
  book: { shares: 7500, buyAvg: 208.33 },

  /* what is already on. The Aug 10 line expired at the open, so there is one. */
  expiries: [
    { iso: "2026-08-12", load: "60 sold for Aug 12", verdict: "60 rollable" },
  ],

  /* where this sits */
  plan: {
    conviction: 91, convictionYest: 78, convictionTrail: [72, 78, 91], paidVsNormal: -12,
    /* what conviction did to the size. full is what the rule would sell at a neutral reading. */
    size: { sold: 22, full: 60, strike: 227.50, fullStrike: 227.50, strikeMoves: false },
    keepPct: 94, keepDelta: 7016, totalDelta: 7500,
    event: "clear week", price: "6% off the high",
    why: "The stretch penalty came off as the price came in, and trend is at its cap. Nothing here argues for capping upside.",
    baseline: 50, convictionMove: 13,
    expiry: "Aug 12", expCode: "08-12", expDays: 2, expectedMove: 7.78,
    /* Always three, always the same three names. Conviction does not change the shape of the
       choice, only where the three sit: at 91 all three moved out and got smaller. Neutral-50
       versions of the same tiers are carried in was, so the shift is visible, not asserted.
       prem is per share, breakeven is strike + prem. blocked refuses a tier out loud. */
    picks: [
      { tier: "conservative", ct: 14, strike: 230.00, otm: 4.32, delta: 15, gamma: .010, iv: 42.6, prem: 0.52, breakeven: 230.52, posBe: 220.37, uncovered: 6100, kept: 97, called: 14, income: 728, label: "$1K", was: "34", beBasisPct: 10.65,
        out: { prem: "+$1K", shares: "+$30K" } },
      { tier: "balanced", ct: 22, strike: 227.50, otm: 3.19, delta: 22, gamma: .014, iv: 43.1, prem: 0.94, breakeven: 228.44, posBe: 220.19, uncovered: 5300, kept: 94, called: 21, income: 2068, label: "$2K", rec: true, was: "60", beBasisPct: 9.65,
        out: { prem: "+$2K", shares: "+$42K" } },
      { tier: "aggressive", ct: 34, strike: 225.00, otm: 2.05, delta: 31, gamma: .019, iv: 43.8, prem: 1.52, breakeven: 226.52, posBe: 219.78, uncovered: 4100, kept: 86, called: 29, income: 5168, label: "$5K", was: "75", beBasisPct: 8.73,
        out: { prem: "+$5K", shares: "+$57K" } },
    ],
    /* why the aggressive end stops where it does */
    tierNote: "The aggressive end stops at 225.00: nearer strikes sit inside the 220 floor's own protection.",
    hedgeNote: "Covers 0.3x of the $7K hedge, against 1.6x at full size",
    grade: 7, gradePrice: 220.47,
    /* which quarter the grade is answering, and every grade given since the first one */
    gradeQuarter: { label: "Q1 FY27", reported: "27 May", sessionsAgo: 53, nextPrint: "26 Aug" },
    gradeHistory: [
      { q: "Q2 FY26", on: "Aug 2025", g: 6 },
      { q: "Q3 FY26", on: "Nov 2025", g: 5 },
      { q: "Q4 FY26", on: "Feb 2026", g: 8 },
      { q: "Q1 FY27", on: "May 2026", g: 7, current: true },
    ],
  },

  /* Nine families off a neutral 50, each capped so five ways of saying "the stock is up"
     cannot stack. peers has a slot and no number yet, and says so rather than reading zero. */
  factors: [
    { key: "trend", hue: "#1F6F4A", reads: "Above the 50-day (±8), above the 200-day (±10), distance from the high (−6 to +8).", min: -22, max: 22, today: 22, yest: 18, d2: 14 },
    { key: "catalyst", hue: "#C08A16", reads: "Print inside 7 days adds 12, inside 21 days adds 10, inside 40 days adds 4. One-directional.", min: 0, max: 12, today: 10, yest: 10, d2: 10 },
    { key: "stretch", hue: "#C0503A", reads: "(σ from the 50-day − 1.5) × 5. One-directional: it can only take conviction away.", min: -12, max: 0, today: -2, yest: -10, d2: -10 },
    { key: "record", hue: "#3B4CA8", reads: "(prints better than −8% ÷ n − 0.7) × 25. Needs at least 8 prints to say anything.", min: -8, max: 8, today: 6, yest: 6, d2: 5 },
    { key: "relative", hue: "#1E7C86", reads: "The gap against SMH × 0.6.", min: -6, max: 6, today: 5, yest: 4, d2: 3 },
    { key: "grade", hue: "#7A4BB5", reads: "(your grade − 5) × 2, decaying over 60 sessions.", min: -8, max: 8, today: 4, yest: 4, d2: 4 },
    { key: "sector", hue: "#93417A", reads: "SMH's own trend against its 50-day × 0.5. Whether the group is working, not just this name.", min: -6, max: 6, today: 3, yest: 3, d2: 3 },
    { key: "macro", hue: "#8A5A2B", reads: "Your dial. Nothing reads it for you.", min: -12, max: 12, today: -7, yest: -7, d2: -7 },
    { key: "peers", hue: "#8E8E88", reads: "Peer print outcomes. The slot exists, the number does not yet.", min: -8, max: 8, today: 0, yest: 0, d2: 0, computed: false },
  ],

  observations: {
    matters: [
      { lede: "What you are paid.", text: "40% against a 45% normal — 12% under it. There is no premium argument for this week, only the roll you were already making." },
      { lede: "The record.", text: "This name has landed better than −8% in 37 of its last 40 prints. Selling upside into that record has been the losing side of it." },
      { lede: "The calendar.", text: "CPI lands on Wednesday, inside the expiry you would be writing." },
    ],
    quiet: [
      { lede: "The neighbourhood.", text: "AMD dropped 7% on its print 6 days ago and NVDA is +9% against the group since. The read-across has not stuck." },
    ],
    silent: ["sentiment"],
  },

  floorAdvice: { stale: false, floor: 220, gapPct: 0.2, head: "The floor is level with spot", verdict: "no change" },

};
