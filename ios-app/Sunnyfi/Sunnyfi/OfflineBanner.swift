//
//  OfflineBanner.swift
//  Sunnyfi
//
//  Thin banner under the global pill that appears when the device
//  has no network. Clear, non-dismissible. Disappears as soon as
//  connectivity returns. Independent of the system_alerts banner
//  so we don't conflate "your network is down" with "the cron
//  failed on the server".
//

import SwiftUI

struct OfflineBanner: View {
    let isOnline: Bool
    let lastFreshness: Date?

    var body: some View {
        if isOnline {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.theme.neg)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're offline")
                        .font(.ui(size: 12, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    if let last = lastFreshness {
                        Text("Last data \(staleLabel(from: last))")
                            .font(.ui(size: 10, weight: .medium))
                            .foregroundStyle(Color.theme.fg3)
                    } else {
                        Text("No cached data yet.")
                            .font(.ui(size: 10, weight: .medium))
                            .foregroundStyle(Color.theme.fg3)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.theme.neg.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.theme.neg.opacity(0.4), lineWidth: 1))
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func staleLabel(from date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let h = minutes / 60
        return "\(h)h ago"
    }
}
