//
//  IBKRSourceBadge.swift
//  Sunnyfi
//
//  Tiny chip that surfaces "this row came from IBKR Flex sync"
//  on Trades and Activity rows. Hidden for manual / assignment /
//  seed rows so the UI doesn't get noisy for non-imported data.
//
//  Two visual modes:
//    .new   — orange chip, "AUTO-IMPORTED · 12 min ago" — shown
//             when last_synced_at is < 24h ago (or user just
//             swiped to refresh and saw a new row land).
//    .quiet — gray dot, no text, just signals "from IBKR" for
//             older rows the user has already digested.
//
//  Wire from any row view:
//      IBKRSourceBadge(source: row.source, lastSyncedAt: row.last_synced_at)
//

import SwiftUI

struct IBKRSourceBadge: View {
    let source: String?
    let lastSyncedAt: String?

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var syncedDate: Date? {
        guard let s = lastSyncedAt else { return nil }
        return Self.formatter.date(from: s)
            ?? ISO8601DateFormatter().date(from: s)
    }

    private var ageHours: Double? {
        guard let d = syncedDate else { return nil }
        return -d.timeIntervalSinceNow / 3600
    }

    var body: some View {
        // Only render for IBKR-sourced rows.
        guard source == "ibkr_flex" else { return AnyView(EmptyView()) }

        let isNew = (ageHours ?? .infinity) < 24

        if isNew, let d = syncedDate {
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .bold))
                    Text("AUTO · \(Self.relative.localizedString(for: d, relativeTo: Date()))")
                        .font(.ui(size: 10, weight: .bold))
                        .tracking(0.3)
                }
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
                )
            )
        }

        // Quiet mode: tiny dot indicating IBKR origin
        return AnyView(
            HStack(spacing: 3) {
                Circle()
                    .fill(Color.theme.fg3)
                    .frame(width: 4, height: 4)
                Text("IBKR")
                    .font(.ui(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.theme.fg3)
            }
        )
    }
}

#Preview("New") {
    IBKRSourceBadge(
        source: "ibkr_flex",
        lastSyncedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-720))
    )
    .padding()
    .background(Color.black)
}

#Preview("Quiet") {
    IBKRSourceBadge(
        source: "ibkr_flex",
        lastSyncedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-200_000))
    )
    .padding()
    .background(Color.black)
}

#Preview("Manual (hidden)") {
    IBKRSourceBadge(source: "manual", lastSyncedAt: nil)
        .padding()
        .background(Color.black)
}
