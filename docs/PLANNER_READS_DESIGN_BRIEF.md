# Planner reads · design brief

Hand this whole file to Claude Design. It builds on handoff 25: block 14b, the Planner
(SunnyPlanner), and block 14, Inventory. Precedence as always: UI Kit wins for visuals,
Build Blocks for behavior. Reuse the Planner's existing parts; if nothing fits, say so.

## Why

The Planner shows one name at a time: what is held now, next week's suggestions, and where
delta lands. For **NKE only** (a trial), next week's sells now come from a rule driven by
simple **reads** of the stock. Today the Planner shows the suggestion but not why. Nik needs
to see the reads and the pick they produce, so he can trust or overrule the suggestion in
under a minute, on a phone.

His direction: very simple, checkbox style, one short fact each. Not a data screen.

## What to add (NKE only; every other name stays as it is)

**1. The reads.** One row each: the factor, a read word, one short fact.

| Factor | Read words | Fact (NKE, 16 Oct close) |
|---|---|---|
| Fundamentals | bullish · neutral · bearish | value $42.05, 13% above the price (analysts $36.41, model $47.70) |
| Technicals | bullish · mixed · bearish | above the 20-day line, below the 50-day, RSI 58 |
| IV | rich · OK · skip | IV 36%, rank 32, 1.4x realised |
| History (the month) | stretched up · up · flat · down · stretched down | top of the month's range after +7% in 5 days |
| Momentum (the year) | bullish · mixed · bearish | below a falling 200-day line ($47.40) |
| Events (to expiry) | clear · ex-dividend · earnings | nothing before 23 Oct. Earnings 17 Dec, ex-dividend about 1 Dec |
| Breakout week | yes · no | up 7% in 5 days: sell above the 5-day high $37.87 |

Delta, the seventh factor, is already the Planner's Delta card. Do not repeat it.

We need a **short** version of each row (read word + one number, e.g. "Fundamentals · bullish · 13%
room") and the **long** fact above. Your call how they relate (for example short by default, long
on tap).

**2. The pick.** One line: what the rule chose and why. NKE now: **"0.8 SD"**, because
"momentum bearish; stretched up: wider". The Suggestion chips already carry the strikes and
quantities; this line explains them.

**3. Which reads moved it.** Most reads change nothing most weeks. Show which ones drove the
pick (NKE now: momentum and history) apart from the rest. The Ink idea: opacity is relevance.

**4. What changed since last week.** Mark a read whose word changed since last Friday's pick
(the reads are stored daily). A read that did not change is not news.

**5. Quantity.** The rule sells **54 of 60** calls and keeps **6 free** on purpose (room for a
sharp rally). Show it as kept free, not as room left. In Inventory (block 14), NKE counts full
at 54, with the 6 shown as kept free, never as "not covered" or as room to sell.

## How the rule picks (so the states make sense)

- **IV skip:** no sells that week (buys only).
- **Earnings before expiry:** every call at 1 SD, no puts.
- **Otherwise the menu:** start at 0.6 SD (0.8 if momentum is bullish). One step wider if
  stretched up, or if momentum and technicals are both bullish. One step closer (20% at the
  money + 0.6 SD) if stretched down or fundamentals are bearish. Never past 1 SD.
- **Breakout week:** the strike moves above the 5-day high.
- **Ex-dividend before expiry, calls within 2%:** two thirds of the calls (36 of 54).
- **Puts:** half the hedge puts (13) at 0.6 SD, 0.8 if momentum is bearish. None if stretched
  down or in an earnings week.

## Every state

| State | Pick line | Sample facts |
|---|---|---|
| Normal (NKE now) | 0.8 SD | as in the table above |
| Skip the week | Skip the week | IV · skip · "IV rank 22 is under 25" (or "IV 30% is below realised 33%") |
| Earnings week | Earnings week: every call at 1 SD, no puts | Events · earnings · "earnings 17 Dec before the 18 Dec expiry" |
| Ex-dividend cut | 0.6 SD, two thirds of the calls | Events · ex-dividend · "ex-dividend about 1 Dec before the 4 Dec expiry" |
| Breakout | 0.6 SD, above the 5-day high | Breakout · yes · "up 6% in 5 days: sell above the 5-day high $39.20" |
| Stretched down | 20% at the money + 0.6 SD, no puts | History · stretched down · "bottom of the month's range after -6% in 5 days" |
| Reads stale | The usual rule (reads are 6 days old) | reads dimmed or hidden |
| A read changed | any | e.g. Technicals mixed to bullish since last Friday |

Light and dark, 393 wide, as on the phone. Build Blocks live for the tap states.

## Copy

Plain words, short. No em dashes. Never a minus sign on money (red carries it); the
5-day move keeps its sign. Read words lower case as above.

## Data (for the build, not the design)

`writes.names[].read_rule` in the home snapshot: `pick`, `why`, `calls` (54), `of` (60),
`puts` (13), `reads_day`, and `reads.{fundamentals, technicals, iv, history, momentum,
events, breakout}`, each `{read, fact}`. Null for every name but NKE.
