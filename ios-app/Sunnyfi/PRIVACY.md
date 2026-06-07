# Sunnyfi Privacy Policy

**Last updated: June 5, 2026**

Sunnyfi is an internal portfolio and options-trading application used by Sunny Wealth Management employees and authorized testers. It is **not** a multi-tenant product: the entire SWM team signs in to a single shared account and views the same book of trades, positions, and lots. This document explains what data the app collects, how it's stored, and how to delete it.

## What we collect

| Data | Purpose | Where it lives |
|---|---|---|
| **Email address** | Account authentication | Supabase Auth |
| **Trade logs** (options, share buys/sells, share lots) | Power the Trades, Positions, Activity, and Performance views | Supabase database, scoped to your `user_id` |
| **Position notes** (free-text per trade) | Your own record-keeping | Supabase database, scoped to your `user_id` |
| **Crash reports** | Diagnose app crashes | Sentry (sunny-wm/apple-ios project), stripped of personally identifiable trade data |
| **Device identifier for push notifications** | Send opt-in alerts (assignment risk, expiry reminders) | Stored against your `user_id` in Supabase, used only by our notification service |

We do **not** collect:
- Real-name identity, address, or phone number
- Brokerage credentials or API keys
- Location data
- Contacts, photos, calendar, or other system data
- Advertising identifiers (IDFA)
- Any analytics on tap/scroll behavior

## How we use it

- Trade and position data is the firm's shared book and is visible to anyone signed in to the shared SWM team account. Sunny WM administrators can see all data for support and debugging.
- Crash reports are reviewed by the engineering team to fix bugs. They contain stack traces, device model, OS version, and app build — not portfolio contents.
- Push notification tokens are used only to send notifications you opt into via iOS settings; we do not share them with third parties.

## How we store it

- All data is stored in Supabase databases hosted in the United States.
- Sign-in is gated by Supabase Auth on the shared SWM team account. Row-Level Security is enabled on every table; only authenticated clients can read or modify rows.
- Crash data is stored by Sentry per their [Privacy & Security](https://sentry.io/privacy/) terms.
- Data is encrypted in transit (HTTPS/TLS) and at rest.

## How long we keep it

- Trade and position data: indefinitely while your account is active.
- Crash data: 90 days, then deleted by Sentry per their default retention policy.
- Push notification tokens: until you uninstall the app or revoke notifications.

## Your rights

You can:
- **Export firm data** — request a copy of the firm's trade and position rows by emailing the address below. Because the data is shared, export requests are coordinated with SWM administration.
- **Stop using the app** — sign out from the You tab and uninstall. Your APNs push token and Face ID state are cleared from the device. Firm data remains in Supabase for the rest of the team.
- **Opt out of notifications** — toggle them off in iOS Settings → Sunnyfi → Notifications.
- **Opt out of crash reporting** — not currently exposed in-app; email us if you want it disabled.

## Children

Sunnyfi is not intended for users under 18 and is not offered to the public.

## Changes

If this policy changes, we will update the "Last updated" date above and notify active users in-app on next launch.

## Contact

Questions or requests: **nik@sunnyfi.co**
