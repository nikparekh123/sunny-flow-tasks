# Income scanner — gate spec

Agreed 2026-08-17. The screen that decides which names are *eligible* for the
income sleeve. Not built yet; this is what it will be built from.

It is a **report**, not a recommender. It applies gates, emits facts, and sorts.
Nik picks. Only then does a name become a row in `income_sleeve_names` and a card
on the Income screen.

---

## ⚠ Gate zero: exclude market-wide days

**This one is first because getting it wrong quietly poisoned every other gate.**

The "no bizarre swings" rule measured each stock's worst single day outside its
earnings prints. On 2026-08-17 that gate excluded NKE, LULU, ORCL and AAL — and
every one of their "gappy" days fell on 3, 8, 9 or 10 April 2025.

So did everyone else's. On 9 April 2025, **79% of the 134-name universe moved more
than 5%**, average +11.1%. It was a macro week, not a stock-specific event, and the
gate was reading the market's behaviour as evidence about the stock.

**Definition.** A trading day is a MARKET day when more than **25% of the universe
moved more than 5%**. Those days are removed before any per-stock statistic is
computed. Over Apr 2025 to Aug 2026 that is fifteen days:

```
2025-04-03  2025-04-04  2025-04-09  2025-04-10  2025-05-12
2025-10-10  2025-11-13  2025-11-20  2026-02-05  2026-02-06
2026-03-31  2026-04-23  2026-06-05  2026-06-11  2026-07-30
```

What it changes:

| | worst day before | after |
|---|---|---|
| NKE | 16.9% | **5.0%** |
| LULU | 10.6% | **7.0%** |
| NFLX | 8.6% | 7.8% |

NKE and LULU were never gappy names. The whole candidate list went from **two names
to nine** on this one correction.

The threshold is a universe fraction rather than an index return on purpose: it
needs no external benchmark and it scales with whatever list is being scanned.

---

## The gates

Applied after market days are removed, and after earnings days are identified.

| gate | threshold | why |
|---|---|---|
| **weekly options** | **3+ distinct expiries in the next 5 weeks** | see below |
| **option liquidity** | **50** open interest across ±5% of spot, both legs | see below |
| **share price** | $15 to $400 | under, the premium is noise and spreads eat it; over, one contract is too big to size against a ~$200k block |
| **own gap** | no non-earnings, non-market day worse than **12%** | Nik's no-bizarre-swings rule, properly isolated |
| **has stopped falling** | within **±15%** over three months | a broken narrative that has settled, not one still breaking |
| **calm enough** | 60-day realised vol under **45%** | high vol demands capital better spent elsewhere, and it is realised vol that eats the short straddle |
| **edge** | **positive AND under 15 points** | see below |
| **earnings date** | on file, confirmed or estimated | otherwise nothing guards the print |
| **correlation** | under **0.40** to every held name, over 250 days | or the sleeve owns one position twice |
| **52-week position** | under **45%** | Nik writes into names near their lows, not their highs |

### Weeklies must be counted, not assumed

**This gate was in this spec from the first draft and was not implemented for two
days.** The scanner only ever asked for the coming Friday, and 21 Aug 2026 is the
THIRD Friday — the monthly expiry — so every optionable name in the country has
contracts that day.

ZTS passed with 11,252 open interest and a 4.23% straddle while having no weekly
market at all:

```
              ZTS   NKE   PEP
2026-08-21     17    46    55     <- monthly, everyone is here
2026-08-28      0    39    54
2026-09-04      0    37    53
2026-09-11      0    27    50
```

Nik caught it. The failure would have appeared only one week in four, which is
the worst kind: silent three weeks out of every month.

Counting DISTINCT EXPIRIES over the next five weeks is the test. A weekly name has
four or five; a monthly name has one. A separate, deliberately narrow call, since
it only needs the dates.

### Liquidity is a floor, not a bar

Nik, on seeing NKE rejected at 38: *"128 is not bad unless you see one or two then
reject."* He is right, and the first version was wrong twice over.

**It measured one strike.** Open interest piles up on round strikes, so whichever
happens to sit nearest spot says nothing about whether there is a market. NKE and
LULU, two of the most heavily traded names in the US, came back at 38 and 128. It
now sums every strike within **5% of spot**, both legs.

**And it judged rather than filtered.** The gate's only job is to catch a name with
no weekly market at all. Grading how *good* the market is would be a quality score
smuggled in through a filter, which is the thing this screen exists not to do.

So: **50 across the band**, and everything above it passes. The figure itself is
reported, plus a plain word — thin, fine, deep — so the difference is visible
without being a verdict.

**Volume is not gated at all.** A quiet name with real open interest and no trades
today is perfectly tradeable, and a scan running before the open sees zero volume
on everything.

### Why the edge has an upper bound

Positive edge is the whole discipline: implied above realised means the option is
priced above what the stock has been doing.

But on 2026-08-17 the two best-scoring names in the entire screen were **EL at
+53.1** and **PYPL at +34.9**, and both are traps. A seven-day option priced fifty
volatility points above realised is the market pricing an event inside that week
which the scanner cannot see. **An enormous edge is a trap, not a find.**

### Data sanity, before anything is scored

Any name whose history contains a single-day move over ~45%, or a gap over 10
days, is EXCLUDED rather than scored. Of ~50 names screened on 2026-08-14, three
had unusable history from ticker reuse (SPCX, META, FIG) and every one produced
confident nonsense. ZS was caught this way on 2026-08-17 (a -32% day).

---

## Two buckets, not one ranking

Simulated over ten weeks on each name's own returns, these behave differently
enough that a single score would hide it:

**Broken and quiet** — NKE, LULU, NFLX. A bigger discount, and a worse tail.

**Just quiet** — KO, PEP, MCD, PG. A smaller discount and almost no tail. KO's
worst case was 1% underwater against NKE's 10%.

Every row carries its bucket. Neither is better; they are different trades.

---

## Columns

```
percent a week · edge · next earnings · 60-day vol · 3-month move ·
worst own-gap day · 52-week position · option volume & open interest · bucket
```

**No composite score.** Every attempt to compress this into one number has moved
the ranking by the next day. Nik sorts.

**No suggestions.** The scanner never proposes a trade.

---

## Reference: what passed on 2026-08-17

Run over 134 names, market days excluded. Kept here so a future change to the
gates can be checked against a known result.

```
            spot    12mo     3mo   vol   52w    gap  corr
MCD       272.83    -12%   -2.7%   22%   13%   4.2%  0.24
PEP       140.79     -5%   -5.7%   24%   16%   5.1%  0.27
PDD        84.79    -26%  -13.6%   42%   18%   6.4%  0.25
PG        144.55     -6%   +1.5%   22%   22%   3.9%  0.27
UBER       75.95    -17%   +1.8%   42%   29%   6.5%  0.24
HSY       184.22     +2%   -3.5%   31%   30%   5.0%  0.21
JD         29.06     -8%  -10.5%   32%   35%   6.0%  0.22
CAG        15.62    -20%  +13.5%   35%   41%   5.0%  0.28
KMB       110.39    -17%  +13.2%   28%   43%   4.9%  0.20
```

Held names NKE, LULU and NFLX also pass. ORCL fails on four gates (still falling
20% in three months, 68% vol, 0.42 correlation to NVDA). AAL fails on three (under
$15, 55% vol, and 58% up its range — it is up 16% over the year and not beaten
down at all).

---

## Open before building

**Option volume and open interest.** Not yet confirmed available per contract on
the current Polygon plan. The liquidity gate is the one that cannot be faked, and
building it on an unstated proxy is how INTU got into the sleeve.

**The strategy simulation.** Still omits the volatility lift after a fall (measured
at 1.20x, and real) and the floor. Until both are modelled it cannot say whether
the sleeve beats simply owning the shares. The gates above do not depend on that
answer, so the scanner can be built in parallel.
