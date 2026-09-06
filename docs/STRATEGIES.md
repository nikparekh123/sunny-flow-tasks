# The strategies

**Read this file before answering anything about strategy. Do not reconstruct it
from memory.** Reconstructing is what kept mixing TLT with the income sleeve, and
it is now what would have you describing a share block that was sold on
31 August 2026.

Last rewritten **2026-09-06**. One book runs today. Two are wound down and kept
below, marked, because their rules are still correct for what they were and
deleting them is how they get half-remembered.

---

## The book that runs: stock replacement

**Shares were sold on 31 August 2026.** Every name is now a deep in-the-money
LEAP call instead of a share block, and a weekly call is sold against it.

Entering a name is two legs: **buy the LEAP, sell the call.** Then a call every
week thereafter.

| | |
|---|---|
| the long leg | a deep ITM call, Jan 2028, roughly 0.9 delta |
| the short leg | one weekly call per LEAP contract, at the money |
| names | near a 52-week low, held with conviction, **they do not change weekly** |
| shares | none. The LEAP is the position |

Live at the time of writing: NKE, BABA, NFLX, LULU, FIS, PEP, KR.

### The put programme, from 2026-09-08

Added on top, not instead. **Buy six-month puts roughly 1:1 against the LEAPs,
twice a year. Sell a smaller weekly quantity of puts to fund them.** The aim is
protection that pays for itself, never income.

Selling about **a quarter of the notional** each week fully funds a 1:1 six-month
put. It works because weekly puts trade rich to six-month puts: the square root
of time says a 6-month should cost about 5.1x a weekly, and NKE measures 6.13x,
BABA 6.80x, NFLX 6.67x. FIS is the exception at 3.80x and funds itself worst.

**Two things that are true whatever the financing:**

**A deep ITM LEAP already contains a put.** By put-call parity a long call at K
is long stock plus a long put at K. A new put therefore only adds cover between
its own strike and the LEAP strike. LULU and PEP get **nothing** from one, because
their LEAP strikes already sit at or above spot.

**The financing leg is short the crash being hedged.** At a quarter notional that
is roughly $135,000 of stock committed for assignment in a falling week, and there
is no share block left to absorb it.

### How the app counts it

Four rulings, 2026-09-06. They exist because each one had two defensible answers.

1. The put cover ring counts **short-put premium only**. Call premium is already
   the numerator of Yield progress, and one dollar cannot discharge two
   obligations on two cards you can see at once.
2. Put cost does **not** join Yield progress's denominator. That card stays a
   question about the LEAPs.
3. The ring **never resets**. Cost is every dollar ever spent net on long puts,
   collected is every short-put credit ever. Buying a tranche raises the cost and
   drops the ring; the weeklies climb it back.
4. Roll check carries sold puts beside sold calls, suffixed `PEP 140P`, one
   sorted list, header "sold".

And one that is not a preference: **moneyness inverts on a put.** A call is in the
money above its strike, a put below it. That flag drives every row colour and the
ROLLING count.

---

## Wound down

Kept so the rules are not half-remembered. **Neither has an open leg. Do not
describe either as running.**

### Income sleeve — retired 2026-08-31

Own a block of shares near a 52-week low. Every week sell one ATM call and one
ATM put per 100 shares. Hold an ATM 4-month put underneath as the floor.

**Never a standalone put.** Entering a name meant four legs at once: buy the
shares, sell the call, sell the put, buy the floor. "Write N puts on X" was not a
sentence this strategy could produce.

Replaced by stock replacement above. The floor put is the one idea that survived,
in the put programme.

### TLT — no open leg since 2026-09-01

No block. No conviction. Sell puts on the second red day of a slide, nearest
Friday, nearest strike, flat size. Assignment is how you buy it.

**The put IS the trade.** There was no block underneath and nothing to protect.

100 TLT shares remain from an assignment. No options.

### NVDA — no open leg since 2026-08-17

Puts on Fridays only. An income wheel, not accumulation.

---

## The mistakes to check yourself against

**Do not describe a share block.** There is not one. Every "own the shares"
sentence in this file lives under *Wound down* and is history.

**Do not treat the book as weekly.** Nik: *"I cant buy Nike one week and not buy
next week, this is not a weekly game plan, the puts bought will cost me. Plus
being 52 week low or near that means my conviction is high, to hold them not toss
them away each week or day."* The names do not change. Only the weekly call does.

**Do not apply a new-money test to a position already held.** An edge floor
decides where NEW capital goes. A LEAP already owned is written every week
regardless, because the premium is what pays it off.

**Do not confuse the two puts.** The book now has long puts (the hedge, bought
six months out) and short puts (the funding, sold weekly). They are opposite
legs of one structure. TLT's put, above, was a third thing entirely and is
retired.
