//
//  NvdaShell.swift
//  Sunnyfi — Ink rebuild · Events + Profile tabs
//
//  Two chrome tabs that sit beside the portfolio. Events is the forward
//  calendar (earnings + macro); Profile is the rebuilt Account surface with
//  the System / Light / Dark theme control. Both compose Ink primitives only.
//

import SwiftUI
import UIKit

// MARK: - Events

/// A dated calendar entry. Earnings is real (IBKR/NVDA); macro entries are
/// added as the user hands them over — nothing is invented here.
struct NvEvent: Identifiable {
    enum Kind { case earnings, macro }
    let id = UUID()
    let date: DateComponents      // y/m/d in America/New_York
    let kind: Kind
    let title: String
    let tag: String
    let detail: String
}

struct NvdaEventsScreen: View {
    let store: NvdaStore

    // The one confirmed event today: NVDA Q2 FY27 earnings, Aug 26 2026.
    private let events: [NvEvent] = [
        NvEvent(date: DateComponents(year: 2026, month: 8, day: 26), kind: .earnings,
                title: "NVDA · Q2 FY2027 earnings",
                tag: "After close",
                detail: "Est EPS $2.07–2.09 · revenue ~$91.8B. The overlay's biggest single-day risk."),
    ]

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c
    }
    private func daysUntil(_ dc: DateComponents) -> Int {
        guard let d = cal.date(from: dc) else { return 0 }
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
    }
    private func dateLabel(_ dc: DateComponents) -> String {
        guard let d = cal.date(from: dc) else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; f.timeZone = cal.timeZone; return f.string(from: d)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "What's coming", count: "\(events.count) dated")
                if let next = events.min(by: { daysUntil($0.date) < daysUntil($1.date) }) {
                    earningsHero(next).inkEntrance(0).padding(.horizontal, 16)
                }
                timeline.padding(.top, 8)
                macroFooter
                Color.clear.frame(height: 120)
            }
        }
    }

    private func earningsHero(_ e: NvEvent) -> some View {
        let d = daysUntil(e.date)
        return InkCard(spine: .short, height: 300) {
            InkBody {
                InkEyebrow(n: "NEXT", cat: e.kind == .earnings ? "Earnings" : "Macro", glyph: "◆") {
                    InkBand(skin: .hue(Ink.delayed), text: e.tag)
                }
                InkHero(value: "\(d)", unit: d == 1 ? "day away" : "days away")
                InkBullets(items: [e.detail])
                InkSpacer()
                InkBand3(items: [
                    ("Date", dateLabel(e.date)),
                    ("Est EPS", "$2.08"),
                    ("Est rev", "$91.8B"),
                ])
            }
            InkStamp(state: .delayed, text: "Confirmed · NVDA investor relations")
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(events.sorted(by: { daysUntil($0.date) < daysUntil($1.date) })) { e in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 4) {
                        Text("\(daysUntil(e.date))").font(InkFont.mono(16, .medium)).foregroundStyle(Ink.text)
                        Text("DAYS").font(InkFont.mono(8)).tracking(8 * 0.14).foregroundStyle(Ink.dim)
                    }
                    .frame(width: 48)
                    Rectangle().fill(Ink.hair).frame(width: 1).frame(maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(e.title).font(InkFont.display(14, .medium)).foregroundStyle(Ink.text)
                            Spacer(minLength: 0)
                            InkBand(skin: e.kind == .earnings ? .hue(Ink.delayed) : .low, text: e.tag)
                        }
                        Text(dateLabel(e.date)).font(InkFont.mono(10)).tracking(10 * 0.06).foregroundStyle(Ink.dim)
                        inkFig(e.detail).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 18)
                }
                .padding(.horizontal, 16).padding(.top, 16)
            }
        }
    }

    private var macroFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Ink.hair).frame(height: 1)
            Text("MACRO CALENDAR").font(InkFont.mono(9.5)).tracking(9.5 * 0.16).foregroundStyle(Ink.dim)
            Text("FOMC, CPI and jobs prints appear here once wired to the macro feed.")
                .font(InkFont.display(13, .light)).foregroundStyle(Ink.dim)
        }
        .padding(.horizontal, 16).padding(.top, 24)
    }
}

// MARK: - Profile

struct NvdaProfileScreen: View {
    let auth: AuthStore
    let lock: AppLock
    let prefs: NotificationPrefs

    private let appPrefs = AppPrefs.shared
    @State private var showSignOut = false

    private var email: String {
        if case .signedIn(let e) = auth.state { return e }
        return "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                InkSectionHead(title: "Account", count: "Sunnyfi")
                header.padding(.horizontal, 16)
                display
                security
                account
                version
                Color.clear.frame(height: 120)
            }
        }
        .confirmationDialog("Sign out of Sunnyfi?", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await auth.signOut(); lock.onboardingDone = false }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need the 10-digit code to sign back in.")
        }
    }

    // ── header ──
    private var header: some View {
        HStack(spacing: 16) {
            Text("NP").font(InkFont.mono(20, .medium)).foregroundStyle(Ink.invertText)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Ink.invertBg))
            VStack(alignment: .leading, spacing: 5) {
                Text("Niket Parekh").font(InkFont.serif(20)).foregroundStyle(Ink.text)
                Text(email).font(InkFont.mono(11)).foregroundStyle(Ink.dim)
            }
            Spacer(minLength: 0)
        }
    }

    // ── display ──
    private var display: some View {
        panel("Display") {
            row(icon: "circle.lefthalf.filled", label: "Appearance") {
                InkSegment(selection: Binding(get: { appPrefs.appearance }, set: { appPrefs.appearance = $0 }))
            }
            hair
            toggleRow(icon: "eye.slash", label: "Hide P&L amounts",
                      on: Binding(get: { appPrefs.hidePnL }, set: { appPrefs.hidePnL = $0 }))
        }
    }

    // ── security ──
    private var security: some View {
        panel("Security") {
            toggleRow(icon: lock.biometricKind.icon, label: lock.biometricKind.label,
                      on: Binding(
                        get: { lock.biometricEnabled },
                        set: { newVal in
                            Task {
                                if newVal { if await lock.authenticate(reason: "Enable lock") { lock.biometricEnabled = true } }
                                else { lock.biometricEnabled = false }
                            }
                        }))
            hair
            toggleRow(icon: "icloud.and.arrow.down", label: "Background refresh",
                      on: Binding(get: { appPrefs.backgroundRefresh }, set: { appPrefs.backgroundRefresh = $0 }))
        }
    }

    // ── account ──
    private var account: some View {
        panel("Account & data") {
            Link(destination: URL(string: "https://nikparekh123.github.io/sunny-flow-tasks/privacy")!) {
                rowBody(icon: "lock.shield", label: "Privacy & data", tint: Ink.text) {
                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Ink.dim)
                }
            }.buttonStyle(.plain)
            hair
            Link(destination: URL(string: "mailto:support@sunnyfi.co")!) {
                rowBody(icon: "envelope", label: "Help & support", tint: Ink.text) {
                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Ink.dim)
                }
            }.buttonStyle(.plain)
            hair
            Button(role: .destructive) { showSignOut = true } label: {
                rowBody(icon: "rectangle.portrait.and.arrow.right", label: "Sign out", tint: Ink.loss) { EmptyView() }
            }.buttonStyle(.plain)
        }
    }

    private var version: some View {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return HStack {
            Spacer()
            Text("Sunnyfi v\(v) · build \(b)").font(InkFont.mono(10)).tracking(10 * 0.06).foregroundStyle(Ink.dim)
            Spacer()
        }
    }

    // ── layout helpers ──
    @ViewBuilder private func panel<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.16)
                .foregroundStyle(Ink.dim).padding(.leading, 20)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
                .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).strokeBorder(Ink.hair, lineWidth: 1))
                .padding(.horizontal, 16)
        }
    }
    private var hair: some View { Rectangle().fill(Ink.hair).frame(height: 1).padding(.leading, 54) }

    @ViewBuilder private func row<Trailing: View>(icon: String, label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        rowBody(icon: icon, label: label, tint: Ink.text, trailing: trailing)
    }
    @ViewBuilder private func toggleRow(icon: String, label: String, on: Binding<Bool>) -> some View {
        rowBody(icon: icon, label: label, tint: Ink.text) {
            Toggle("", isOn: on).labelsHidden().tint(Ink.invertBg)
        }
    }
    @ViewBuilder private func rowBody<Trailing: View>(icon: String, label: String, tint: Color, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .regular)).foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Ink.text.opacity(0.06)))
            Text(label).font(InkFont.display(14, .regular)).foregroundStyle(tint)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
    }
}

/// Inverted-selection 3-way segmented control (Ink Law 1: selection is inversion).
private struct InkSegment: View {
    @Binding var selection: AppPrefs.Appearance
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppPrefs.Appearance.allCases) { a in
                let on = a == selection
                Button { selection = a } label: {
                    Text(a.rawValue.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.1)
                        .foregroundStyle(on ? Ink.invertText : Ink.dim)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background { if on { Capsule().fill(Ink.invertBg) } }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Ink.text.opacity(0.06)))
        .animation(InkMotion.fast, value: selection)
    }
}
