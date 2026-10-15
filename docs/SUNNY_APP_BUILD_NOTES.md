# Sunny app (handoff 18-20): build notes

The new one-page Sunny app, target `Sunny` (bundle `com.sunnyfi.app.next`), installs beside
the old Sunnyfi app. It reads one row, `home_snapshot`, rebuilt every 30 s by `sunny-home`.

## Where things are

| Block | File |
|---|---|
| 01 Status, Updated pill | `ios-app/Sunnyfi/Sunny/Home/StatusLine.swift` |
| 02, 02b Account value and chart | `Sunny/Home/AccountChart.swift` |
| 03-07 Deck, report and theta check receipts | `Sunny/Deck/` |
| 08-09 Quick nav, Today | `Sunny/Today/TodaySection.swift` |
| 10-11 Portfolio, Watchlist | `Sunny/Book/SunnyPortfolio.swift` |
| 12-13 Positions (handoff 22) | `Sunny/Book/SunnyPositions.swift`, `PositionsMath.swift` |
| 14 Inventory, Writes sheet | `Sunny/Book/SunnyInventory.swift` |
| 15-16 Theta, Delta | `Sunny/Risk/SunnyRisk.swift` |
| 17-18 Yield, Payback | `Sunny/Income/SunnyIncome.swift` |
| 19-21, 23 Sold vs Bought, Performance, Allocation | `Sunny/Results/SunnyResults.swift` |
| 22 Insight lines | `SInlineInsight` / `Insight` in `Sunny/Design/` |
| 24 Live glow | `Sunny/Design/SLiveGlow.swift` |
| 25 Refresh | `Sunny/Data/HomeStore.swift`, `Sunny/Home/SunnyRefresh.swift` |

## Where the design files disagreed, and what was built

The UI Kit / phone design wins visuals, Build Blocks wins behaviour (README, Precedence).

1. **Receipt face.** README says Inter only and tokens.md gives the receipt Inter 700, but the
   UI Kit and the phone design print the receipt in IBM Plex Mono. Built in IBM Plex Mono.
   Only Regular and Medium ship in the app, so the receipt's bold lines are Medium.
2. **Screen background.** tokens.md has the gradient only; the phone design's default screen
   ("aurora") adds three soft glows. Built with the glows.
3. **Insight style.** Block 22 says inline under the title. The phone design shows Portfolio and
   Watchlist with the small sun-dot line at the bottom, and every other card with the hairline
   that opens the sentence. Built as the phone design.
4. **Quick nav place.** Block 08 puts it under the deck with Today below; the phone design's
   default puts it after Today. Built as block 08.
5. **Bar charts.** Gallery tiles squeeze W1-W5 into the card; the phone design uses 80 pt
   columns, 40 apart, that scroll and open on now. Built as the phone design.
6. **Card labels.** Gallery tiles title Inventory, Yield and the rest in 20 pt bold; the phone
   design uses the 15 pt grey label. Built as the phone design.
7. **Theta 2× line.** Block 15 says dashed; the design file draws the 2× line solid and only
   Delta's 50% line dashed. Built as the design file.
8. **$0 change on the account chart.** Block 02b says flat is ink; the design file colours zero
   green. Built as block 02b.
9. **Writes rule.** Nik: today's roll sheet (a third at the money, the rest at 0.6 SD, 1 SD
   after a 15% month, 20% at the money with earnings before expiry; puts about 30% of puts
   bought at the nearest strike at or below spot), not the design's 20% / 1 SD / 3% OTM.

10. **Positions chip order.** Block 12 says least room to the short breakeven first. Nik,
    13 Oct: sort by premium size, the open credit on the sold legs, biggest first; names with
    only longs go last. The dot still shows the room; the All chip's dot is the worst name.

11. **Inter's cut.** The design loads Inter from Google Fonts with weights only, so every
    size renders in the text cut (opsz 14). The app set the optical size to the point size,
    which drew big titles and numbers about 4% narrower. Built at opsz 14 everywhere, which
    measures within half a point of the design.
12. **Deck arrow.** The web Inter has no → glyph, so the browser falls back, and the PNG
    screens and the live file draw it differently. Built in Inter, per "Inter only".
13. **Company names.** The design says "the Nike longs" and "39.1% in Nike"; the payload has
    tickers only and every other card uses them ("NFLX reports after close"). Built with
    tickers: "the NKE longs", "34.4% in NKE".
14. **Deck title wrap.** The design balances deck titles ("Time to roll / the NKE longs")
    and keeps subs from ending on one word. SwiftUI has neither, so the breaks are worked out
    in code (SWrap).

15. **Toast.** Built as the UI Kit draws it (44 pt glass pill, green check, 13/600); the phone
    file never shows it and the Build Blocks tile is a dark bar.
16. **Payback %.** One decimal with a trailing .0 dropped ("42%", "18.6%"), as the phone file
    rounds it.

17. **App icon (handoff 21).** Built as an Icon Composer file, `Sunny/App/AppIcon.icon`, from
    the layer SVGs: light, dark (with the glow) and tinted (rays and horizon at 55%). Group
    translucency is off and the glow has no glass, or the orange washed out and the glow
    showed a glass rim. Checked with Icon Composer's ictool renders against the PNGs.

18. **Story line (block 22).** Not built. Nik, 13 Oct: the account value replaced it, so the
    rotating line under the header is not wanted.

19. **Theta line 3×, not 2×.** Nik, 13 Oct 2026, after the risk-bands backtest
    (research/risk-bands, untracked): under the roll sheet 2× fired on under 1% of weeks;
    below 3× on the app's gauge most following months lost money. The line, the "below/above"
    words, the red number and the theta check's ratio trigger all use 3×
    (`SunnyMountain.thetaLine`, `THETA_LINE` in sunny-home). The Delta band stays 20% to 50%:
    the rule writes about 41% and 30% to 40% tested best; a high reading means the LEAPs lost
    delta, and the fix is rolling them deeper, not selling fewer calls.

20. **Account value vs IBKR: left as is.** Nik, 13 Oct 2026. Sunny runs about $300 to $400
    off IBKR's app during the day: about $110 in the starting close (IBKR statement close vs
    the app's prior close, probably accrued interest), and option prices (we use the bid/ask
    middle; IBKR its own mark, worst on wide LEAP spreads), plus up to a minute of lag.
    Unrealized differs by design: the glossary counts open shorts at full value and keeps
    their open premium apart (about $7.3K), where IBKR nets shorts against their sale price.

21. **Picked week or month.** Nik, 13 Oct 2026: the grey box moves to the picked column and
    nothing else changes; the other columns are not dimmed (block 14 says "other weeks fade").
    Month view starts at the book's first month (Sep 2026) and opens on now; the back arrow
    stops at the book start. A positions strike opens on Today, not Exp. Performance's month
    chips start in September too; the LEAPs bought on 31 Aug count in September.

22. **Portfolio and Watchlist tap states.** Nik, 13 Oct 2026: % change, then the stock's $
    change per share, then the current price, on both. Block 10 had Portfolio's $ as the
    move's effect on the book. The summary line is about the stocks too: the biggest gainer,
    the biggest loser, then the next biggest move, by % ("NKE up 1.8%. BABA down 0.5%, ...").
23. **Period arrows at Apple's size.** Nik, 13 Oct 2026: the design's 28 pt arrows read too
    small next to iOS's own back buttons. Built as 44 pt glass circles with a 17 pt semibold
    chevron, 8 apart; the Writes sheet back button matches (design 40 pt).

24. **Payback = made vs the LEAP cost.** Nik, 13 Oct 2026, replacing block 18's two lines: the
    target is what the LEAPs cost (time value plus intrinsic when bought, $214K), drawn as a
    line on top; "made" is everything realized since the first LEAP (sold premium, puts and
    calls bought, shares, any close) plus the premium in hand on open shorts, and it climbs to
    the target at the last five weeks' pace, dotted to a date. Intrinsic is not in it.
    sunny-home: series rows carry `all_real` and `held`, plus `pace_made` (v29).
25. **Inline insight edge to edge.** The line and the opened gradient run to the card edges, as
    the design draws them; a clip after the negative padding had cut them to the text margins.

26. **All positions card.** Its own height, not stretched to the ticker cards: a small gap
    under the title, room at the bottom (Nik, 13 Oct 2026).

27. **Glass cards (trial).** Nik, 13 Oct 2026: the glance cards (Inventory, Yield, Payback,
    Sold vs Bought, Allocation) take the Theta and Delta glass; Positions ticker cards,
    Performance, Portfolio and Watchlist stay on the design's paper. One switch,
    `S.glassCards`, puts them all back on paper; per card, `sCardSurface(glass: false)`.
    Tried and turned off the same day (Nik: "go back to how it was"): `S.glassCards` is false.

28. **Deck swipe.** A UIKit pan that only takes sideways drags (`DeckSwipe`), not a SwiftUI
    DragGesture: a drag starting on the deck held the page's vertical scroll (Nik, 13 Oct 2026).

29. **Positions redesign (handoff 22), both styles.** Five pages: All, Sold (Bar), Sold (Chart),
    Bought (Bar), Bought (Chart); Nik uses both and picks one later (13 Oct 2026). The old
    per-ticker chips, payoff chart, time strip, page dots and Combined card are deleted (Nik:
    delete), and with them decisions 10 and 26.
30. **"to" and "past".** Block 13's text says "to" when the strike is on your side; the
    component and the pictures say "to" until the price reaches the strike and "past" once it
    crosses (red on sold, green on bought). Nik: match the pictures.
31. **Chart data.** Hourly closes 10:00 to 16:00 New York from our own 30 s quotes
    (`hourly_closes()`, the last quote at or before each full hour), not a new feed; Nik chose
    hourly over 15-minute points. Until 9 Oct the quotes ran 15 minutes late, so those days read
    15 minutes after the hour (checked against Yahoo's 15-minute bars: mean gap 0.03-0.07%).
    The line joins across any hour with no quote (Nik: a break "looks odd"; our feed missed the
    morning of 12 Oct). Holidays never show: only trading days count.
32. **All card spacing.** 32 under the header, 28 between totals, 36 at the bottom, not the
    design's 24 / 20 / 28 (Nik: "feels too cramped").
33. **Glow tint.** Block 13 says the glow follows the nearest strike; the component takes the
    worst strike on the card. Built as the component, so a crossed strike always shows red.

34. **Theta check growth rule: smoothed and sized.** Nik, 13 Oct 2026, after KR's one LEAP
    was told to roll on noise ($0.27 a day on 14 Sep against $0.72 now, +167%, while its theta
    bounced between $0.18 and $0.78 day to day on a thin deep-ITM quote; 0.4% of the book's long
    decay; book ratio 7.8x). Growth now compares 5-session averages, and only a LEAP carrying 10%
    or more of the book's long decay can flag on growth. The ratio trigger is unchanged. Replayed
    on 13 Oct: nothing flags (NKE's single-day jump of 47% is 18% smoothed). KR's card was
    resolved as a false alarm.

35. **Theta check on one basis.** The ratio trigger, "without this LEAP" and the roll's
    before/after are all the 2-week ratio (the Theta card's number, the 3x line's basis); they
    had mixed in the single-day ratio, which swings through the week. The receipt says "back
    to" only when the roll lifts the book. Admin test mode: `{"mode":"theta_check","dry":true,
    "price":"*"}` runs the check now, writes nothing, and prices every LEAP's roll (13 Oct).
36. **All card taps cycle the number.** Tap a total: time value, %, $, shared with every page,
    as before the redesign (Nik, 13 Oct 2026); the design's jump to that side is gone, the chips
    navigate.
37. **Loss, not gain; lost, not kept.** Red says so in words: a bought side or card that is
    down says "loss", a sold one "lost" (Nik, 13 Oct 2026: "when it's red don't call it gain").
    "captured" and "return" stay. Only Positions used these words.
38. **Chart scale zoomed on the strikes.** Fit to the strikes and the price with a 2% minimum
    span (design 6%), and the week's line may widen it by a quarter at most (design half);
    beyond that it clips. The strikes sit well apart; a big move widens the scale (Nik, 13 Oct).

39. **Bar axis zoomed on the strikes.** At least 1% either side of the price, not the design's
    3%, so close strikes sit apart and their labels stop colliding (NFLX 71 / 72 / 72.5 now three
    tidy rows). The axis still widens to every strike and the price (Nik, 14 Oct 2026).
40. **Roll strike stays on delta alone.** Asked whether to require open interest of 100+ for the
    suggested roll's strike (KR 57.5 had OI 1); Nik: keep delta only (14 Oct 2026).

41. **Chart line colour = the week shown.** Green when the card's legs made money over the five
    sessions on the chart, red when they lost (Nik, 14 Oct 2026: a LEAP rising all week drew red
    because it is still down since bought). The footer and the Bar fill keep since-opened. Each
    leg carries `mark_wk`, its mark at the close before the first session (sunny-home); a leg
    opened inside the week starts from its opening price.
42. **Inventory sheet swipes.** One card per ticker side by side, snapping one at a time, as tall
    as the card on screen; the chips follow and stay in view (Nik, 13 Oct 2026). Back by swipe
    now starts at the left edge only, so swiping right on a card goes to the previous ticker.

43. **Live pulse on the Chart dot.** While the market is open (9:30 to the close, New York), a
    soft ring in the line's colour grows from the dot to 2.8x and fades in 1.6 s, rests 0.4 s and
    repeats; off outside the session and with Reduce Motion (Nik, 14 Oct 2026; not in the design).

44. **"Positions updated" only on trades.** The toast fired whenever any leg's mark moved half a
    cent, so every tick in market hours; now only when a leg is bought, sold, closed, expires or
    changes size (Nik, 14 Oct 2026: "just noise"). Its slide animates the toast alone: on the
    page it also animated every card change from the same update, and the cards jumped.

45. **15 s updates in the regular session.** Nik, 14 Oct 2026 (the 10 s idea, parked the day
    before, came back as 15 s). 9:30 to 16:00 New York: mp-refresh prices four times a minute
    (:00 :15 :30 :45 from its start), sunny-home rebuilds just after each (:06 :21 :36 :51), the
    app fetches at :08 :23 :38 :53. Stock and option prices move together (same pass), so time
    value stays right. Storage unchanged: only the :00 and :30 passes append to option_greeks
    and ticker_quotes; the passes between write the live tables. Outside the session: every 30 s
    as before. The glow keeps its 30 s rhythm. Checked live: passes 1.3-1.7 s, builds 0.2-0.4 s,
    marks equal to IBKR's bid/ask middle on four legs.

46. **Watchlist: SPCX, TSLA, APP added.** Eight names (Nik, 14 Oct 2026): the Yahoo feed
    (market-tape) and sunny-home's list; more than five tiles fill even rows (4 + 4).
47. **Write rules from research.** TSLA: 3% out of the money on 70% of the LEAPs; SPCX: 5% out
    on 50%; Inventory counts each full at that share (`WRITE_RULES`, docs/TSLA_SPCX_RESEARCH.md).
    Dormant until the names are held; every other name keeps the roll sheet.
48. **Positions cards keep their order.** Still safest first, but read from the insight words'
    copy, so they re-sort on open, pull to refresh and after the close, never on the 15 s
    tick (Nik, 14 Oct 2026: moving "all the time"). Numbers stay live.

49. **Yield legend in dollars.** Calls sold, Calls closing cost, Puts sold and Puts closing cost
    always show dollars (Nik, 14 Oct 2026: the hero already gives the %): plain dollars when the
    hero is %, the mode's own dollars (time value) otherwise.

50. **Chart picked, Bar removed.** Nik, 14 Oct 2026, after a day with both: Positions is three
    pages, All · Sold · Bought, every ticker card in the Chart style. The Bar pages, their
    geometry and motion are deleted (decisions 39 and the Bar half of the audit no longer
    apply). Debug preset `pos.page`: 0 All, 1 Sold, 2 Bought.

51. **Period cards open on now.** Yield and Sold vs Bought: with nothing tapped, the numbers
    follow the grey box, this week in Week view and this month in Month view (Nik, 14 Oct 2026:
    Week showed October's total until W3 was tapped). Inventory unchanged: its untapped number
    is already now.
52. **Chart tags carry the contracts.** `72 ×6 2.1%`: strike, contracts at it, distance (Nik,
    14 Oct 2026); the tag column is 77 wide (design 65), the plot 12 narrower.
53. **Footer: collected (or paid) first.** Four figures: collected · time value · captured ·
    kept on Sold, paid · time value · return · gain on Bought; collected = kept + time value
    still in the option (Nik, 14 Oct 2026).
54. **Planner (block 14b, handoff 23) replaces the writes page.** `SunnyPlanner` +
    `PlannerMath` (Book/). Every Inventory chip and the deck's earnings card open it.
    - **Starting plan = the engine's pick** (the roll sheet: a third ATM, rest 0.6 SD, 1 SD
      after a 15% month, 20% ATM with earnings; TSLA 3% out on 70%, SPCX 5% out on 50%; puts
      30% of the puts bought, nearest at or below spot), not the prototype's 0.6/1 SD split.
      An untouched name follows the engine live; once edited, the plan is kept per name and
      Friday until the app closes (`HomeRouter.plans`).
    - **Next Friday**, the writes rule. Caps: calls = LEAPs held less calls sold for that
      Friday; puts = all puts bought less puts sold (Nik, 14 Oct 2026).
    - **Live chain**: `chain-next` with `{ticker, expiry}` returns every listed strike to about
      2.2 SD with live mid and Black-Scholes delta; polled every 15 s in the regular session (60 s
      otherwise) only while the Planner is open; held still while a slider is held. The chain
      IV already carries a report, so no extra 1.5x for earnings.
    - **Stops**: the first listed strike at or past the money, then the listed strike nearest
      each 0.2 SD step to 1.4 SD, kept strictly apart. Where strikes are a dollar apart on a
      low-vol name (KR) "strictly apart" walks past 1.4 SD (KR's stop 7 is about 2.1 SD; the
      label shows the true SD).
    - **Axis squeezed**: the days to next Friday share the design's three sessions of width
      (Nik, 14 Oct 2026); day labels need 30 pt, today, the report day and Friday keep theirs.
    - **"By Oct 23"**, not "By Fri", in the header, insight and fully-sold line: "By Fri" means
      this Friday on Positions (Nik, 14 Oct 2026).
    - **Zoomed scale** (Nik, 14 Oct 2026: "breathing room between strikes"): fitted to the
      price and every sold and planned strike (the Positions rule) and always the whole week,
      as the design did; replaces the design's fixed 1.5 SD. Positions' quarter-stretch cut
      most of PEP's week off. Rescales glide with the plan.
    - **Pulse** on the price dot during the regular session, as Positions (Nik, 14 Oct 2026).
    - **System slider**: iOS 26 `Slider` with `step`, a `tick` per stop and `neutralValue`
      (puts fill from the right). Its ticks sit under the track, not on it as drawn; its thumb
      is the system capsule and glass lens. A tap on the track jumps to the nearest stop.
56. **Planner swipes between names** (Nik, 14 Oct 2026: "like before"): the chart cards sit
    side by side and snap one at a time, the chips follow; the strikes below are the name on
    screen's and rise in again. The cards slide, so they no longer also rise (a change from
    the block's entrance); each card's week still draws in as it appears.
57. **Reset** (Nik, 14 Oct 2026): a glass "Reset" capsule beside Add, shown only once a name's
    plan was changed; it goes back to the engine's pick, live.
58. **Call / Put readable** (Nik, 14 Oct 2026: "hardly readable"): the side a strike is on is
    filled in its colour (green call, blue put, as its dot and chart tag) with paper text, 13
    semibold; the other word is ink. Replaces the design's white pill on glass.
59. **Week ↔ Month animation** (update 14 Oct, `week.md`). One shared sequence in
    `PeriodState.flip`: the thumb slides at once (`S.thumb`, overshoot); Out: bars shrink
    (0.7 s standard), the hero fades and drops 6 pt and the value labels fade (0.15 s); at
    240 ms the data, labels and scroll swap with no animation (a new row, already on now:
    now 32 pt in from the right, a past period at the start), bars at 0; 32 ms on, In: bars
    grow 0.7 s, hero back after 0.2 s (0.5 s), labels after 0.5 s (0.4 s). The last tap wins;
    Reduce Motion swaps at once; ‹ › morphs heights 0.7 s with no Out. In Inventory and Yield
    (`SBarChart`) and Sold vs Bought (its own chart, now with label room on both sides so its
    height holds). Payback, Performance and Allocation have no Week | Month here.
    Measured (430 sim): bars 89% down at 240 ms, swap clean, grow 0.7 s, hero +0.23 s, labels
    +0.5 s; the In starts about 45 ms late in the simulator (the swap's redraw). A bar label's
    fade is scoped to opacity: value-keyed, its delay also held the label behind its bar.
60. **Put overlay in the Planner** (Nik, 15 Oct 2026, after the ITM-put forward test,
    `research/itm-puts`, page "LEAP Put Overlay Test"). He buys the long puts himself (March
    2027, strike nearest 8% above the price, on half the LEAPs). For NKE, LULU, BABA and NFLX
    (`PUT_RULES` in sunny-home) next Friday's put write is now half the puts bought, rounded
    half up (NKE 30 -> 15, BABA 7 -> 4), at the highest strike at least 2% below spot, never
    above the lowest long put still open that Friday, so every short put is covered. No
    covering long put, no put suggestion. Other names keep 30% at the money. Calls unchanged:
    the roll-sheet split is what the test used. Server only (sunny-home build 2026-10-15.1);
    the Planner already starts from the engine's pick.
55. **Speed (Planner audit).** `SType.uiFont` now caches each Inter size/weight/tnum (a
    variable-font descriptor per Text per redraw was the app's top cost); `MarketClock.addDays`
    keeps one formatter. The Planner reads its name from the router, not a Binding, so a Home
    redraw no longer redraws it. The live pulse runs on Core Animation: as a SwiftUI keyframe
    animation inside glass it held the app near 80% CPU.

## Planner audit (14 Oct 2026)

Against `blocks/14b-planner.md` and `reference/SunnyPlanner.dc.html`, 430 and 393, light and
dark, live chains saved for repeatable numbers (`-preset planner.chains=<dir>`).
- **Numbers by hand**: NFLX 71×3 + 75×14 = $858 + $2,044 = $2,902, delta 685 → 111; BABA
  112×5 call + 110×1 put = $1,120 + $212 = $1,332, delta 404 → 221. App equal to the dollar.
- **Rules** (35 checks, compiled against the app's own code): caps, over-typing gives way
  biggest first to 1, quantity 0 → 1, strike snaps to listed and clamps ATM..1.4 SD, side
  switch keeps the stop and takes what is free, a full side does nothing, Add takes a free
  side calls first then splits the biggest one stop past the farthest, four is the most, fully
  sold adds nothing, earnings in/out of the week. All pass.
- **Motion** (recorded, fitted): card fade 0.525 s (spec 0.5), rise 0.6 s on the standard curve,
  strikes +92 ms (spec 80), line from +0.1 s over 0.9 s, dot from 0.85 s over 0.3 s. Reduce
  Motion: the name changes in one frame.
- **Fixed in the audit**: Call/Put halves overlapped their tap areas (a tap on Put after the
  switch landed on Call and switched back); the selected half greyed out; the Done button
  covered the field being typed in (the row now rises to the middle); a value-keyed animation
  on the chart scale looped the render and blanked the screen; the fade's animation also drove
  the rise (stacked value-keyed animations: the inner wins; the fade is now scoped); the
  entrance waited up to seconds behind slow redraws (fonts, above).
- **Differs from the design, by choice**: system slider ticks below the track; ATM line at the
  price (the prototype draws it at its snapped ATM strike); next Friday axis and date label;
  zoomed scale; pulse.

## Positions audit (13 Oct 2026)

Fixed: the chip row cut the glass shadows (a gray band, also in the old Positions); opening on
the last page at 430 wide landed between pages (the pager started at 393 wide); cards did not
rise and the thumb, pill and caret did not slide (offsets in a body-scoped animation jump; now
value-keyed); chart points on the delayed-feed days. Matched by overlay at 393: chips, All card,
page top, Bar and Chart cards to about 1 px at 2x. Totals checked against the legs by hand.

Open, for Nik: (1) close strikes on the Bar: the design's label rule could run out of rows (NFLX
71, 72, 72.5 dropped the 72.5 label seven rows); decision 39's zoom fixes NFLX, but five strikes
a point apart can still crowd; the Chart handles it. (2) Contrast: some small coloured text on the glass is
under 4.5:1 with the design's own colours (light: muted on a tinted corner 3.9, gold/red/green
labels 3.9-4.4; dark: red 3.9-4.5).

## Still open

- **Launched (13 Oct 2026, step 2).** Sunny took over `com.sunnyfi.app` at 2.0 (3) and replaced
  the old Sunnyfi app on Nik's iPhone in place; the `.next` test copy was removed. Signed with
  the existing Xcode-managed profile "iOS Team Provisioning Profile: com.sunnyfi.app" (push,
  development, until Jun 2027). The old Sunnyfi target moved to `com.sunnyfi.legacy`, its code
  kept for now. The app re-registers for push on every launch when alerts are allowed.
- **Faster updates.** 15 s in the regular session since 14 Oct 2026 (decision 45). Watch the
  Theta server on Fly.io (shared-cpu-1x, 1 GB) and the database load over the first days.
- **Live checks.** The 30 s tick, the glow and the toast need a look during market hours.
- **Last week (block 09).** `index_weekly` was empty because sunny-home went live after the
  last weekend. Admin mode `last_week` filled Oct 5 - 9; next Friday after the close is the
  first real run.
