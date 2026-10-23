# To do · the Buy inventory row · design brief

Hand this whole file to Claude Design. It builds on handoff 30: block 13 (the Position card's
**To do** face, on the Positions tab) and the rules in block 12b. Precedence as always: UI Kit wins
for visuals, Build Blocks for behavior. Reuse the To do face's existing parts; if nothing fits, say
so.

## Why

Today a buy row reads like an order: **"Buy 11 more Jan $47.5 calls"**. That is not how Nik works.
He is not chasing a strike, he is chasing **delta**: the book sells a call at the money on every
LEAP each week, and the calls he buys are there to keep the book from going short if the stock
jumps. Any strike can do that job with a different number of contracts, and so can shares. He may
pick the strike the row names, a different one, a mix, or buy shares.

So the row should say **how much delta is needed**, give **a few ways to get it**, and shrink as he
fills it. It never tells him which one to pick.

## Where it lives

Only on the **To do** face of each Position card, in the **Buy inventory** group (block 13). One row
per name, as today. The This week group (rolls and sales) does not change. Nothing on Home.

## What the row shows

**1. The need, in shares of delta.** "Need 290 delta by Thu". Shares, not dollars, because one share
is one delta and Nik sometimes buys shares instead of calls. It is the delta the book is short if the
stock is 1.5 weekly SD higher by Thursday (NKE today: $41.33), or what lifts today's delta back to 20%
of the LEAP shares, whichever is bigger. Plain words only; the row does not need to say "1.5 SD".

**2. Four ways to cover it.** Each one covers the **whole** need on its own, so a mix is just a split.

| Way | What it is | NKE today |
|---|---|---|
| Wall | The call wall of the quarterly expiry's chain: where rallies tend to stall | Jan 40: 5 for $1,140 |
| 2nd wall | That chain's runner-up call wall | Jan 42.5: 6 for $882 |
| 1.5 SD | The strike the rule used until now (1.5 SD to the quarterly expiry) | Jan 47.5: 11 for $665 |
| Shares | The stock itself | 290 shares, $11,101 |

**The wall is the default** (Nik, 22 Oct 2026): it comes first, and it is the one the To do totals
count until he buys something. Why, at the same protection (BABA today):

| Choice | Cost | Fast: +10% in a week | Slow: +10% by Dec 15 | Flat to Dec 15 | +38% by Jan 15 |
|---|---|---|---|---|---|
| Wall, Jan 110 (7) | $3,766 | +$3,276 | +$881 | -$2,261 | +$17,524 |
| 2nd wall, Jan 130 (14) | $2,156 | +$2,583 | -$867 | -$1,942 | +$12,425 |
| 1.5 SD, Jan 140 (22) | $1,892 | +$2,438 | -$1,229 | -$1,806 | -$979 |

All three protect alike in a fast jump; only the wall earns in a slow rally, and it wins even at +38%
by January. The far strike pays only in a blowout beyond about 40%. The wall costs more up front.

Shares are capital kept, not premium spent. The row should make that difference clear (for example
"kept as shares"). The three option costs are premium.

**3. The budget, optional.** Nik's question is "how much am I paying to protect the premium". One
small reference: the cheapest way as a share of a week's premium (NKE: $665 against $4,282, about
16%). Your call whether it earns its place.

**4. It shrinks as he fills.** Whatever he buys (any strike, any expiry, a mix, or shares) counts
at its own delta, the need shrinks, and the counts and costs re-size. When the need reaches zero the
row leaves on its own, once IBKR shows the trades. No checkbox (as in block 13).

## Today's rows (22 Oct 2026, after the close)

| Name | Need | Wall | 2nd wall | 1.5 SD | Shares |
|---|---|---|---|---|---|
| NKE | 290 | Jan 40: 5 for $1,140 | Jan 42.5: 6 for $882 | Jan 47.5: 11 for $665 | 290 for $11,101 |
| BABA | 352 | Jan 110: 7 for $3,762 | Jan 130: 14 for $2,163 | Jan 140: 22 for $1,892 | 352 for $35,816 |
| LULU | 302 | Jan 110: 5 for $3,975 | Jan 150: 19 for $2,118 | Jan 145: 16 for $2,240 | 302 for $31,414 |
| PEP | 125 | Jan 140: 2 for $1,060 | Jan 150: 3 for $584 | Jan 165: 9 for $378 | 125 for $17,340 |
| FIS | 142 | Jan 47.5: 5 for $488 | Jan 45: 4 for $310 | Jan 50: 8 for $240 | 142 for $5,434 |
| NFLX | 91 | Jan 80: 4 for $350 | Jan 75: 3 for $507 | Jan 82: 4 for $266 | 91 for $6,105 |

## States to design

- **No need:** no row, as today.
- **The walls are not in strike order.** The 2nd wall can sit below the wall (FIS 45 under 47.5,
  NFLX 75 under 80) or above the 1.5 SD strike (LULU 150 over 145). Decide whether the row orders by
  strike or keeps the fixed order wall · 2nd wall · 1.5 SD · shares.
- **A wall on the 1.5 SD strike:** one line carrying both labels.
- **No wall above the price** in that chain: show what exists.
- **Partly filled:** the need is smaller and every count re-sizes; nothing marks what was bought.
- **Very large shares cost** (BABA $35,816): the number must fit without truncating.
- **Dark mode**, 393 and 430 wide, Dynamic Type, VoiceOver (it should read the need, then each way:
  "Wall, January 40, 5 calls, 1,140 dollars").

## Open for design

- **Fitting four ways in one row.** Today a row is 56 pt with the action, the why line, the cost and
  the delta. Four ways probably need a taller row or a second line of compact items.
- **The totals at the foot of the To do face** (to do · net cost · delta added) count the wall way
  until he buys something, then what he actually bought.
- **The why line** today reads "Short at +8.1% · Jan calls 50 → 75". Keep it, shorten it, or fold it
  into the need line.

## Not in scope

- Placing orders. The app never trades.
- The weekly sales and rolls (This week group).
- Walls on the Sold chart: a separate brief if wanted.

## Copy

No em dashes; use · or -. No plus or minus signs except the delta a task adds ("+$7.9K delta").
"Need 290 delta by Thu", not "short 290 delta". Strikes as "Jan 40", contracts as a plain count.

## Data (for Claude Code, not design)

- Need: `max(-pkg.safe.d15, thin gap)` in shares, from sunny-home's package for the name.
- Walls: gex-walls on the quarterly expiry's chain (`pkg.q.exp`), the call wall and its runner-up.
- The default strike moves from 1.5 SD to the wall: sunny-home's fix row (`pkg.fix`, the To do buy) is
  sized at the wall. With no wall above the price, it falls back to the 1.5 SD strike.
- Count per strike: the need divided by 100 x that call's delta at the +1.5 SD price by Thursday,
  rounded up. Cost: count x mid x 100. Shares: the need x the price.
- Every held call (any strike or expiry) already counts at its own delta, so the need is net of what
  was bought. **Shares do not count yet**: the package reads option legs only. The build adds held
  shares (share_lots, held = bought - sold) at one delta each.
