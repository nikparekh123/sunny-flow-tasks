# Income screen — design brief

Hand this whole file to Claude Design. It is self-contained: the brief and the real
data are both here.

---

Design a mobile screen for a personal investing app. It is one of three position
screens; the other two each cover a single stock, and this one covers a small group
of stocks that all follow the same weekly routine.

**What the user does with it.** Once a week he opens this screen, reads it in under a
minute, and places trades in his broker based on what it says. It is a decision
surface, not a dashboard. He is not a professional trader and he reads it on a phone,
usually standing up.

**The routine, so the content makes sense.** For each stock he owns a block of shares.
Every week he sells two option contracts against that block, which pay him cash
immediately. He also holds a long-dated protective contract underneath, called the
floor, which limits how far the position can fall. The weekly cash pays for the floor
over time. Some weeks a stock has a company earnings announcement inside the option's
life, and those weeks he skips it entirely.

## Three regions

### 1. A standing summary at the top

Four facts about the group as a whole:

- how much money is invested
- how much cash has been collected so far
- how far the collected cash has pushed his effective cost below what he paid
- what the floors cost, expressed both as a share of the cash collected and as how
  many weeks of collecting pay for them

Plus what is collectable this week, and the date the contracts expire.

### 2. A ranked list of the stocks

Currently three, expandable to more. **The order is meaningful and changes over
time:** they are ranked by how much cash each has produced per week per dollar
invested. The rank position must be immediately visible.

Before any cash has been collected the rank falls back to a forecast, and the row
states which basis was used. A forecast and a track record must never look identical.

Each row carries, in this order:

1. the stock symbol and its current price
2. a short verdict phrase on whether this is a good week to sell, which is the single
   most important thing on the row
3. what has been earned, per week, and since when
4. what to sell this week: how many of each contract, at what price level, expiring
   when, and the cash it pays. Or, if the week is being skipped, the reason instead
5. the money committed, meaning what he would owe if the contracts are exercised
   against him
6. the size of his holding, as a share count, a dollar value, and a percentage of the
   group
7. his effective cost now versus what he originally paid, plus how much each of the
   two contracts contributed to closing that gap
8. where the price sits in its 52-week range, whether it just made a new low, and
   three plain trend facts
9. the floor: its price level, how far below the current price it sits, and whether
   the cash has paid for it yet

Several of these are absent early on and read as "none yet" or "nothing yet". **Empty
is a normal state, not an error state**, and there will be weeks where a row is almost
entirely empty.

### 3. A closing note

One or two sentences, reminding him these are trading positions rather than long-term
holdings.

## Tone, which matters more than usual here

An earlier version flagged missing pieces as warnings and it read as alarmist.
Everything here is a plain fact.

There are exactly **two states**: sell this week, or skip this week with a stated
reason. There is no cautionary middle state and nothing that reads as an alert. A
missing floor is simply reported as missing.

## Constraints

- Every row must be reachable without horizontal scrolling. The ranking is the point,
  and hiding the last-ranked item defeats it.
- Density is high, roughly eight labelled facts per row. The current build is not
  comfortably readable on a phone, and fixing that matters more than fitting
  everything above the fold.
- **Numbers are the content.** Prices, percentages, share counts and dollar amounts
  all sit next to each other and have to be told apart at a glance.

---

# The data

Two states, both real. The first is the screen as it stands today, before anything has
been bought. The second is the same screen a month in, built from this week's actual
strikes and premiums.

## State one — nothing owned yet, Sun 16 Aug

```
Header    invested $0 · collected $0 · average nothing yet
          floors none yet, nothing to pay back
          this week $0 to collect, writes to Fri 21 Aug

INTU      346.18   good week to sell
          rank      nothing yet · ranked on this week's 4.9%
          skip      no shares yet, nothing to write against
          block     no shares yet
          where     20% up the 52w range · above the 50 day · RSI 68 · 5d +6.4%
          floor     none yet

NKE       40.79    good week to sell
          rank      nothing yet · ranked on this week's 3.2%
          skip      no shares yet, nothing to write against
          block     no shares yet
          where     1% up the 52w range · below the 50 day · RSI 43 · 5d -2.2%
          floor     none yet

LULU      119.78   good week to sell
          rank      nothing yet · ranked on this week's 4.2%
          skip      no shares yet, nothing to write against
          block     no shares yet
          where     13% up the 52w range · above the 50 day · RSI 53 · 5d -6.8%
          floor     none yet

Note      These are trading positions. Every put here is a promise to buy at the
          strike, and the calls can take the shares away.
```

## State two — a month in, all three blocks owned

```
Header    invested $603,314 · collected $80,456 · average 13.3% below cost
          floors $18,400, 23% of premium, paid back in 2 weeks
          this week $24,652 to collect, writes to Fri 18 Sep

1 · INTU  351.40   good week to sell
          rank      3.68% a week · $30,600 since 17 Aug
          write     6 puts 350 · 6 calls 350 · Fri 18 Sep · $10,200
          money     puts commit $210,000
          block     600 shares · $210,840 · 34% of the sleeve
          avg       294.00 from 345.00 · calls gave 27.00, puts gave 24.00
          where     24% up the 52w range · above the 50 day · RSI 61 · 5d +0.9%
          floor     310 Jan · 12% below the price · paid for

2 · NKE   41.20    good week to sell
          rank      3.19% a week · $26,000 since 17 Aug
          write     50 puts 41 · 50 calls 41 · Fri 18 Sep · $6,500
          money     puts commit $205,000
          block     5,000 shares · $206,000 · 33% of the sleeve
          avg       35.80 from 41.00 · calls gave 2.22, puts gave 2.98
          where     4% up the 52w range · below the 50 day · RSI 47 · 5d -1.1%
          floor     37 Jan · 10% below the price · 78% paid for

3 · LULU  117.10   poor week to sell
          rank      3.11% a week · $23,856 since 17 Aug
          skip      earnings Thu 25 Sep is inside this expiry
          money     puts commit $0
          block     1,600 shares · $187,360 · 30% of the sleeve
          avg       105.09 from 120.00 · calls gave 7.35, puts gave 7.56
          where     11% up the 52w range · below the 50 day · RSI 44 · 5d -2.4%
          floor     108 Jan · 8% below the price · paid for
```

## Notes on the data

- **State one is live**, read from the function on 2026-08-16. Nothing is owned yet,
  which is why every row is mostly empty. The design has to hold up like this.
- **State two is arithmetic**, not a guess: it takes this week's real strikes and
  premiums forward three weeks of writing, with the INTU and LULU earnings weeks
  skipped.
- **LULU in state two shows the skip case.** No trade to place, a stated reason, and
  every other fact still present. Roughly one row in five looks like this.
- **The rank basis differs between the two states.** State one is a forecast and says
  so. State two is a track record. They must not be mistakable for one another.
- Long field values wrap. The `avg` and `where` lines are the longest and will run to
  two lines on most phones.
