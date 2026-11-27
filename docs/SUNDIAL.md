# Sundial 1.0

The selling engine. Agreed with Nik on 25 Nov 2026, one rule at a time. Names: **NVDA and SpaceX (SPCX), both in
book N**, same rules for both (Nik, 25 Nov). The rest of the names come after.

**Nik decides what to buy** (shares, calls, puts). **Sundial decides what to sell**: how many calls and puts,
on which expiry, at which strike. It can also show what a purchase would unlock ("5 Jan calls bought = 8 more
calls you can sell"), but buying stays his call.

---

## Calls

1. **When and which expiry.** At 3:45 PM ET every Monday, Wednesday and Friday, sell on the expiry a week out.
   Three expiries are always open.
2. **Strike.** The 11 Nov tables: the week's move in weekly SD (against the close 5 sessions back), the trend
   (50-day and 200-day), then IV rich (0.25 SD closer) or cheap (0.25 SD wider). **Cheap wins whenever NVDA's
   20-day real moves are bigger than its IV.** Calls stay between 0.25 and 1.25 SD; at the money only on a
   20% up day.
3. **How many: the +20% test.** The most calls that keep the whole NVDA book from losing money at any rise
   from 0 to +20%, at any close in the next 5 trading days. "The whole book" is shares, calls bought, puts
   bought and everything sold. Sold legs count in full (their premium is the cushion). Bought legs count only
   what the move does to them, not their slow daily decay (that is the cost of protection, not of the rally).
   Applied every week ("20% in a week is normal for NVDA"). Past +20% a loss is accepted.
   **Cap: no expiry takes more than half** the calls the test allows a book with no calls sold (25 Nov, from data:
   uncapped, the room piles onto one expiry after an early close).
4. **Early profit.** If a call is worth half or less of its sale price at 3:45 PM on its first or second
   trading day, buy it back. That expiry stays empty until the next normal sale.
   After day 2, hold to expiry, even at 90% kept (27 Nov, from data: closing on the last day pays the ask for
   very little risk, and holding never delays the next sale, since calls expiring that day take no room).
5. **In the money before expiry: hold.** No early roll or close.
6. **In the money at expiry:** buy back and sell again. Shares are let go only from lots held over a year.
7. **Earnings weeks: no calls** on any expiry that spans an NVDA report.

## Puts

8. **Normal.** 2 puts on each new expiry (a week out) at 3:45 PM on Monday, Wednesday and Friday, strike from
   the 11 Nov put table. Earnings weeks: 1 SD.
9. **Big drop.** When NVDA falls 2 daily SD below yesterday's close (daily SD = IV / square root of 252; about
   9% at 71% IV), checked **live every minute**, sell puts up to the cap on the expiry a week out, strike from
   the put table at that price. Nik gets a push.
10. **Cap.** Never more than **30 sold puts open** (3,000 shares), counting every open sold put.
11. **In the money before expiry: hold.** At expiry: take the shares if the strike is under the average cost,
    otherwise buy back and sell again.
12. **Early profit: none.** Puts are held.

## Calendar

13. Quiet months (August, late December) and holiday or half-day weeks: **sell as normal.**

---

## The evidence (all 25 Nov 2026)

Model prices (Black-Scholes, no skew). IV before July 2026 = 20-day real moves x 1.10, the median ratio of
NVDA's real IV to its real moves in Jul to Nov 2026. Money scaled to NVDA at $150. Monday, Wednesday and Friday
expiries assumed since 2010. Earnings days = the busiest day of each Feb, May, Aug and Nov.

| Question | What we tested | Result |
|---|---|---|
| Replay 16 to 25 Nov | Sundial against Nik's real trades, same purchases | Sundial -$21K, Nik -$29K (sold legs). Calls equal, big-drop puts +$13K against +$3K |
| Calls in the money early | 187 up-jumps of 2 daily SD since 2010 | Hold -$11.2K a jump, close and resell -$10.4K to -$10.8K, roll -$11.4K. Holding best on 20% days |
| Early profit | 2,387 call slots, 50% kept in the first 2 days | Close only +$1,089 a hit, hold +$861, close and resell closer +$720. Puts: no difference |
| Puts in the money early | 156 falls of 2 daily SD since 2011 | Hold -$5.9K, close at the close -$5.9K, roll -$5.0K but worst -$83K against -$54K |
| Why calls lost | 2,387 slots over 16 years | Normal weeks +$345K, earnings weeks -$689K |
| Earnings weeks | 185 expiries over 68 reports | Calls only -$282K, equal calls and puts -$182K, puts only at 1 SD +$117K (at 1.6x normal IV) |
| Quiet months | By month and holiday weeks, priced by trading days | Half-day weeks best (calls +$950, puts +$883 an expiry). Late-December calls weakest (-$714) |
| Late close (27 Nov) | Legs at 90% kept or more at the close the day before expiry, earnings weeks out. Real Theta quotes since 2016 (268 calls, 306 puts), model since 2010 (984 calls, 1,402 puts) | Hold wins. Real calls: close at the ask $14.6K, hold $3.5K (paid out 3 times, worst $1,706). Real puts: $14.9K against $5.6K. Model calls: hold better by $24K to $43K. Same at 80% and 95%, every period, every expiry day |
| Very cheap NVDA | Chance of a 20%+ week by distance from the 52-week high, since 2010 | About 1 to 2 days in 100 at every level. No special rule |

**SpaceX check (25 Nov, real Theta end-of-day prices since the 12 Jun IPO, 10 contracts an expiry at SPCX $127).**
Every rule held except the 50% early close, which lost $4.9K over 17 cases against holding while SpaceX fell from
$161 to $127; Nik kept it for one rule on both names (SpaceX rose 23% in its August earnings week).

| Rule | SpaceX since June |
|---|---|
| +20% test | 20%+ within a week on 3.6% of days; a 1-in-20 week +19%; weekly SD 8.7% |
| Calls ladder | +$48K over 29 expiries, 3% paid out; Mon/Wed/Fri +$26.5K vs Fridays only +$24.8K (Oct to Nov) |
| Puts ladder | +$6.3K (Oct to Nov -$0.3K) |
| Calls in the money after a jump (4) | hold +$14.0K, close -$4.4K, roll +$11.0K |
| Puts in the money after a drop (2) | hold -$6.1K, close -$8.6K, roll -$5.9K |
| Earnings (2 reports) | calls -$3.1K in August's week (+23%), puts +$5.1K |
| Big drop | fired 8 times, including 20 and 25 Nov |
| Late close at 90% (27 Nov) | calls: close better by $2.1K over 16 cases, all from one +7.4% day (2 Oct); puts: hold better by $773 over 14. Too few to change the rule |

**Decided from data the same night (NVDA since 2010, model prices):**

| Question | Result |
|---|---|
| Expiry cap (1,500 shares, test-sized, early close on) | No cap +$284K, worst week -$88K, worst expiry -$88K. Half +$328K, -$61K, -$42K. A third +$272K, -$55K, -$26K. A quarter +$229K, -$46K, -$21K. Half chosen: most profit, bad weeks well under no cap |
| More room: bigger 3 expiries or a 4th (about 9 days)? | 40 calls open either way: 3 expiries +$404K (+$23.7K a year), 4 expiries +$252K (+$14.9K). Sell more on the same 3 |
| After a jump, sell puts 1.5 SD below (after a drop, calls above) | 175 jumps: same count as the in-the-money calls -$22K; premium-matched (about 5x the contracts) -$244K, worst -$146K. 142 drops: -$49K and -$211K. Not adopted: snap-backs hit the extra legs |

Scripts are in the session scratchpad (engine/, replay/, rolltest/); re-run before relying on a number.

## Next names (agreed 27 Nov 2026, not built yet)

**Sunny's six (book S): BABA, FIS, NFLX, LULU, NKE, UBER.** Sundial replaces the 20 Oct call rule (at the money on
every 100 shares plus 1.5 SD hedge calls). One expiry: each Friday at 3:45 PM for next Friday (Nik tried a smaller
second week too, then: "just do it weekly"). Each name's own test size, the same safety as NVDA's +20% (its 1-in-100
week outside earnings, x1.24): **NKE +11%, FIS +11%, NFLX +20%, LULU +17%, BABA +20%, UBER +19%.** LEAPs and other
bought calls count by what a rise does to them.

**Agreed 27 Nov (Nik's read, then the data):** FIS is **off** (no calls, no puts; the shares just sit). NFLX and UBER test
at **+15%** (Nik: they rarely jump more than 10-12% a week; a smaller test sells MORE calls, so +12% would sell 15-17 a
week; return against worst week is the same at +12, +15 and +20%). **Earnings weeks: sell nothing** (calls lost -$122K
to -$265K over the six by rule, puts at 1 SD -$34K). **Weekly puts** at the put table's strike (about 0.9 SD), outside
earnings weeks: **NFLX 10, UBER 10, BABA 4, LULU 6, NKE 5** a week (per 10 since 2016: NFLX +$56.5K, UBER +$55.2K, BABA
+$72.2K, LULU +$34.9K, NKE +$3.9K; assigned about 1 week in 6). **No 50% early close** on the weekly names or TLT
(27 Nov test, Sundial's weekly calls since 2016: holding +$254K, closing at the mid -$27K less, at the ask -$64K less;
only NFLX gained, +$2.6K at the ask). NVDA and SPCX keep theirs.

**Built 27 Nov (sundial v11, build 2026-11-27.7):** every name carries its own settings in `NAMES` (cadence, test size,
puts, put cap, earnings rule, early close, big drop). Sunny's board shows NFLX, UBER, BABA, LULU and NKE; Nicolay's adds
TLT; Together shows all. A signed-in user sees only the books they own.

| Since 2016, real prices, per 1,000 shares, earnings weeks out | Today's rule | Sundial |
|---|---|---|
| NKE | -$2.3K | +$7.1K |
| FIS (218 weeks) | +$16.7K | +$23.6K |
| NFLX | -$35.5K | -$8.2K |
| LULU | -$9.6K | +$68.3K |
| BABA | +$95.7K | +$115.4K |
| UBER (since 2020) | +$25.5K | +$31.3K |

Losing weeks 15 to 21% against 24 to 35%. Sundial sells about 13 calls about 0.75 SD out, so its worst week is a little
bigger; today's rule won only BABA's 2021-23 fall.

**TLT in Nicolay's book (book N), replacing IWM.** 1,000 shares building to about 5,000. **Weekly at +6.5%, no richness
gate** (Nik, 27 Nov). TLT's 1-in-100 week is +5.3% since 2003. Real prices: weekly calls -$1.7K in 2016-20 (rising),
+$25.3K in 2021-23 (falling, shares -$30.6K), +$8.1K in 2024-26; weekly beat Mon/Wed/Fri since 2024 (+$8.1K against
+$6.3K); the gate lowered every period. Forward 3 years at real option prices (IV about real moves): Nik's view (72, then
110) calls +$0.5K middle path, flat +$7.9K, early rally +$3.4K, keeps falling +$10.8K (per 1,000 shares).
**Puts (Nik, 27 Nov): 10 a week** at the put table's strike, plus extra on a big down day: **10 when TLT falls 2 daily
SD (about 1.5%), 20 in all when it falls 3 daily SD (about 2.3%)**, inside the cap; assignment is how the position grows. **Cap: open puts never exceed the shares still wanted** (5,000 less held;
40 puts at 1,000 shares). History: weekly TLT puts about break-even (+$0.3K per 10 over 530 weeks, shares in at $119.47
against a $117.85 average); drop puts +$1.5K over 37, shares in at $113.10.

The test now checks up to each name's own size (fixed 27 Nov: it used to check to +20% whatever the size; NVDA and
SPCX are unchanged).

## Checks (built 27 Nov 2026)

Two layers watch the engine. Both push Nik only when they find a problem.

- **The check, 10 AM, 12 PM, 2 PM and 4 PM New York** (`sundial` mode `audit`, table `sundial_audits`, cron
  `sundial-audit`). Rebuilds every name's book from IBKR's trades a second way and checks the board is not over or
  under suggesting: calls inside the test, puts per expiry and under the cap, drop puts inside the day's total.
- **The inspection, once a trading day at a random time** (`sundial-inspect`, table `sundial_inspections`, cron
  `sundial-inspect`). Picked from the date between 10 AM and 30 minutes before the close. Shares no code with the
  engine: its own option maths, data reads and count search, and the rules typed again from this page. Checks every
  name: settings as agreed, data fresh, book delta positive now (and what +1 weekly SD does), the reads, the drop
  lines, earnings, strike distances, the chain IV and strikes, the counts and the credit. `{"force":true}` runs it now.
- Next: a short written review each day by Claude, reading both.

## Not yet

- Built 25 Nov: `sundial` edge function, `_shared/sundial.ts`, `sundial_runs`, scheduler `sundial-tick` (every minute in the session; plan at close minus 15). Pushes go to Nik's login only.
- The Income page redesign reads Sundial's answer ("To sell", "Bought back"), once built.
- Other names after NVDA.
- Bug seen: sunny-home `risk.delta` counts only LEAP contracts as shares, so book N's 1,500 real NVDA shares
  are left out of the delta card.
