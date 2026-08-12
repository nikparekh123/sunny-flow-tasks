# TLT — the accumulation mechanism

Settled 2026-08-12. This is the spec for `tlt-planner`. Written before any code so
the disagreements happen here rather than in a rebuild.

## What makes TLT different from NVDA

NVDA is one strategy: a block you own, an overlay on top. TLT is **two** —
a block you are still acquiring, and an overlay on whatever has arrived so far.
Both run at once, and the same conviction reading moves them in opposite
directions. That is the structural difference and everything below follows from it.

## The parameters

| | |
|---|---|
| target | ~100,000 shares |
| horizon | **100–120 weeks** from Aug 2026 — a band, not a date |
| quarterly budget | 10–12K shares |
| cash ceiling | **$400,000** outstanding short-put commitment |
| cadence | thrice weekly, same as NVDA |
| floor | long puts sized to the **fully-assigned** share count |

The horizon is a band because the pace is not fixed. 100K arrives in 108 weeks at
12K a quarter, 118 weeks at 11K, and 130 weeks at 10K. So the band closes **only if
the quarterly budget runs in its upper half** — 10K a quarter and the programme
runs past its own outer edge. Treat 11–12K as the working budget and 10K as the
number that means the horizon has to give.

The band is what makes "soft" measurable. Inside 100 weeks the programme is early;
between 100 and 120 it is on plan; past 120 the tool says **behind**, and the
choice is Nik's — extend, raise the quarterly budget, or accept a smaller block.
A soft horizon that stretches forever reports nothing.

## Three factors, two jobs

Time and price set the SPEED. Macro decides whether you are accumulating at all.

### Phase — the macro switch

Nik's input, not the model's forecast. The tool shows the evidence; he sets the state.

- **ACCUMULATE** — rates high or rising, TLT cheap. Puts do the work, calls stay light.
- **HOLD** — rates turning, TLT rallying. Stop adding. Keep the shares. Calls come up.
- **HARVEST** — rates low, TLT rich. Calls do the work. The programme is over.

The model must not forecast the rate path. It reports the voter bloc, how the last
CPI landed against expectation, and where the curve prices the path — and says so
when the evidence stops agreeing with the phase. The drift call is his; on TLT the
drift call IS the strategy.

### Quarterly budget — a budget, NOT a quota

10–12K shares, set at the start of each quarter, reviewed at the end. 11–12K is the
working number; see the horizon band above for why 10K does not close.

**A missed quarter is a correct outcome, not a shortfall.** If TLT sat at 88 all
quarter and only 6K arrived, the next quarter's budget does not become 18K. It
stays 10–12K and the gap spends weeks out of the 100–120 band. That is what the
band is for: the cost of a missed quarter is visible as position in the band, not
as a pace that quietly accelerates.

This rule exists because the obvious implementation breaks: *remaining gap ÷
remaining weeks* accelerates the pace as a quarter runs out, which means buying
hardest at the end of a quarter that was expensive throughout. Exactly backwards.
**The pace never chases.**

### Weekly pace and the price multiplier

    weekly delta  =  (quarter budget ÷ 13)  ×  price factor

    price factor    > 85    0.25×
                  80–85    0.75×
                  75–80    1.50×
                    < 75    2.50×

Each week's budget is split across that week's decisions in proportion to the days
each one covers — a Monday write that runs to Wednesday carries less than a
Wednesday write that runs to Friday.

Worked, at 11K a quarter:

| TLT | weekly delta | ~contracts | committed |
|---|---|---|---|
| 83 | 635 | 14 | $115K |
| 78 | 1,270 | 28 | $218K |
| 74 | 2,115 | 47 | $352K |

## The cash ceiling — the one hard constraint

**$400,000 outstanding commitment**, counting every unexpired short put, not just
this week's. Conviction may not override it, the price multiplier may not override
it, and the phase may not override it. It is the same role the hedge floor plays on
the NVDA side: the single thing allowed to say no.

Without it the multiplier is fiction — the tool tells you to write 47 puts into a
fall, you decline, and from then on you are not using the tool.

## The two legs, and why they balance

Position delta is one number:

    shares            +1.00 each
    short puts        +delta      (a short put is long delta)
    short calls       −delta
    long put floor    −delta
    ────────────────────────────
    net delta

The weekly question is not "how many puts" and separately "how many calls." It is:
**where should net delta be, where is it, and how is the gap split.** Puts add,
calls subtract. Conviction then has one job and one sign again — it sets the SPEED
of accumulation — and the two legs fall out of it rather than fighting.

Output reads: *"Sell 14 puts at 82, sell 4 calls at 83. Net +900 delta, putting you
at 12,400 of 100,000."*

### The floor is collateral, not insurance

The long puts are deliberately over-sized against current shares. They are not
there because a crash is expected — they are what lets the next put be written
after two assignments have already gone against you. Without them, three
assignments down the programme stops.

Two consequences the tool must show:

**Size to the fully-assigned count.** 16 Dec 80 puts against 1,000 shares looks
over-hedged and is not: it covers the 1,600 that exist once the short puts deliver.
The floor anticipates assignment.

**Net delta and share count diverge.** The floor's delta grows as TLT falls —
−0.35 today, −0.60 at 78 — exactly while assignments are adding shares. You can be
put 5,000 shares and find net exposure barely moved. Report net delta as the
position, with share count beside it, or the page will overstate progress.

## A short put is not income

Six puts at 82 is a **$49,200 commitment to buy**, not $186 of premium. Booking it
as income flatters the sleeve and hides the obligation. It shows as **pending
shares** with the cash it commits, and becomes income only when it expires
worthless.

## What is his, what is the model's

**His:** the phase, the quarterly budget, the target, the horizon, the ceiling.
**The model's:** the arithmetic, the evidence, and saying plainly when the evidence
and the phase disagree.

## Open before build

- The rates conviction families (drafted separately). `supply` has no free feed;
  `real` needs FRED. Seven families with wider caps is the fallback.
- Whether HOLD and HARVEST need their own call-side settings or inherit NVDA's.
