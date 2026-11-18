# Option pies · design brief

Hand this whole file to Claude Design. It builds on the Positions handoffs of 13 Nov 2026 (the name
page on the web and the phone). Precedence as always: UI Kit wins for visuals, Build Blocks for
behavior. Reuse existing parts where they fit; if nothing fits, say so.

## Why

Nik (and his cousin Nicolay, book N) run the same plan on every name: own shares and long-dated
calls, protect them with puts, and **sell calls and puts** every week to pay for it all. He wants to
see, at a glance, **how much the selling is paying for**. In his words: "think of it as a pie chart
... how much slice the short puts are giving us, almost like a yield, how much of the pizza pie is
being covered."

Two questions, one pie each:

| Pie | The whole pie | The slice | It answers |
|---|---|---|---|
| **Puts** | every put bought: the weekly short-dated ones and the long-dated ones | the credit from puts sold | How much of my protection have the sold puts paid for? |
| **Calls** | the shares and the calls bought | the credit from calls sold | How much of the position have the sold calls paid back? |

Plus **one overall pie per book**: the whole is both wholes added up, and the slice is both slices,
in **two colours** (calls, puts). It answers: how much of everything I paid has the selling paid back.

## Where it lives

- **Per name:** a Puts pie and a Calls pie on each name's page on Positions, web and phone. Two
  pies, not two cards' worth of rows. Where they sit on the page is your call.
- **Overall:** one pie for the book, at the top of Positions. Book S and book N each have their own.
- This **replaces** the leg-by-leg "UBER Puts" card Nik sketched on 17 Nov. **No Max loss** anywhere.

## What each pie shows

1. **The pie**, with the slice in two tones: **kept** (solid) for sold contracts that expired or
   were bought back, and **still open** (lighter) for credit on contracts not finished yet. Same idea
   as the old Coverage card: settled credit solid, open credit as a lighter cap.
2. **The percentage in the centre**: kept ÷ the whole. Puts say "paid for", Calls and the overall
   pie say "paid back".
3. **Three figures under it:** the whole (e.g. "Puts bought $6,257"), kept, and still open.

**Not on the pies** (Nik said no, 17 Nov): Max loss, the leg rows, and any "cushion" where put
credit offsets calls or call credit offsets shares. Each pie stays on its own side.

## The rules (Claude Code computes these; listed so the design knows what moves)

- **Since the book started:** book S from 31 Aug 2026, book N from 29 Oct 2026. A contract is in
  by the day it was **opened**. The pie never resets.
- **Short-dated or long-dated put:** a put bought that ends within **2 weeks** of the day it was
  bought is a weekly hedge for the sold puts. Anything longer protects the shares. Both are in the
  Puts pie. (Nik, 17 Nov.)
- **Puts and calls bought count at what they cost after what they paid back** (Nik's own footnote:
  "protection is what the hedges cost after what they paid back").
- **Credit counts after buy-backs:** what a contract was sold for, minus what it cost to buy back.
- **Shares count at what they cost** (IBKR average × shares held).

## Today's figures (real, after the close on Tue 17 Nov 2026)

**Puts.** The whole = puts bought, after what they paid back.

| Name | Book | Puts bought | Sold, kept | Sold, still open | Kept | With open |
|---|---|---|---|---|---|---|
| UBER | S | $810 | $0 | $2,056 | 0% | 254% |
| LULU | S | $6,257 | $938 | $3,522 | 15% | 71% |
| NKE | S | $3,027 | -$131 | $735 | lost $131 | 20% |
| FIS | S | $223 | $898 | $0 | 403% | 403% |
| BABA | S | made $1,240 | -$6,499 | $1,283 | - | - |
| NFLX | S | made $1,953 | -$620 | $681 | - | - |
| NVDA | N | $5,045 | -$1,658 | $23,428 | lost $1,658 | 431% |
| SPCX | N | $0 (none bought) | $114 | $2,345 | - | - |

**Calls.** The whole = shares + calls bought, after what they paid back.

| Name | Book | Shares | Calls bought | The whole | Sold, kept | Still open | Kept | With open |
|---|---|---|---|---|---|---|---|---|
| NFLX | S | none | $39,532 | $39,532 | $6,407 | $442 | 16.2% | 17.3% |
| UBER | S | none | $27,953 | $27,953 | $3,786 | $339 | 13.5% | 14.8% |
| BABA | S | $86,558 | $16,190 | $102,748 | $12,250 | $646 | 11.9% | 12.6% |
| FIS | S | $14,066 | $8,866 | $22,932 | $1,609 | $0 | 7.0% | 7.0% |
| NKE | S | $118,215 | $10,454 | $128,669 | $1,613 | $0 | 1.3% | 1.3% |
| LULU | S | $77,109 | made $1,087 | $76,022 | -$497 | $1,194 | lost $497 | 0.9% |
| NVDA | N | none | $19,960 | $19,960 | $0 | $2,494 | 0% | 12.5% |
| SPCX | N | none | $11,202 | $11,202 | $0 | $0 | 0% | 0% |

**Overall.**

| Book | The whole | Kept: calls | Kept: puts | Still open: calls | Still open: puts | Kept | With open |
|---|---|---|---|---|---|---|---|
| S | $404,980 | $25,168 | -$5,414 | $2,621 | $8,277 | 4.9% | 7.6% |
| N | $36,207 | $0 | -$1,544 | $2,494 | $25,773 | lost $1,544 | 73.8% |

The overall pie adds up the names held today. Names already closed out (PEP, KR, TLT in book S)
are not in it.

## States to design (every one is real today)

- **Under 100%** (LULU puts 15%, NKE calls 1.3%): the normal case.
- **Over 100%** (FIS puts 403%, UBER and NVDA with open credit 254% and 431%): paid for more than
  once. A pie stops at 100%; show the rest (a second lap, "4.0×", your call).
- **The sold side lost money** (BABA puts kept -$6,499, NVDA -$1,658, LULU calls -$497): the kept
  slice is below zero. It must read as a loss, not as an empty pie.
- **The bought side made money** (BABA and NFLX puts, LULU calls bought): the hedges paid back more
  than they cost, so there is no whole to fill. Say it plainly ("Puts made $1,953").
- **Nothing bought yet** (SPCX puts: 8 sold, none bought).
- **Nothing sold yet** (SPCX calls).
- **Mostly still open** (NVDA puts: $23,428 open against -$1,658 kept): the lighter tone carries
  almost the whole slice.
- **One colour negative in the overall pie** (book S: calls +$25,168, puts -$5,414).
- **A name with no shares** (NFLX, UBER, NVDA, SPCX): the Calls pie's whole is calls bought only.
- **The book switch:** S and N each show their own overall pie and names.
- **Dark mode**, phone 393 and 430 wide, the web page, Dynamic Type, VoiceOver ("UBER calls, 13.5
  percent paid back, 3,786 dollars kept of 27,953").

## Open for design

- Pie or ring (a donut leaves room for the number in the middle).
- How over 100% and a negative slice read.
- How the two colours sit in the overall pie when one is negative.

## Copy

No em dashes; use · or -. "Paid for" (puts), "Paid back" (calls, overall), "Kept", "Still open",
"Puts bought", "Calls bought", "Shares". Whole dollars; percentages to one decimal under 10%, whole
numbers above.

## Data (for Claude Code, not design)

- Every read filters `book_id` and `voided_at is null`.
- A leg = (ticker, option_type, direction, strike, expiry). It is in if its first open is on or after
  the book's start (S 2026-08-31, N 2026-10-29).
- Cash per row: `net_cash` (IBKR, commission included). 265 IBKR rows since 31 Aug have no
  `net_cash`; fall back to ± contracts × premium × 100 + `commission`.
- Kept = legs flat or past expiry; still open = the rest.
- Short-dated put bought: expiry minus first open ≤ 14 days.
- Shares: `positions.quantity × avg_cost` where quantity > 0.
- Figures above came from a one-off query on 17 Nov 2026; sunny-home would send them per name and
  per book.
