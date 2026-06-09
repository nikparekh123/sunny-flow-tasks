//
//  LogoTimer.swift
//  Sunnyfi
//
//  ◆ SUNNYFI mark with the 15-min sync cycle baked into it. The
//  diamond fills with neon as the next refresh approaches; flashes
//  on a real sync; turns amber if data is stale. No separate
//  "X minutes ago" pill — the logo IS the live indicator.
//
//  Driven from `store.freshness` (the latest greeks/quote capture
//  timestamp from Supabase), not a CSS-style continuous animation —
//  so it stays truthful across backgrounding, manual refresh, and
//  failed syncs.
//
//  Replaces the old RefreshPill that lived at the top of TabRootView.
//

import Combine
import SwiftUI

struct LogoTimer: View {
    let store: PortfolioStore
    /// Visual size of the diamond mark. 26 is the default header size
    /// per the design handoff; passing 22 / 34 gives the compact / large
    /// variants if we ever need them.
    var markSize: CGFloat = 26
    /// Show the small "Synced Xm ago · live" caption next to the
    /// wordmark. Hidden in tight spaces — the mark alone reads as
    /// "data is current".
    var showCaption: Bool = true

    /// Manual-refresh trigger on tap. The pulse animation hides while
    /// this is true.
    @State private var refreshing: Bool = false
    /// Bumps every second so the fill / caption stay current as time
    /// passes without a backend event.
    @State private var tick: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Where we are in the 15-min cycle, 0…1. >1 if we're past due.
    private var progress: Double {
        _ = tick
        guard let last = store.freshness else { return 1.0 } // no data = fully drained
        let elapsed = Date().timeIntervalSince(last)
        return elapsed / Self.cycleSeconds
    }

    /// Visible fill height (0…1). Drains back from 1 → 0 in the stale
    /// state so the diamond visibly empties as it gets older.
    private var fillFraction: Double {
        if isStale {
            // Drain from full at the threshold to empty at 2× cycle.
            let overshoot = max(0, progress - 1.0)
            return max(0, 1.0 - overshoot)
        }
        return min(1.0, max(0.0, progress))
    }

    /// True once we're past the cycle plus a small grace period
    /// (~1 min). Switches the mark to amber/warn.
    private var isStale: Bool {
        store.freshness == nil || progress > 1.05
    }

    /// Caption next to the wordmark. Truthful and compact.
    private var captionText: String {
        guard let last = store.freshness else { return "no sync yet" }
        let minutes = max(0, Int(Date().timeIntervalSince(last) / 60))
        if isStale { return "stale · tap to refresh" }
        if minutes < 1 { return "synced just now · live" }
        return "synced \(minutes)m ago · live"
    }

    var body: some View {
        Button {
            Task {
                refreshing = true
                await store.refresh()
                refreshing = false
            }
        } label: {
            HStack(alignment: .center, spacing: markSize * 0.42) {
                diamondMark
                VStack(alignment: .leading, spacing: 1) {
                    Text("SUNNYFI")
                        .font(.ui(size: markSize * 0.52, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(Color.theme.fg1)
                    if showCaption {
                        Text(captionText)
                            .font(.numeric(size: 9, weight: .medium))
                            .foregroundStyle(captionColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onReceive(timer) { _ in tick &+= 1 }
    }

    // ── The mark itself ───────────────────────────────────────────
    @ViewBuilder
    private var diamondMark: some View {
        let stroke = isStale ? Color.theme.warn : Color.theme.neon
        let fill   = isStale ? Color.theme.warn : Color.theme.neon
        ZStack {
            // Empty track + outline.
            Diamond()
                .stroke(stroke.opacity(0.55), lineWidth: 1.5)
                .background(
                    Diamond().fill(Color(red: 30/255, green: 90/255, blue: 80/255).opacity(0.32))
                )
                .clipShape(Diamond())
                .frame(width: markSize, height: markSize)

            // Filling overlay — clipped to the diamond, height grows
            // with progress, anchored to the bottom.
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(fill)
                        .frame(height: geo.size.height * fillFraction)
                }
            }
            .clipShape(Diamond())
            .frame(width: markSize, height: markSize)
            .animation(.easeOut(duration: 0.6), value: fillFraction)

            // Brief "just synced" flash when refreshing finishes — the
            // refresh action drops freshness to "0 elapsed", which we
            // surface here as a quick glow.
            if !isStale && progress < 0.02 {
                Diamond()
                    .fill(Color.theme.neon)
                    .frame(width: markSize, height: markSize)
                    .opacity(0.55)
                    .blur(radius: 6)
                    .transition(.opacity)
            }
        }
        .compositingGroup()
        .shadow(color: stroke.opacity(0.25), radius: 4, x: 0, y: 0)
    }

    private var captionColor: Color {
        isStale ? Color.theme.warn : Color.theme.fg3
    }

    /// Production cycle — matches the `mp-refresh-15min` Supabase cron.
    private static let cycleSeconds: Double = 15 * 60
}

// ── Diamond shape ────────────────────────────────────────────────
/// Square rotated 45°. Implementing as a path means the fill
/// animations stay clean (no transform glitches).
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let cy = rect.midY
        let w  = rect.width
        let h  = rect.height
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: cy))
        p.addLine(to: CGPoint(x: cx, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: cy))
        p.closeSubpath()
        _ = (w, h)
        return p
    }
}
