# Sunnyfi — Context for Claude

Persistent context the user keeps having to re-explain. Read this **before** suggesting changes to IBKR sync, the iOS app, or the Supabase setup.

## The product in 30 seconds

Sunnyfi is the user's personal iOS app for managing their option-overlay equity portfolio. Data flows: IBKR account → IBKR Flex Web Service → Supabase edge function `ibkr-flex-sync` → Postgres → iOS app via Supabase Swift SDK. Market prices come from Polygon via the `mp-refresh` edge function. The user is **not a developer** — explain what to click, not what to compile.

## IBKR Flex specifics — DO NOT FORGET

IBKR Flex Web Service has **two different report types**. They are not interchangeable:

| Type | Latency | Allowed Periods | What we use it for |
|---|---|---|---|
| **Trade Confirmation Flex** | ~15 min after execution | "Today" only | This is what `ibkr-flex-sync` calls every 15 min during market hours. Query ID **1535729** is configured as Period = "Today". |
| **Daily Flex** | T+1 (24-hour) overnight | Multi-day periods OK | Used for historical backfills only (see `docs/IBKR_CUTOVER_RUNBOOK.md` Option B). Not the cron's primary feed. |

**Do not suggest the user change Trade Confirmation Flex's Period to a multi-day range** — it just won't return intraday data, and they'll lose the 15-min freshness that's the whole point. If they want historical backfill, that's a *separate* Flex Query with a different ID.

## The void/cancellation logic (fixed 2026-06-09)

`ibkr-flex-sync` soft-voids trades that have disappeared from IBKR's report (true cancellations). The rule is now: **only void IBKR trades whose `trade_date` is in the current report's date set.** Trades dated outside the report's scope are untouched.

This replaces a prior buggy rule ("any IBKR trade with `last_synced_at` in the last 7 days that isn't in seenIds") that mass-voided a week's worth of trades the moment the report came back empty. If you find yourself proposing to change this, re-read the incident comment in `supabase/functions/ibkr-flex-sync/index.ts` section 7.

## Supabase

- Project ref: `ziwoutsnuywjnsyfbzsp`
- The CLI on this user's machine is broken (node 26 incompatibility). Don't suggest `supabase db push` or `supabase functions deploy`. Edge function deploys happen via **Dashboard → Edge Functions → \<name\> → code editor → Save**. SQL migrations are applied via **Dashboard → SQL Editor**.
- Cron jobs: `mp-refresh-15min` (market prices), `ibkr-flex-sync-15min` (trades), `health-monitor-1min`, plus the alert-dispatcher and apns-deliver crons. All run via Postgres `pg_cron`.
- Secrets live in `vault.decrypted_secrets`: `IBKR_FLEX_TOKEN`, `IBKR_FLEX_QUERY_ID`, `POLYGON_API_KEY`, `service_role_key`.

## iOS app

- Repo path: `ios-app/Sunnyfi/Sunnyfi/`
- Bundle ID: `com.sunnyfi.app` (Apple team `AR5LF7RNCP`)
- Xcode beta at `/Users/niketparekh/Downloads/Xcode-beta.app` — use `DEVELOPER_DIR` env var when shelling out to `xcodebuild`.
- For physical device builds: `ENABLE_DEBUG_DYLIB = NO` is set on Debug config — keep it. Xcode 16+'s default split-binary debug layout broke launch on iOS 27 builds (libxpc init crash).
- Sentry SPM package is pinned (sentry-cocoa 9.16.1) but **not currently linked to the target** — `import Sentry` and `SentrySDK.start { ... }` are commented out in `SunnyfiApp.swift`. To re-enable: Xcode → target → General → Frameworks → add Sentry, then uncomment those lines.
- The simulator runs the app fine; the user's physical iPhone is on iOS 27 beta `24A5355q`. When in doubt, use the simulator for testing.

## Working style the user wants

- **No checklists. Do the work.** "Try this, try that, then check this" frustrates the user fast. When something is broken, dig in (read code, query the API with the publishable key in `Secrets.swift`, inspect built artifacts) rather than asking the user to run diagnostics. Their job is to use the app, not run a debugger for you.
- **Trust the runbooks.** `docs/IBKR_CUTOVER_RUNBOOK.md`, `docs/portfolio-go-live.md`, `docs/METRICS.md` are source of truth for things already designed.
- **Commit + push as you go.** The user wants visible progress on GitHub, not local-only commits. Push every meaningful commit.
- **Don't disable features to "test"** without restoring them in the same turn unless explicitly told to leave them off.

## What's "in production" (per Jun 2026)

- IBKR Flex sync every 15 min, soft-deletes via voided_at, lifecycle codes A/Ex/Ep handled
- Today landing tab with per-event pinning + IV bucket (requires `option_iv_daily_change` view applied to prod)
- SyncIndicator (orbit-style freshness pill)
- Settings → "Manual entry (use sparingly)" toggle
- BGTaskScheduler 15-min hint + remote push (APNs via apns-deliver cron, devices in push_devices table)
- App lock + biometric gate + onboarding
- macro_events + earnings_events tables seeded
- Privacy policy live at nikparekh123.github.io/sunny-flow-tasks/privacy

## Open tracker (per Jun 2026)

- #7 Notification permission prompt bug (real bug, found during smoke test)
- #11 Hard cutover — wipe manual trades + IBKR backfill (runbook ready, awaiting trigger)
- #17 FIFO share consumption reconcile (`realized_pl` on IBKR-sourced share sells stays at 0 until built)
- #19 Snapshot pipeline debug (daily_theta + position_history empty despite cron "success") — suppressed in health-monitor for now
