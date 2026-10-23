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

**From 2026-10-23: weekly puts only above the 50-day.** Nik: a name sells its weekly
puts only while its last close is above its 50-day average; below it, put sales pause
(To do shows "Puts paused · Below the 50-day"). The weekly short puts netted about
**-$44** from 31 Aug to 23 Oct (3 winning weeks, 3 losing), so they were adding drop
risk for nothing. The long protective puts are unchanged.

**From 2026-10-23 (handoff 31): strikes from the gamma walls.** Nik:
- **Weekly short puts** (when above the 50-day) go at next Friday's **1st put wall** below
  the price (its 2nd wall once the price has fallen through the 1st). The count is
  unchanged: the put cap. Replaces "nearest strike at or below" and the 2% overlay rule.
- **Hedge calls** are bought at the quarterly's **1st call wall** (2nd wall, 1.5 SD and
  shares shown as other ways), sized to the delta still needed: short at +1.5 SD by
  Thursday, or under the floor today. Shares and puts count in that delta.
- **Protective puts:** January's 1st and 2nd put walls are shown with price and delta;
  no size is suggested, Nik decides.
- Hedge expiry: January until it is under 8 weeks out (to 20 Nov 2026), then March, June,
  September and December, each moving on at 8 weeks the same way.

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

### The in-the-money put overlay, from 2026-10-15

Replaces the 1:1 six-month programme above for **NKE, LULU, BABA and NFLX**. Nik sold
every put by 15 Oct and asked for a forward test (not a backtest: these names fell 20 to
30% in two years). Research: `research/itm-puts/` and the page "LEAP Put Overlay Test".

| | |
|---|---|
| the long put | March 2027 (about 5 months), the strike nearest 8% above the price, on **half** the LEAPs; roll before expiry into the next ~5-month put |
| the weekly put | **half the long puts**, the first strike at least 2% below the price, never above a long put's strike (always covered) |
| the calls | **from 2026-10-20: the call rule below** (every LEAP at the money) |
| extra upside | **from 2026-10-20: the quarterly 1.5 SD calls below.** Before that: 12-month ~30% out and 3-month ~15% out, 10% of LEAP value a year (held ones stay on the books) |

Across the ten names tested: about free in a flat year, +$219K in a 30% crash, -$151K in a
sudden 30% jump. The account is on portfolio margin, so the puts cut the margin requirement
by about a third. The book goes delta negative after big falls while the puts are working.

### The call rule, from 2026-10-20: at the money + quarterly 1.5 SD

**Every name.** Replaces "a third at the money, the rest at 0.6 SD" and the NKE read
rule's strike. Nik, 20 Oct 2026: "1.5 SD means selling ATM as we agreed and buying
quarterly 1.5 SD calls, add based on delta and SD." Tested 19 Oct as "Q 1.5 SD"
(`research/target-study/diagq_fwd.py`, `six_fwd.py`): the best all-rounder found, ahead of
the 0.6 SD rule's forward average on all seven names.

| | |
|---|---|
| the weekly calls | **every LEAP**, each Friday for the next Friday, at the money: the first strike at or above the price |
| earnings week | a report after the Friday sale and before the expiry: every call at **1 SD**, no puts |
| the quarterly calls | the next Jan/Apr/Jul/Oct expiry at least 3 weeks out, the first strike at or above the price + **1.5 SD to that expiry** (spot x IV x sqrt(time)) |
| how many quarterly calls | enough that the plan **holds net delta at 0 or above if the stock is 1.5 weekly SD higher by the Thursday before the expiry**, and at 20% or above today (landing on 25%) |
| the other fix | sell fewer weekly calls instead, sized the same way. The Planner offers both as a pick-one pair; buying is the default (about 3x cheaper as a standing rule, 20 Oct check) |
| puts | unchanged (the overlay above; NKE's puts still from its reads) |

Why 1.5 SD: in the Planner's own SD, 1.5 SD up covered 19 weeks in 20 for every held name
but BABA over the last year (earnings weeks aside). A 1 SD check costs about the same:
the weekly calls are all in the money by about 1 SD, so they cannot get any shorter after
that. The Delta card shows the +1.5 SD figure; the Thesis receipt shows the rule.

### NKE weekly rule (trial), from 2026-10-17 to 2026-10-20 (calls retired)

**Its call strike, count (54 of 60) and skip are retired by the call rule above.** Its puts
still run. Kept for the record.

Chosen by Nik after the 17 Oct tests (`research/target-study/`). Each week the seven factors give simple reads,
and the reads pick the strike.

| | |
|---|---|
| how many calls | **54 of 60** (keep 10% free). NKE's one exception to "calls on every LEAP" |
| skip the week | IV rank under 25, or IV below realised volatility measured **without earnings days** |
| earnings before expiry | calls at 1 SD, no puts |
| ex-dividend, calls within 2% of the price | fewer calls |
| the strike | start at 0.6 SD, or 0.8 SD if momentum is bullish. One step wider if stretched up, or if momentum and technicals are both bullish. One step closer (20% at the money, the rest 0.6 SD) if stretched down or fundamentals are bearish. Never past 1 SD |
| breakout week (up 5% or more in 5 days) | the next strike above the week's high, never inside the range |
| puts | half the long puts (13 today) at 0.6 SD, 0.8 SD if momentum is bearish. None if stretched down or across earnings. Never above a long put's strike |
| extra upside | unchanged: the 3-month and 12-month buys above, **bought always**. A buy-on-trigger version was tested and dropped: it fired in nearly every year and bought late |

The reads:

- **Momentum:** bullish above a rising 200-day line, bearish below a falling one, else mixed.
- **Technicals:** bullish above the 20- and 50-day lines with RSI 50 to 70, bearish below both with RSI under 50, else mixed.
- **Stretched up / down:** in the top or bottom 10% of the month's range after a 5%+ week.
- **Fundamentals bearish:** the price is more than 10% above value (the middle of the analyst target and the models).

Tested, rolled every Friday: NKE's real year made $40.5K with 6 losing weeks (worst
-$5.9K), against today's rule $45.6K with 13 (worst -$11.5K). In the forward test it
makes about $2.4K a year less on average and loses $10K more in a crash, but makes $14K
to $38K more in a violent rally. Nik's view: these names are beaten down, so a violent
rally is the case worth paying for.

### Planned: TSLA and SpaceX (SPCX), from 2026-10-14

Not traded yet. Researched for Nik (`docs/TSLA_SPCX_RESEARCH.md`); the app's
write suggestions already carry these rules and switch on when a name is held.

| | TSLA (sideways view) | SPCX (very bullish) |
|---|---|---|
| the long leg | Jan 2028, about 0.80 delta | Jan 2028, deep (0.85 to 0.88 delta) |
| the short leg | 3% out of the money on 70% of the LEAPs, weekly | 5% out of the money on 50%, weekly |

**Not the roll sheet, and not three times a week.** These two names do not take the
book's third-at-the-money rule; weekly beat Mon/Wed/Fri selling in the test.

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
