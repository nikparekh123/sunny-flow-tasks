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
| 12-13 Positions | `Sunny/Book/SunnyPositions.swift`, `PositionsMath.swift` |
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

## Still open

- **App icon.** The new target has no icon yet.
- **Push.** apns-deliver sends to `com.sunnyfi.app` devices only, so alerts keep going to the old
  app until the new one takes that bundle id at ship.
- **Live checks.** The 30 s tick, the glow and the toast need a look during market hours.
