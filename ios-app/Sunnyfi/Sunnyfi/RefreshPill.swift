//
//  RefreshPill.swift
//  Sunnyfi
//
//  Generalised version of the freshness pill that lived inside the
//  Hedge tab. Now mounted globally above tab content so every screen
//  shows the same status. Color-coded by data age:
//   • green  — last pull < 30m ago
//   • amber  — 30m – 2h
//   • coral  — > 2h
//   • coral  — never (data unavailable)
//
//  Tap to force a manual refresh.
//

import SwiftUI
import Combine

struct RefreshPill: View {
    let store: PortfolioStore

    @State private var refreshing: Bool = false
    /// Bumps every minute so the "Xm ago" text stays current.
    @State private var tick: Int = 0
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Button {
            Task {
                refreshing = true
                await store.refresh()
                refreshing = false
            }
        } label: {
            HStack(spacing: 7) {
                if refreshing {
                    ProgressView()
                        .tint(Color.theme.fg2)
                        .scaleEffect(0.6)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(toneColor)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.numeric(size: 10, weight: .semibold))
                    .foregroundStyle(Color.theme.fg2)
                if let next = nextRefreshHint {
                    Text("·").foregroundStyle(Color.theme.fg4)
                    Text(next)
                        .font(.numeric(size: 10, weight: .medium))
                        .foregroundStyle(Color.theme.fg3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.theme.cardSolid.opacity(0.8))
                    .overlay(Capsule().strokeBorder(Color.theme.soft, lineWidth: 1))
            )
        }
        .buttonStyle(.pressable)
        .onReceive(timer) { _ in tick &+= 1 }
    }

    // Bind `tick` so SwiftUI re-evaluates these every minute.
    private var label: String {
        _ = tick
        guard let last = store.freshness else { return "no data yet" }
        let minutes = max(0, Int(Date().timeIntervalSince(last) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h ago" : "\(h)h \(m)m ago"
    }

    private var toneColor: Color {
        _ = tick
        guard let last = store.freshness else { return Color.theme.neg }
        let minutes = Date().timeIntervalSince(last) / 60
        if minutes < 30  { return Color.theme.pos }
        if minutes < 120 { return Color.theme.warn }
        return Color.theme.neg
    }

    private var nextRefreshHint: String? {
        _ = tick
        let eastern = TimeZone(identifier: "America/New_York") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: Date())
        guard let wd = comps.weekday, let h = comps.hour, let m = comps.minute else { return nil }
        let isWeekday = wd >= 2 && wd <= 6
        let inMarket  = isWeekday && h >= 9 && h < 15
        if inMarket {
            let mins = m % 15
            return "next \(15 - mins)m"
        }
        return "closed"
    }
}
