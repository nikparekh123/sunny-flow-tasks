//
//  SystemAlertBanner.swift
//  Sunnyfi
//
//  Non-dismissible top banner that appears whenever
//  `store.activeAlerts` is non-empty. Driven by the
//  `health-monitor` cron writing to `system_alerts` and the
//  store fetching unresolved rows on every load.
//
//  Shown above the tab content (under the status bar) on every tab
//  so the user never misses a "data is stale" or "cron failed"
//  situation. Tapping the banner shows the detail; alerts can't be
//  dismissed by the user — they auto-clear when the underlying
//  issue resolves (cron writes `resolved_at`).
//

import SwiftUI

struct SystemAlertBanner: View {
    let alerts: [SystemAlertRow]
    @State private var expandedID: String? = nil

    var body: some View {
        if alerts.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                ForEach(alerts) { a in
                    row(a)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func row(_ a: SystemAlertRow) -> some View {
        let isExpanded = expandedID == a.id
        let tone: Color = a.isCritical ? Color.theme.neg : Color.theme.warn

        Button {
            withAnimation(Motion.standard) {
                expandedID = isExpanded ? nil : a.id
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: a.isCritical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tone)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.title)
                        .font(.ui(size: 12, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                        .multilineTextAlignment(.leading)
                    if isExpanded, let d = a.detail, !d.isEmpty {
                        Text(d)
                            .font(.ui(size: 11, weight: .medium))
                            .foregroundStyle(Color.theme.fg2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.theme.fg3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tone.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(tone.opacity(0.45), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }
}
