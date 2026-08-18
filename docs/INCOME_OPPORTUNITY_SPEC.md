# Income sleeve: writing by opportunity, not by calendar

Agreed in conversation 2026-08-18. Not built. This is what it will be built from.

The sleeve currently writes on a weekly rhythm: sell, wait, sell again. That
rhythm was never the strategy. It was a habit sitting on top of the strategy,
and the strategy is one number.

---

## The one signal

**Edge = 7-day ATM implied vol minus 20-day realised vol.**

Write when a name clears **+3**. Never write above **+15**.

Nothing else is a reason to write. Not a big premium, not a low price, not a
name being overdue. When ladders, tenor staggering and buy-backs were simulated
in August 2026 every one of them failed and the note in
`project_wheel_structure_research` is the finding: only the vol edge earns.

### Premium is not edge, and the board proves it

| | pays a week | edge |
|---|---|---|
| UBER | 3.29% | **+0.3** |
| CCL | 3.25% | **+5.7** |
| NKE | 3.02% | **+11.1** |

UBER pays the most on the board and earns none of it: implied is priced at
almost exactly what UBER actually moves. CCL pays nearly the same with six
points of real edge. **The card must lead with edge**, because premium is the
number that feels like the answer and is not.

---

## Sizing is in dollars, never in contracts

The sleeve writes a fixed 25 puts. 25 NFLX puts is a $190,000 promise and 25 CCL
puts is a $133,000 one, and calling both "25" has been hiding the actual risk.

```
contracts = floor( room_for_this_name / (strike x 100) )
```

Where `room_for_this_name` is the smaller of the remaining headroom and the
per-name cap. A fixed count is not a fixed size, and the size is the risk.

---

## The limits

| limit | value | why |
|---|---|---|
| **commitment cap** | **$500,000** on the sleeve | dollars owed if every open put is assigned |
| **per-name cap** | 1/3 of the cap | one name must not become the whole book |
| **edge floor** | **+3** | below this the option is not paying for the movement |
| **edge ceiling** | +15 | an event is priced inside the week |
| **earnings** | no expiry after the report date | the print is the one thing the week cannot absorb |
| **expiries open** | one at a time | see below |
| **Friday** | no new writes on an expiry Friday | Monday's position is not known yet |

### TLT is out of scope

TLT runs its own dip rule and its short puts are deliberately NOT counted here.
On 2026-08-18 they stood at $311,300 against the sleeve's $180,800. They are a
claim on the same cash, so a whole-book ceiling is worth setting eventually, but
it is not part of this and the sleeve's $500,000 stands on its own.

### Why expiries are not spread

This was asked for and rejected, and the reason is not the failed August test.

Today the book is **flat on puts every Friday afternoon**. Carrying two expiries
at once removes that. Peak exposure is unchanged, since both tranches are open
together, and the only moment the book is genuinely empty disappears. That is
strictly more risk, bought in exchange for nothing.

If the worry is a large assignment landing in one go, **write smaller**. Same
result, and the flat week survives.

---

## The cards

Content only. Design follows the Ink card spec.

### 1 · What I am on the hook for

```
COMMITTED                                    [ 36% OF CAP ]
$180,800
IF EVERY PUT IS ASSIGNED

  NFLX   13 puts at 77 .......  $ 99,800   Fri 21 Aug
  NKE    20 puts at 39.5 .....  $ 81,000   Fri 21 Aug

CAP $500,000  |  HEADROOM $319,200  |  WHOLE BOOK $492,100
```

### 2 · Today

```
TUE 18 AUG                                   [ 2 TO WRITE ]
  NKE    edge +11.1   write at 39.5, Fri 28 Aug
  CCL    edge  +5.7   write at 27,   Fri 28 Aug
  UBER   edge  +0.3   pays 3.29% and earns none of it, skip
  PDD    edge +10.9   no earnings date on file, skip
  LULU   edge +16.1   an event is priced inside the week, skip
```

### 3 · Progress

```
THIS WEEK                                 [ $6,536 / $5,000 ]
$6,536 COLLECTED
TARGET MET FOR FRI 21 AUG

RUN RATE $2,900/wk   MONTH $18,400   FLOORS $17,070
FLOORS PAID FOR IN 3 WEEKS
```

### 4 · Friday

```
FRI 21 AUG                                    [ SETTLE DAY ]
NOTHING TO WRITE TODAY

  13 NFLX puts at 77    spot 76.02    1.3% in the money
  20 NKE  puts at 39.5  spot 39.09    1.0% in the money

IF BOTH ASSIGN YOU BUY $180,800 AND HOLD 8,600 SHARES MONDAY
```

### 5 · A calm day

```
WED 19 AUG                                 [ NOTHING TODAY ]
NO NAME CLEARS THE EDGE FLOOR

Best was PEP at +2.4 against a floor of +3.0.
Nothing is wrong. The edge was not there today.
```

A quiet day is a normal day. The card says so plainly and does not hedge. Idle
time is not a leak; that was measured, and buying back to stay invested cost 2.8x
the gross premium and doubled the tail.

---

## Monitoring

Two bars and one list.

- **Commitment against the cap.** The constraint. Hard stop.
- **Income against the weekly target.** The goal. Never a reason to write, only a
  reason to stop.
- **The open puts, by expiry.** What is owed and when.

Income is the goal, commitment is the constraint, edge is the trigger. Three
different numbers. Confusing the first with the third is how a book gets too big.

---

## Open

- A whole-book ceiling covering TLT as well as the sleeve. Deferred, not dismissed.
- LULU is above the edge ceiling at +16.1 and is out of the sleeve until it settles.
- PDD reports 24 Aug, six days out. Its +10.9 edge is the print being priced, and
  it is unwritable for any expiry that reaches the date.
