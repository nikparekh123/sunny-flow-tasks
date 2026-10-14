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
37. **Loss, not gain.** A bought side or card that is down says "loss" (Nik, 13 Oct 2026:
    "when it's red don't call it gain"). Only Positions used the word.
38. **Chart scale zoomed on the strikes.** Fit to the strikes and the price with a 2% minimum
    span (design 6%), and the week's line may widen it by a quarter at most (design half);
    beyond that it clips. The strikes sit well apart; a big move widens the scale (Nik, 13 Oct).

## Positions audit (13 Oct 2026)

Fixed: the chip row cut the glass shadows (a gray band, also in the old Positions); opening on
the last page at 430 wide landed between pages (the pager started at 393 wide); cards did not
rise and the thumb, pill and caret did not slide (offsets in a body-scoped animation jump; now
value-keyed); chart points on the delayed-feed days. Matched by overlay at 393: chips, All card,
page top, Bar and Chart cards to about 1 px at 2x. Totals checked against the legs by hand.

Open, for Nik: (1) close strikes on the Bar: the design's label rule runs out of rows (NFLX 71,
72, 72.5 drops the 72.5 label seven rows and its tick crosses the 72 label; five strikes a point
apart overlap); the Chart handles both. (2) Contrast: some small coloured text on the glass is
under 4.5:1 with the design's own colours (light: muted on a tinted corner 3.9, gold/red/green
labels 3.9-4.4; dark: red 3.9-4.5).

## Still open

- **Launched (13 Oct 2026, step 2).** Sunny took over `com.sunnyfi.app` at 2.0 (3) and replaced
  the old Sunnyfi app on Nik's iPhone in place; the `.next` test copy was removed. Signed with
  the existing Xcode-managed profile "iOS Team Provisioning Profile: com.sunnyfi.app" (push,
  development, until Jun 2027). The old Sunnyfi target moved to `com.sunnyfi.legacy`, its code
  kept for now. The app re-registers for push on every launch when alerts are allowed.
- **10 s option prices (parked).** Scoped 13 Oct 2026; Nik parked it: revisit in November with
  the Theta stock prices, so stock and option prices speed up together.
- **Live checks.** The 30 s tick, the glow and the toast need a look during market hours.
- **Last week (block 09).** `index_weekly` was empty because sunny-home went live after the
  last weekend. Admin mode `last_week` filled Oct 5 - 9; next Friday after the close is the
  first real run.
