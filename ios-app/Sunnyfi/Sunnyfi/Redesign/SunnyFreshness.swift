//
//  SunnyFreshness.swift
//  Freshness, "hold until seen" (21 Sep 2026, `Sunny Freshness Options` 4a).
//
//  ⚠ ONE INK FOR CHANGE: --warn amber. Recency, not direction.
//  ⚠ A MARK HOLDS UNTIL THE CARD IS SEEN (60% on screen, app active, 1 s), then
//    cools once over 3 s to the figure's own ink. Never on a timer while away.
//  ⚠ ONLY THE FIGURE THAT CHANGED is marked, by its colour. The header stamp is
//    the only other trace.
//
//  The diff runs where the feed lands (`OptionsStore.load`); a card only reads
//  its track. First load marks nothing; a quiet pull clears nothing.
//

import SwiftUI

@Observable
final class FreshTrack {
    /// Held marks: key → the figures that moved. A key is `side:TICKER`, or
    /// `side:#total` for a Total row.
    private(set) var marks: [String: Set<String>] = [:]
    /// When the last pull landed.
    private(set) var at: Date?
    /// True from the seen moment until the marks clear: figures take their own
    /// ink, animated.
    private(set) var cooling = false

    func landed(_ diff: [String: Set<String>]) {
        at = Date()
        guard !diff.isEmpty else { return }
        cooling = false
        for (k, v) in diff { marks[k, default: []].formUnion(v) }
    }

    /// The last figures seen, for cards that diff by figure list rather than a
    /// hand-written diff. nil until the first pull, which is the baseline.
    private var last: [String: [String: String]]?

    /// Diff a card's figures (row key → figure → printed value) against the
    /// last pull. A new row is `added`; a gone row marks `closeKey`.
    func observe(_ figs: [String: [String: String]], closeKey: (String, String)? = nil) {
        defer { last = figs }
        guard let old = last else { at = Date(); return }
        var diff: [String: Set<String>] = [:]
        for (k, f) in figs {
            guard let o = old[k] else { diff[k] = ["added"]; continue }
            let moved = Set(f.keys.filter { o[$0] != f[$0] })
            if !moved.isEmpty { diff[k] = moved }
        }
        if let (ck, cf) = closeKey, old.keys.contains(where: { figs[$0] == nil }) {
            diff[ck, default: []].insert(cf)
        }
        landed(diff)
    }

    func isMarked(_ key: String, _ fig: String) -> Bool {
        guard !cooling, let m = marks[key] else { return false }
        return m.contains(fig) || m.contains("added")
    }

    /// Names with any change, a name counted once whatever moved on it.
    var count: Int {
        Set(marks.keys.compactMap { k -> String? in
            let t = (k.split(separator: ":").last.map(String.init) ?? k)
                .split(separator: "|").first.map(String.init) ?? k
            return t.hasPrefix("#") ? nil : t
        }).count
    }

    /// The seen moment. The cool is an animation that only starts with the
    /// reader present; the marks clear when it ends.
    @MainActor func seen(reduceMotion: Bool) async {
        guard !marks.isEmpty, !cooling else { return }
        if reduceMotion { cooling = true } else {
            withAnimation(S.easeSettle(3)) { cooling = true }
        }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 3))
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { marks = [:]; cooling = false }
    }
}

// MARK: - the stamp

/// `<ago>` / `<ago> · N changed` / `Updating…`, right of the header meta.
struct FreshStamp: View {
    let track: FreshTrack
    let updating: Bool
    /// The narrow form: `2 changed` without the age, for a header that cannot
    /// hold the whole stamp beside its title.
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let s = state(ctx.date)
            Text(s.text).font(S.inter(S.t12, s.bold ? S.wSemiN : S.wMidSmN))
                .foregroundStyle(s.ink).lineLimit(1)
        }
    }

    private func state(_ now: Date) -> (text: String, ink: Color, bold: Bool) {
        if updating { return ("Updating\u{2026}", S.mute, false) }
        guard let at = track.at else { return ("", S.mute, false) }
        let secs = now.timeIntervalSince(at)
        let ago = secs < 45 ? "just now"
            : secs < 3600 ? "\(max(1, Int(secs / 60))) min ago" : "\(Int(secs / 3600)) h ago"
        if track.count > 0, !track.cooling {
            return ((compact ? "" : "\(ago) \u{00B7} ") + "\(track.count) changed", S.warn, true)
        }
        return secs < 45 ? (ago, S.ink, true) : (ago, S.mute, false)
    }
}

/// The header's right side: `<meta> · <stamp>`. ⚠ WHILE A CHANGE IS HELD
/// THE STAMP STANDS IN FOR THE META. `8 positions · just now · 1 changed` does
/// not fit beside a title and scope in 313, and the sheet's first rule for the
/// stamp is one line; the meta returns when the marks cool.
struct FreshMeta: View {
    let meta: String
    var metaInk: Color = S.mute
    let track: FreshTrack?
    let updating: Bool

    /* ⚠ AND WHEN EVEN THAT DOES NOT FIT, IT GETS SHORTER, never cut. Weekly
       yield's "on premium paid" leaves no room for "just now · 2 changed"; the
       count is the part that matters, so held falls back to "2 changed" and a
       clean stamp falls back to the meta alone. */
    var body: some View {
        let held = (track?.count ?? 0) > 0 && track?.cooling == false && !updating
        ViewThatFits(in: .horizontal) {
            line(held: held, compact: false)
            line(held: held, compact: true)
        }
    }

    private func line(held: Bool, compact: Bool) -> some View {
        HStack(spacing: 0) {
            if !held {
                Text(meta).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(metaInk)
            }
            if let track, held || !compact {
                if !held && !meta.isEmpty {
                    Text(" \u{00B7} ").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                }
                FreshStamp(track: track, updating: updating, compact: compact)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - seen

extension View {
    /// Seen = at least 60% of the card on screen, the app active, for 1 s
    /// continuously. Then the track cools.
    func freshSeen(_ track: FreshTrack) -> some View { modifier(FreshSeen(track: track)) }
}

/// For cards whose track is optional (a preview or an older caller has none).
struct OptionalFreshSeen: ViewModifier {
    let track: FreshTrack?
    func body(content: Content) -> some View {
        if let track { content.freshSeen(track) } else { content }
    }
}

private struct FreshSeen: ViewModifier {
    let track: FreshTrack
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inView = false
    @State private var arm: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0.6) { v in inView = v; rearm() }
            .onChange(of: phase) { _, _ in rearm() }
            .onChange(of: track.marks.isEmpty) { _, _ in rearm() }
            .onDisappear { arm?.cancel() }
    }

    private func rearm() {
        arm?.cancel()
        guard inView, phase == .active, !track.marks.isEmpty else { return }
        /* Verification only: `-freshHold` never cools, so held marks can be
           inspected without racing the 1 s seen timer. */
        if ProcessInfo.processInfo.arguments.contains("-freshHold") { return }
        arm = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await track.seen(reduceMotion: reduceMotion)
        }
    }
}
