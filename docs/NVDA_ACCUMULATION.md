# NVDA — the accumulation plan

Settled 2026-08-12, from `research/nvda-tenor`. Every number below was measured on
real NVDA closes and real option marks over 2024-07 to 2026-08, not reasoned.

NVDA joins TLT's shape: a block being built by selling puts, not a block being
monetised by selling calls. That is a change of strategy, not of parameters.

## The parameters

| | |
|---|---|
| starting point | **1,000 to 1,500 shares**, after the reduction (decided 12 Aug) |
| target | 15,000 by Dec 2027 |
| to accumulate | **~13,500 shares** |
| horizon | ~72 weeks, ~5.5 quarters |
| rate | **~190 shares/week**, ~2,450/quarter |
| **expiry** | **weekly** (biweekly is a tie if fewer tickets are worth more) |
| **strike** | **1% out of the money** |
| contracts | **~5 a week** at that strike |
| cash committed | **~$117K** outstanding |
| earnings | **play through it** |
| calls | **none** |

## Strike: 1% out, and the reason it is not ATM

| strike | ct/wk | shares | delivery | net basis | peak cash | total |
|---|---|---|---|---|---|---|
| ATM | 4.2 | 18,900 | 100% | 151.84 | $90K | $1,359,528 |
| **1% OTM** | **5.2** | **19,100** | **102%** | **148.95** | **$117K** | **$1,429,112** |
| 2% OTM | 6.1 | 18,500 | 99% | 149.38 | $163K | $1,376,230 |
| 3% OTM | 8.1 | 15,300 | 82% | 141.12 | $311K | $1,264,674 |
| 5% OTM | 15.4 | 13,200 | 70% | 125.91 | $929K | $1,291,787 |

1% wins on everything at once — more shares, better basis, +$69,583 — for $27K more
capital than ATM. The curve peaks there and falls away both sides.

**Delivery is the mechanism.** Delta is a risk-neutral probability, and NVDA's real
drift ran far above risk-neutral. Near the money that barely bites, and realised
assignment slightly BEAT what delta priced (102%). Two sigma-fifths out it starts to
cost, and by 5% out three shares in ten never arrive.

**The rule that covers strike and tenor together: stay inside one sigma.** Weekly sd
is 4.75%, so 1% out is a fifth of a sigma. The same rule killed monthly expiries,
where delivery fell to 82% at 30 days against 98% at 7.

Weekly assignment over the last year, 49 weeks, which is what actually decides a
weekly put rather than the daily distribution:

| strike | weeks assigned |
|---|---|
| ATM | 24 of 49 (49%) |
| 1% OTM | 22 of 49 (45%) |
| 2% OTM | 17 of 49 (35%) |

Ten points of assignment lost for the second point of strike. That is the cliff.

## Earnings: play through

Eight prints in the window. Stripped of what the shares did afterwards, the option
side nets **−$808 across all eight**, four of eight profitable. The premium looks fat
because IV is elevated and essentially all of it goes back at assignment.

So the case for playing is not that the premium is good. It is that skipping forfeits
8% of the year's accumulation, and accumulation is the objective.

**And earnings is not the risk that matters here.** NVDA's largest moves in the window
were DeepSeek (−17.0%), the tariff pause (+18.7%) and the July 2024 rotation (+12.8%),
against a worst earnings reaction of −8.5%. Protection has to be structural — size,
floor, ceiling — not a date in the diary.

## Calls: none, and the overwrite does not fund a floor

A 10% floor rolled quarterly costs **−$263,448** net over two years. The best overwrite
tested returns **+$99,014**, and gets there by writing half the block at 4% out. Nothing
tested funds it; the closest is $164,434 short.

So if the floor is carried it has to justify itself on **margin relief**, not on premium.
That is a broker-mechanics question and should be sized from real buying-power numbers,
not modelled.

## What premium actually does to the basis

Over the two-year run the premium moved the basis from **156.01 to 148.95**, a **4.5%**
reduction. That is the real, durable effect and it is worth having.

It is **not** larger for holding fewer shares. Premium per share is
`premium ÷ shares held`, so a small book shows a huge per-share number and identical
dollars:

| shares held | same premium, per share |
|---|---|
| 100 | $1,347 |
| 1,500 | $90 |
| 19,100 | $7.06 |

Every row is the same $134,759. Only the denominator moves. Shrinking the book to
flatter the ratio buys nothing and costs participation in the stock the programme
exists to own.

## The floor

At 1,000 to 1,500 shares there IS a block behind the obligation, which is the whole
difference from starting at 100. Five short puts carry ~$110K of assignment exposure;
against a hundred shares that is almost pure obligation, against fifteen hundred it is
a position with a hedgeable core. The floor stops being a week-one emergency and
becomes what it is on TLT: sized to the fully-assigned count, and justified by margin
relief rather than by premium.

## What is still open

- **Net delta target.** TLT's fell out of its accumulation rate. Here it is a decision,
  because a retained block plus short puts plus any floor resolve to one number.
- **Margin.** Whether a long put beneath the short puts frees enough buying power to
  pay for itself. Needs real IBKR numbers.
- **The price multiplier cannot be absolute.** TLT's under-75-buy-harder works because
  TLT oscillates around a yield. NVDA trends, so the speed dial has to read distance
  below a moving reference, not a price.
