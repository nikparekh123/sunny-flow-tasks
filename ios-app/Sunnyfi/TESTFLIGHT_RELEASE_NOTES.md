# Sunnyfi v1.0 — TestFlight Notes

Welcome to Sunnyfi! This is our internal options & positions monitor for the Sunny WM book. The first TestFlight build covers the **Trades**, **Activity**, **Performance**, and **You** tabs. Home and Hedge are getting rebuilt and will land in a follow-up.

## What's in this build

- **Trades tab** — feature-complete
  - Unified per-ticker cards (header → greeks band → Shares → Options)
  - Open Call Credit / Open Puts Bought carousel (swipe left/right at the top)
  - Ticker filter pills (All + per-ticker)
  - Trade pill bottom-right → Option / Shares
  - Swipe a leg left → Edit (yellow-grey) or Close (red)
  - "Likely assignment · log it" CTA on ITM short calls past expiry
- **Activity tab** — date-grouped trade ledger with Open / Closed filters
- **Performance tab** — Gains & Losses chart + Leaderboard
- **You tab** — account & settings

## Quick start

1. Sign in with the magic-link email
2. Tap the **Trade** pill bottom-right → Option to log your first short call
3. Pull-to-refresh on the Trades tab pulls fresh greeks
4. Swipe-left on any open leg to Close it (or Edit if you logged it wrong)

## What we'd love you to test

### Critical paths
- [ ] **Log a new option** — Trade pill → Option, fill it out, tap Review then Confirm
- [ ] **Log new shares** — Trade pill → Shares
- [ ] **Swipe-close a winning short call** — verify "Estimated profit" line is positive
- [ ] **Swipe-close an expired-worthless option at $0** — Fill price stays $0, Review enables, Confirm logs the close
- [ ] **Swipe-edit a leg** with a typo — fix the expiry or strike, verify the card updates
- [ ] **Pull-to-refresh** on the Positions tab
- [ ] **Pre-fill from filter** — tap a single-ticker pill (e.g. META), tap Trade → Option, ticker should already be META
- [ ] **Carousel swipe** at the top of the All view — Calls Sold ↔ Puts Bought

### Edge cases
- [ ] Open the app with **no positions** — verify the empty state reads clearly
- [ ] Open the app on a **slow network** (toggle airplane mode for 5 sec then back) — verify pull-to-refresh recovers
- [ ] Try logging a trade with **invalid input** (strike $0, fill $0 on an open) — verify Review stays disabled
- [ ] **Assignment flow** — if you have an ITM short call past expiry, tap "Likely assignment · log it" → verify the FIFO cost basis preview matches what you expect

### Things to look for
- Hero P&L on each card should equal the sum of the per-leg "Total return" rows below — please flag any cards where they don't match
- "If exercised" row should appear only on **covered short calls that are ITM** — flag if you see it on puts or OTM calls
- Cursor in the trade ticket should sit cleanly next to the number you're editing
- The Trades segmented control should match the Performance Gains/Leaderboard segmented control exactly

## Known issues / not yet in scope

- **Home tab and Hedge tab are hidden** for v1.0 — rebuild incoming
- **No "On the radar" feed** — removed in the simplified redesign
- **Trade fork's date picker** defaults to today — don't forget to set the actual expiry when opening a new contract
- **FIFO preview** for an exercise uses position-level avg cost, not full lot walk. The actual writer on Confirm uses real FIFO from share_lots.
- **No share-leg edit** from the Trades tab card swipe — routes to the lots-tab admin sheet. Direct in-place edit coming.

## Reporting bugs

- One-liner in our internal Slack channel `#sunnyfi-feedback` works great
- For anything reproducible, include:
  - The leg or screen (e.g. "META $640 Call Sold, swiped close")
  - What you expected vs what happened
  - Device + iOS version (Settings → General → About)
- Screenshots are gold

## TL;DR

Trades tab is the main event. Test the open / close / edit flows on real positions. Yell about anything that feels off.

— Niket
