# Share average card · design brief

Hand this whole file to Claude Design. It builds on the Positions handoffs of 13 Nov 2026 (the name
page on the web and the phone). Precedence as always: UI Kit wins for visuals, Build Blocks for
behavior. Reuse existing parts (the Price chart's line, the stat rows); if nothing fits, say so.

## Why

Nik owns shares in four names and sells calls and puts around them. He wants one honest score per
name: **what his shares really cost him now**, after every trade on that ticker has paid off or
lost. In his words: "all profits within that ticker and any losses drive the share price average up
or down, the rest will be expenses."

So the card starts from what he paid per share and moves it by every **closed** trade on the name:

**New average = (shares × average paid − realized profit) ÷ shares**

- **Realized profit** counts closed trades only, from five places: calls sold, puts sold, calls
  bought, puts bought, and shares sold. A profit moves the average down. A loss moves it up.
- **It counts everything on the ticker since the book started** (Nik, 15 Nov 2026: "since 31 aug,
  everything on the ticker"): every trade closed from 1 Sep 2026, including the LEAPs he sold on
  5 Nov to buy the shares. Same start as every realized figure in the app.
- **Running expense** is what the hedge calls and puts **still held** cost. It stays out of the
  average until each one closes or expires, then it joins it. Margin interest is not on this card.

**On this card, down is good.** A lower average is a win. Watch every colour and arrow for this.

## Where it lives

On each name's page on Positions, web and phone. Where it sits on the page is your call. One card
per name that holds shares. A name with no shares (NFLX and UBER today) has no card.

## What the card shows (Nik agreed these five, 15 Nov 2026)

1. **The new average**, big, with the **average paid** and **today's price** beside it. The new
   average against the price tells him if he is ahead: under the price, ahead; over it, behind.
2. **The change since last Friday**, e.g. "down $1.59 since Friday". What changed comes first.
3. **Which strategy is winning:** five steps in **dollars per share**, from the average paid to the
   new average: calls sold, puts sold, calls bought, puts bought, shares sold. Same unit as the
   average, so he can see which leg pulls it down and which pushes it up.
4. **The running average line**, one point per Friday close since the start, with the **price line**
   on the same chart. When the average line sits under the price line, he is ahead.
5. **Running expense:** what the open hedges cost, in dollars and per share ("$9,152 · $3.05 a
   share").

**Not on the card** (Nik said no): how much is covered (%), weeks it has taken, weeks to go, weeks
until the shares are free, the weekly average as its own number.

## Today's figures (close of Fri 13 Nov 2026, real, book S)

Everything closed on each ticker since 1 Sep. Steps are dollars per share: a negative step lowers
the average. The shares were bought on 5 Nov, when the Jan 2028 LEAPs were sold, so the LEAP sale
sits in Calls bought (FIS lost $8,603 on it, which is why its new average is far above the price).

| Name | Shares | Paid | Calls sold | Puts sold | Calls bought | Puts bought | Shares sold | **New average** | Price | Since Friday | Running expense |
|---|---|---|---|---|---|---|---|---|---|---|---|
| NKE | 3,000 | $39.41 | +$0.31 | +$1.04 | +$1.37 | −$2.26 | +$0.52 | **$40.39** | $37.98 | flat | $9,152 · $3.05 |
| BABA | 800 | $108.20 | −$13.90 | +$9.92 | +$11.52 | −$16.10 | $0.00 | **$99.65** | $94.39 | down $8.13 | $16,957 · $21.20 |
| LULU | 700 | $110.16 | +$0.74 | −$1.31 | −$5.57 | +$0.29 | $0.00 | **$104.30** | $105.57 | down $4.17 | $8,873 · $12.68 |
| FIS | 480 | $29.30 | −$2.85 | −$1.68 | +$17.92 | −$4.45 | +$0.74 | **$38.98** | $29.65 | down $1.59 | $270 · $0.56 |

The chart starts at the first Friday he held the shares (6 Nov). Its first point already carries
everything closed since 1 Sep, so it does not start at the price paid. Running average by Friday
(2 points so far): NKE $40.39 then $40.39; BABA $107.77 then $99.65; LULU $108.47 then $104.30;
FIS $40.56 then $38.98.

## States to design

- **Ahead** (new average under the price: LULU) and **behind** (over it: FIS by $9.33, NKE by
  $2.41).
- **The new average above the price paid** (NKE, FIS): the ticker has lost money overall so far.
- **A flat week** (NKE: +$0.00) and **a losing week** (the average went up).
- **A step of $0.00** (BABA and LULU have sold no shares). Show it, dim it, or hide it.
- **The first week:** one point on the chart, no "since Friday" yet.
- **The chart's first point is not the price paid** (FIS starts at $40.56 against $29.30 paid). Say
  where the paid average sits.
- **A hedge closes:** running expense drops and the average jumps in one step. It is correct, but
  it should not look like an error.
- **Shares partly sold:** the average is over the shares still held.
- **Long run:** the new average can fall a long way below the price, and in theory to zero.
- **Dark mode**, phone 393 and 430 wide, the web page, Dynamic Type, VoiceOver ("NKE, new average
  40 dollars 39, paid 39 dollars 41, price 37 dollars 98").

## Open for design

- How the five steps read: a waterfall, a list, or a bar. They must be scannable at a glance.
- Whether the chart is its own block or shares the Price chart's style.
- Plain words ("down $2.14") or signs (−$2.14) for the steps.

## Copy

No em dashes; use · or -. "New average", "Average paid", "Running expense". Money to the cent per
share, whole dollars for running expense.

## Data (for Claude Code, not design)

- Every read filters `book_id = S` and `voided_at is null`.
- Average paid and shares: `positions.avg_cost` and `quantity` (IBKR, commission included).
- Realized: `option_trades` close rows' `realized_pl` (IBKR's figure, by close date), split by
  `direction` × `option_type`; shares from `share_sells.realized_pl`. Every close dated after
  31 Aug 2026 (sunny-home's realized rule since 19 Oct), so the 31 Aug sale of the old shares
  stays out (NKE −$4,008, BABA −$3,316).
- Running expense: long legs still held, at their opening cost (`net_cash` of the opens, for the
  contracts still held).
- Weekly points: the new average at each Friday close.
