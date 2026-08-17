# Income sleeve — spec

Agreed 2026-08-15. A third tab alongside Nvidia and TLT, holding several names that
all run the SAME rule. Not a per-ticker screen: adding a fourth name is a row.

---

## What it is

Four legs per name:

| leg | what | how often |
|---|---|---|
| 1 | own the block | standing |
| 2 | **sell** an at-the-money **call** | weekly |
| 3 | **sell** an at-the-money **put** | weekly |
| 4 | **buy** a long-dated out-of-the-money **put**, the FLOOR | once, ~5 months |

Legs 2 and 3 are the income. Leg 4 is the protection, and the income pays for it.

**The floor is the point of the structure, not an afterthought.** Measured on AVGO
2026-08-14 at 1,000 shares: a Jan-15 put 10% out cost $1,145 a week amortised against
a $16,950 weekly credit, and turned a 20% fall from -$139k into -$95k. Roughly 7% of
the income buys a third off the worst case.

Priced wrongly it looks useless. A first pass valued the floor at a crude fraction of
intrinsic and concluded it barely helped; valued properly, with its real time value
and the vol rise that comes with a selloff, it is the best $1,145 in the structure.

**NVDA and TLT are accumulation engines.** They answer "how much do I write today",
which needs bands, budgets, chase rates and dip gates because the size is genuinely
uncertain.

**This is not that.** The size is fixed by the block, so the size question disappears.
The only hard question left is **"should I write at all this week, on this name?"**

That is the entire job of this screen.

---

## The three states

Per name, per week, exactly one of:

| state | means | shown |
|---|---|---|
| **WRITE** | clear to sell both legs | strikes, contracts, expiry, credit |
| **SKIP** | a hard block | the reason |
| **CAREFUL** | soft warning, your call | the number that triggered it |

### What forces SKIP

1. **Earnings inside the expiry.** From a real calendar, never inferred (see below).
2. **No shares.** Cannot write a covered call against nothing.
3. **Ceiling reached.** Put commitment plus stock, less the floors, is at the limit.
4. **No floor, or the floor has under 3 weeks left.** The structure is only sound
   while the protection is on. A floor about to expire gets rolled before any more
   premium is written against it.

### What triggers CAREFUL

1. **Negative edge.** 7-day implied below 20-day realised: you would be selling
   volatility cheaper than the stock has been delivering.
2. **Near the 52-week high.** Above ~75% of the range, since an assigned put buys at
   the top. Nik's stated preference is names near their lows.
3. **Stale data.** Any quote or close older than its expected refresh.

CAREFUL never blocks. It states the number and lets Nik decide.

---

## The edge, and why it is the centre of this

```
edge = (7-day at-the-money implied vol) − (20-day realised vol)
```

Positive means the option is priced above what the stock has actually been doing.
Negative means you are underpaid for the risk you are taking.

**Neither existing engine computes this and it is the whole discipline here.** On
2026-08-14, 15 of 20 names screened had NEGATIVE edge. A planner that simply said
"write every Friday" would have walked into most of them. SHOP was at −37%, PLTR at
−64%, MU at −43%.

The horizon matters and getting it wrong inverts the answer. Comparing a 7-day option
to a YEAR of realised vol made almost everything look like a bad sale. It must be
20 days against 7.

---

## What gets tracked

### Per position (mostly exists already)
- shares held, **average buy** (what the shares cost)
- open calls and puts: strike, expiry, contracts
- premium collected, running
- put commitment: `strike × 100 × contracts` per open put

### CURRENT AVERAGE — the number Nik actually watches

```
current average = average buy − (all premium collected ÷ shares held)
```

Bought at 100, collected $1 on the call and $2 on the put, current average is **97**.
It walks down every week you write, and it is the honest answer to "what did these
shares really cost me".

⚠ **DECIDED 2026-08-15: premium counts ON COLLECTION here. Do not "fix" this to match
the glossary.**

This deliberately differs from NVDA and TLT. Those engines only count a short option's
premium once it has EXPIRED or been CLOSED, per `docs/PNL_GLOSSARY.md`, on the grounds
that an open short can still be bought back higher. That rule was itself settled after
a TLT card read $499 against the summary's $249, so it is not casual.

The reason this tab differs: the book turns over WEEKLY, so the gap between collected
and realised is days rather than months, and the entire point of the strategy is
watching the average grind down. Waiting for expiry would make the headline number lag
the thing it exists to show.

Nik was shown both conventions and chose collection, explicitly, on 2026-08-15.

Consequence to live with: "premium collected" means something slightly different on
this tab than on the other two. If that ever causes confusion, the fix is to label
both figures on screen, NOT to silently change either definition.

### The floor, per name (new)
- strike, expiry, contracts, what was paid
- **what it is worth now**, priced properly: real time value, not intrinsic
- **weeks left** on it
- **funded yet?** cumulative premium since the floor was bought, against its cost.
  Once that crosses 100% the protection is free for the rest of its life. On AVGO
  that took about 21 days against a 154-day life, so it pays for itself roughly
  seven times over.
- **gap to the floor**: how far the stock is above the strike, in percent. This is
  the size of the hole the floor does NOT cover.

### Per name (new)
- **edge**, as above
- **days to next earnings**
- **52-week position**, 0% at the low, 100% at the high
- **coverage**: covered shares ÷ shares held

### Portfolio
- **stock held** and **put commitment**, SEPARATELY (see the header note)
- premium collected this week
- contracts expiring Friday
- correlation between the names, refreshed monthly not daily

---

## The screen

```
INCOME
stock $600k · puts commit $600k · floors -$180k · NET AT RISK $1.02m of $1.5m

INTU · WRITE      6 calls 345 · 6 puts 345 · Fri 21 Aug
                  avg 331 from 346 · sells 44%, moves 43% · $10,400
                  floor 310 Jan, funded

NKE  · SKIP       earnings Thu 24 Sep is inside this expiry
                  avg 38.10 from 40.79 · floor 37 Jan, funded

LULU · CAREFUL    sells 35%, moves 43% — underpaid by 8
                  avg 114 from 120 · floor 108 Jan, 62% funded

this week         $10,400 collected · 12 contracts expire Friday
```

### Wording

**"implied 35% against 43% realised" is jargon and was rewritten.** The line now
reads `sells 35%, moves 43%`, which says the same thing without needing the vocabulary:
you are selling the option at 35 and the stock is actually doing 43.

When the edge is negative, the sentence completes itself: `sells 35%, moves 43% —
underpaid by 8`. When it is positive, no suffix is needed; the two numbers speak.

**The average reads `avg 331 from 346`.** Current average first, what the shares
actually cost second, so the gap between them is the premium you have banked.

Each name also carries its floor strike, its expiry month, and whether the premium
has paid for it yet. That last word is the one to watch: once a floor is **funded**
the protection is free for the rest of its life.

Tap a name for its position detail: shares, average cost, open legs, premium
collected. ONE detail component shared by every name; most of it already exists on
the NVDA position screen.

### ⚠ The header, and why it has three numbers not one

A first draft showed a single "committed" figure. That hides the actual risk.

You own the shares AND sell puts against them, so there are **two** exposures:

- **stock**: what the blocks are worth now
- **put commitment**: what you would owe if every open put assigned
- **at risk**: the two added together

**Selling at-the-money puts on a block you already own roughly DOUBLES what you are
on the hook for.** $600k of stock carrying $600k of puts is $1.2m of exposure. The
ceiling must be set against the combined figure, and the screen must show all three
so the doubling is never invisible.

The floors then subtract from it. A floor 10% out on the full block caps how far the
bottom can fall, so it is shown as a negative line and the ceiling is measured against
**net at risk**. It does not remove the exposure, it truncates it: everything between
the current price and the floor strike is still yours to lose.

---

## What this does NOT do

No accumulation target. No chase rate. No price bands. No dip gate. No horizon
projection. No position sizing. No "top 3" or ranked suggestions.

Those belong to the accumulation engines, or to a discovery tool that is deliberately
NOT being built yet (see below).

---

## Data needed

**1. Real earnings dates.** `earnings_events` exists and needs populating for every
name traded here.

Inferring earnings from the volatility term structure was tested on 2026-08-14 and
got 7 of 8 right, but called PYPL as an imminent event when the print was 74 days
away. Good as a cross-check, unusable as the primary source.

**2. 20-day realised vol**, per name, daily. Cheap: it is the standard deviation of
the last 20 daily log returns, annualised.

**3. 7-day at-the-money implied**, per name. Backed out of the nearest weekly
at-the-money option. The `option-chain` edge function already returns what is needed.

**4. A data sanity gate, before anything else.** Of ~50 names screened on 2026-08-14,
THREE had unusable price history: SPCX (a different company until Jun 2026), META
(Meta Materials until Jun 2022), FIG (a 385% day). Every one produced confident,
completely wrong numbers. SPCX showed a 24.7x payback that was pure fiction.

Any name whose history contains a single-day move over ~45%, or a gap over 10 days,
is flagged and excluded from the edge calculation rather than scored.

---

## Honest limits

**The rules moved four times in one evening.** Names were ranked by yield, then edge,
then edge plus earnings, then correlation, then 52-week position. Each step changed
the answer. AVGO was top of the list for an hour before its +0.51 correlation to NVDA
removed it. Do not treat these thresholds as settled; revisit after a month of use.

**20 days of realised vol is a short window.** The edge column moves around, and a
single quiet fortnight makes a name look mispriced. It is a filter, not a forecast.

**Correlation drifts.** The three names were chosen partly because they are nearly
uncorrelated to NVDA, TLT and each other. That will not hold forever. Monthly check,
not a daily number on the screen.

---

## Deliberately not in scope

A discovery tool that scans ~50 names and suggests new positions. Discussed and
postponed on 2026-08-15. The reasoning: the code is feasible, but the selection rules
are a day old and moved repeatedly while being worked out. A scanner running last week
would have been confidently recommending AVGO.

If it gets built later, the sequence is: a plain REPORT first (facts only, no ranking,
no suggestions), watched for a month, and only then any ranking logic.
