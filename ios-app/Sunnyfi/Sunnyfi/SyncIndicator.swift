//
//  SyncIndicator.swift
//  Sunnyfi
//
//  Unified data-freshness indicator that replaces the SUNNYFI
//  lockup + "synced Xm ago · live" caption in the top-left of
//  the home screen.
//
//  Spec: design_handoff_sync_indicator (orbit direction).
//
//  Three states:
//    .live    — silent. Just a faint ring + breathing lime dot,
//               NO label. Resting state 99% of the time.
//               Ring fills 0 → 1 as the next auto-sync approaches
//               (15-min cycle, matches mp-refresh cron).
//    .syncing — ring spins (1.6s linear), neon dot pulses,
//               "SYNCING" label fades in.
//    .stale   — coral ring + coral "!" glyph + "STALE" label.
//               Tap to retry. Data underneath stays visible.
//
//  Tap anywhere on the control = "sync now" / retry.
//
//  Honors `prefers-reduced-motion` — all loops disabled, only
//  state-change transitions remain.
//

import SwiftUI

// ───────────────────────────────────────────────────────────────
// MARK: - Indicator container
// ───────────────────────────────────────────────────────────────

struct SyncIndicator: View {

    enum Status { case live, syncing, stale }

    let store: PortfolioStore
    /// Optional pulling progress 0…1 passed in from a pull-to-refresh
    /// gesture host. When non-nil, the ring tracks the drag and the
    /// label hides. Today's app uses SwiftUI's native .refreshable on
    /// the ScrollViews, which doesn't expose drag progress — so we
    /// leave this nil in production and rely on store.isRefreshing
    /// to drive the syncing animation. Hook this up later if we ever
    /// swap to a custom scroll-offset pull-zone.
    var pulling: Double? = nil

    /// Bumped every second by the timer so the ring fills smoothly
    /// without the store needing to re-emit.
    @State private var tick: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// 15 min — matches mp-refresh cron.
    private static let cycleSeconds: Double = 15 * 60

    // Derived state — entirely read from the store so the indicator
    // animates correctly whether refresh was triggered by tap,
    // pull-to-refresh, background task, or scheduled cron.
    private var status: Status {
        if store.isRefreshing { return .syncing }
        if store.lastRefreshError != nil { return .stale }
        guard let last = store.freshness else { return .stale }
        let elapsed = Date().timeIntervalSince(last)
        return elapsed > Self.cycleSeconds + 60 ? .stale : .live
    }

    /// Fraction toward next auto-sync, 0…1. Drives the ring's gauge
    /// fill while .live. Clamped.
    private var progress: Double {
        _ = tick
        guard let last = store.freshness else { return 0 }
        let elapsed = Date().timeIntervalSince(last)
        return min(1.0, max(0.0, elapsed / Self.cycleSeconds))
    }

    var body: some View {
        Button(action: triggerSync) {
            HStack(spacing: 10) {
                OrbitMark(
                    status: status,
                    progress: progress,
                    pulling: pulling
                )
                if let word = syncWord {
                    Text(word)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(wordColor)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 6)
            .padding(.leading, 2)
            .padding(.trailing, 4)
            .contentShape(Rectangle())
            // iOS 44pt min hit target — pad if the glyph is tiny.
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sync status — tap to refresh")
        .onReceive(timer) { _ in tick &+= 1 }
    }

    // Label visibility & color per spec
    private var syncWord: String? {
        if pulling != nil { return nil }                 // pull state owns its own hint
        switch status {
        case .syncing: return "Syncing"
        case .stale:   return "Stale"
        case .live:    return nil                        // silent
        }
    }
    private var wordColor: Color {
        switch status {
        case .syncing: return .theme.fg3
        case .stale:   return .theme.neg
        case .live:    return .clear
        }
    }

    private func triggerSync() {
        guard !store.isRefreshing else { return }        // re-entry guard
        Task { await store.refresh() }
    }
}

// ───────────────────────────────────────────────────────────────
// MARK: - Orbit mark
// ───────────────────────────────────────────────────────────────

private struct OrbitMark: View {

    let status: SyncIndicator.Status
    let progress: Double
    let pulling: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinAngle: Double = 0

    private let viewboxSize: CGFloat = 28
    private let renderSize: CGFloat = 24
    private let strokeWidth: CGFloat = 2.2

    var body: some View {
        ZStack {
            // Track — faint ring underneath.
            Circle()
                .stroke(trackColor, lineWidth: strokeWidth)

            // Arc — either a gauge fill (live/stale) or a fixed
            // 26% segment that spins (syncing).
            arcView

            // Center glyph — lime dot, neon dot, or "!" depending
            // on state.
            centerGlyph
        }
        .frame(width: renderSize, height: renderSize)
        // Spin loop while syncing. ReduceMotion turns this off.
        .onChange(of: status) { _, newValue in
            if newValue == .syncing && !reduceMotion {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    spinAngle = 0
                }
            }
        }
        .onAppear {
            if status == .syncing && !reduceMotion {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            }
        }
    }

    // The arc — either fixed-gauge or spinning segment.
    @ViewBuilder
    private var arcView: some View {
        let fraction = arcFraction
        let isSpinning = status == .syncing
        let arcLength = isSpinning ? 0.26 : fraction

        Circle()
            .trim(from: 0, to: arcLength)
            .stroke(
                arcColor,
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
            // SVG default starts the trim at 3 o'clock; rotate -90°
            // so 0% sits at 12 o'clock (matches design).
            .rotationEffect(.degrees(-90 + (isSpinning ? spinAngle : 0)))
            .opacity(arcOpacity)
            .animation(.easeInOut(duration: 0.25), value: arcOpacity)
    }

    @ViewBuilder
    private var centerGlyph: some View {
        switch status {
        case .stale:
            Text("!")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.theme.neg)
        case .live, .syncing:
            DotGlyph(status: status, reduceMotion: reduceMotion)
        }
    }

    // ── Color rules ───────────────────────────────────────────

    private var trackColor: Color {
        switch status {
        case .stale: return Color(red: 176/255, green: 74/255, blue: 52/255).opacity(0.20)
        default:     return Color(red: 88/255, green: 102/255, blue: 89/255).opacity(0.13)
        }
    }

    private var arcColor: Color {
        switch status {
        case .stale: return .theme.neg
        default:     return .theme.neon
        }
    }

    private var arcOpacity: Double {
        switch status {
        case .live:    return 0.45
        case .syncing: return 1.0
        case .stale:   return 1.0
        }
    }

    /// 0…1. Drives the static gauge fill (live or stale).
    private var arcFraction: Double {
        if let p = pulling { return min(1.0, max(0.0, p)) }
        switch status {
        case .live:    return min(1.0, max(0.0, progress))
        case .stale:   return 1.0
        case .syncing: return 0.26  // length of the spinning segment
        }
    }
}

// ───────────────────────────────────────────────────────────────
// MARK: - Center dot (breathing live; pulsing while syncing)
// ───────────────────────────────────────────────────────────────

private struct DotGlyph: View {
    let status: SyncIndicator.Status
    let reduceMotion: Bool

    @State private var halo: Bool = false
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            // Halo — gentle 4s breathe in live; soft glow constant
            // while syncing.
            if status == .live && !reduceMotion {
                Circle()
                    .fill(Color.theme.lime.opacity(0.30))
                    .frame(width: 5, height: 5)
                    .scaleEffect(halo ? 2.6 : 1.0)
                    .opacity(halo ? 0 : 0.6)
                    .animation(
                        .easeInOut(duration: 4.0).repeatForever(autoreverses: false),
                        value: halo
                    )
                    .onAppear { halo = true }
            }
            // Core dot
            Circle()
                .fill(coreColor)
                .frame(width: 5, height: 5)
                .opacity(0.9)
                .scaleEffect(pulse && status == .syncing && !reduceMotion ? 1.5 : 1.0)
                .animation(
                    .easeInOut(duration: 1.06).repeatForever(autoreverses: true),
                    value: pulse
                )
        }
        .onChange(of: status) { _, newValue in
            pulse = (newValue == .syncing && !reduceMotion)
        }
        .onAppear {
            pulse = (status == .syncing && !reduceMotion)
        }
    }

    private var coreColor: Color {
        switch status {
        case .syncing: return .theme.neon
        case .live:    return .theme.lime
        case .stale:   return .theme.neg
        }
    }
}

// ───────────────────────────────────────────────────────────────
// MARK: - Previews
// ───────────────────────────────────────────────────────────────

#if DEBUG
#Preview("Live (silent)") {
    SyncIndicator(store: PortfolioStore())
        .padding()
        .background(Color.theme.page)
}
#endif
