//
//  AccountScreen.swift
//  Sunnyfi
//
//  Merged Profile + Settings. Replaces the prior SettingsScreen,
//  reached from the avatar in the home header (no more separate
//  gear icon). Single scroll: profile hero → stat grid → sync →
//  display → alerts → account/data → version pin.
//
//  Per design handoff (package 2).
//

import SwiftUI
import UIKit

struct AccountScreen: View {
    let auth:  AuthStore
    let lock:  AppLock
    let prefs: NotificationPrefs
    let store: PortfolioStore
    @State private var showPrivacy: Bool = false
    @State private var showSignOutConfirm: Bool = false
    private let appPrefs = AppPrefs.shared

    /// Read off AuthStore. Single shared team account today.
    private var email: String {
        if case .signedIn(let e) = auth.state { return e }
        return "—"
    }
    private var displayName: String { "Niket Parekh" }
    /// Two-letter initials for the avatar bubble.
    private var initials: String {
        let parts = displayName.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "N"
        let last  = parts.dropFirst().first?.first.map(String.init) ?? "P"
        return (first + last).uppercased()
    }
    /// Earliest trade date → years with Sunnyfi.
    private var yearsWithSunnyfi: String {
        let dates = store.allTrades.compactMap { AppDates.parseISODay($0.trade_date) }
        guard let earliest = dates.min() else { return "—" }
        let years = Date().timeIntervalSince(earliest) / (365.25 * 86400)
        if years < 1 { return String(format: "%.1fy", max(0.1, years)) }
        return String(format: "%.1fy", years)
    }

    var body: some View {
        // Rendered as the You tab's content — no NavigationStack /
        // sheet plumbing. The title sits inline with the rest of the
        // scroll so it tracks with the user's reading position.
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Account")
                        .heroTitle()
                    Spacer()
                }
                .padding(.top, 4)
                profileHero
                statGrid
                syncSection
                displaySection
                alertsSection
                accountSection
                versionFooter
                // Clearance for the floating tab bar so the version
                // pin isn't covered.
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(Color.theme.page)
        .sheet(isPresented: $showPrivacy) { PrivacyPolicyView() }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) {
                Task {
                    await auth.signOut()
                    lock.onboardingDone = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need the 10-digit code to sign back in.")
        }
        .task { await prefs.refreshSystemPermission() }
    }

    // ── Profile hero ──
    private var profileHero: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.theme.neon, Color.theme.neonDark],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Text(initials)
                            .font(.ui(size: 30, weight: .bold))
                            .foregroundStyle(Color.theme.onNeon)
                    )
                // Neon edit dot — non-functional for v1; visual anchor.
                Circle()
                    .fill(Color.theme.neon)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(Color.theme.page, lineWidth: 3))
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.theme.onNeon)
                    )
            }
            Text(displayName)
                .font(.ui(size: 18, weight: .bold))
                .foregroundStyle(Color.theme.fg1)
            Text(email)
                .font(.numeric(size: 12, weight: .medium))
                .foregroundStyle(Color.theme.fg3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // ── Stat grid ──
    private var statGrid: some View {
        HStack(spacing: 8) {
            statCard(
                value: fmtMoney(store.portfolio.mv),
                label: "PORTFOLIO",
                accent: true
            )
            statCard(
                value: "\(store.companies.count)",
                label: "POSITIONS"
            )
            statCard(
                value: yearsWithSunnyfi,
                label: "WITH SUNNYFI"
            )
        }
    }

    @ViewBuilder
    private func statCard(value: String, label: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.numeric(size: 16, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(accent ? Color.theme.neon : Color.theme.fg1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.ui(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.theme.fg3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .navCard(stroke: Color.theme.neon.opacity(0.18), cornerRadius: Radius.lg, lineWidth: 1)
    }

    // ── Sync ──
    private var syncSection: some View {
        sectionCard(title: "SYNC · UPDATES EVERY 15 MIN") {
            row(icon: "arrow.triangle.2.circlepath",
                label: "Refresh interval",
                trailingText: "15 min",
                showsChevron: true,
                disabled: true)
            divider
            row(icon: "icloud.and.arrow.down",
                label: "Background refresh",
                toggle: Binding(get: { appPrefs.backgroundRefresh },
                                set: { appPrefs.backgroundRefresh = $0 }))
        }
    }

    // ── Display ──
    private var displaySection: some View {
        sectionCard(title: "DISPLAY") {
            row(icon: "circle.lefthalf.filled",
                label: "Appearance") {
                Picker("", selection: Binding(
                    get: { appPrefs.appearance },
                    set: { appPrefs.appearance = $0 }
                )) {
                    ForEach(AppPrefs.Appearance.allCases) { a in
                        Text(a.rawValue).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .fixedSize()
            }
            divider
            row(icon: "eye.slash",
                label: "Hide P&L amounts",
                toggle: Binding(get: { appPrefs.hidePnL },
                                set: { appPrefs.hidePnL = $0 }))
        }
    }

    // ── Alerts ──
    private var alertsSection: some View {
        sectionCard(title: "ALERTS") {
            if prefs.systemPermission == .denied {
                permissionDeniedRow
                divider
            } else if prefs.systemPermission == .notDetermined {
                permissionAskRow
                divider
            }

            row(icon: lock.biometricKind.icon,
                label: lock.biometricKind.label,
                toggle: Binding(
                    get: { lock.biometricEnabled },
                    set: { newVal in
                        Task {
                            if newVal {
                                let ok = await lock.authenticate(reason: "Enable lock")
                                if ok { lock.biometricEnabled = true }
                            } else {
                                lock.biometricEnabled = false
                            }
                        }
                    }
                ))

            // Each notification category as its own row, grouped by tier.
            divider
            tierLabel("AWARENESS — default on")
            ForEach(NotificationPrefs.Category.allCases.filter { $0.tier == .awareness }) { c in
                divider
                row(icon: "bell",
                    label: c.label,
                    toggle: Binding(
                        get: { prefs.isEnabled(c) },
                        set: { prefs.setEnabled($0, for: c) }
                    ))
            }
            divider
            tierLabel("MACRO — opt-in")
            ForEach(NotificationPrefs.Category.allCases.filter { $0.tier == .macro }) { c in
                divider
                row(icon: "calendar.badge.exclamationmark",
                    label: c.label,
                    toggle: Binding(
                        get: { prefs.isEnabled(c) },
                        set: { prefs.setEnabled($0, for: c) }
                    ))
            }
        }
    }

    // ── Account & data ──
    private var accountSection: some View {
        sectionCard(title: "ACCOUNT & DATA") {
            Button { showPrivacy = true } label: {
                rowContent(icon: "lock.shield",
                           label: "Privacy & data",
                           trailing: chevron)
            }
            .buttonStyle(.plain)
            divider
            Link(destination: URL(string: "mailto:support@sunnyfi.co")!) {
                rowContent(icon: "envelope",
                           label: "Help & support",
                           trailing: chevron)
            }
            divider
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                rowContent(
                    icon: "rectangle.portrait.and.arrow.right",
                    label: "Sign out",
                    iconTint: Color.theme.neg,
                    iconBgTint: Color.theme.tintNeg,
                    labelColor: Color.theme.neg,
                    trailing: AnyView(EmptyView())
                )
            }
            .buttonStyle(.plain)
        }
    }

    // ── Version pin ──
    private var versionFooter: some View {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return HStack {
            Spacer()
            Text("Sunnyfi v\(v) · build \(b)")
                .font(.numeric(size: 11, weight: .semibold))
                .foregroundStyle(Color.theme.neon)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    // ── Layout helpers ──
    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.ui(size: 9, weight: .bold))
                .tracking(2.0)
                .foregroundStyle(Color.theme.fg5)   // Navi "quiet divider"
                .padding(.leading, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .fill(Color.theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.xl)
                                .strokeBorder(Color.theme.borderBright, lineWidth: 1)
                        )
                )
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.theme.soft.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 50)
    }

    @ViewBuilder
    private func tierLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.ui(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.theme.fg4)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // ── Row helpers ──
    // Two overloads cover the variants we need:
    //   row(icon:, label:, toggle:)          — a Toggle pill
    //   row(icon:, label:, trailingText:, showsChevron:, disabled:)
    //   row(icon:, label:) { custom trailing }

    @ViewBuilder
    private func row(
        icon: String,
        label: String,
        toggle: Binding<Bool>
    ) -> some View {
        rowContent(
            icon: icon,
            label: label,
            trailing: AnyView(
                Toggle("", isOn: toggle)
                    .labelsHidden()
                    .tint(Color.theme.neon)
            )
        )
    }

    @ViewBuilder
    private func row(
        icon: String,
        label: String,
        trailingText: String,
        showsChevron: Bool = false,
        disabled: Bool = false
    ) -> some View {
        rowContent(
            icon: icon,
            label: label,
            trailing: AnyView(
                HStack(spacing: 6) {
                    Text(trailingText)
                        .font(.numeric(size: 13, weight: .semibold))
                        .foregroundStyle(disabled ? Color.theme.fg3 : Color.theme.fg1)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.theme.fg4)
                    }
                }
            )
        )
        .opacity(disabled ? 0.7 : 1.0)
    }

    @ViewBuilder
    private func row<Trailing: View>(
        icon: String,
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        rowContent(icon: icon, label: label, trailing: AnyView(trailing()))
    }

    /// The shared row body — 30px icon tile + label + trailing slot.
    @ViewBuilder
    private func rowContent(
        icon: String,
        label: String,
        iconTint: Color = Color.theme.neon,
        iconBgTint: Color = Color.theme.tintNeon,
        labelColor: Color = Color.theme.fg1,
        trailing: AnyView
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(iconBgTint)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .frame(width: 30, height: 30)
            Text(label)
                .font(.ui(size: 14, weight: .medium))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private var chevron: AnyView {
        AnyView(
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.theme.fg4)
        )
    }

    // ── Notification-permission rows ──
    private var permissionDeniedRow: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            rowContent(
                icon: "exclamationmark.triangle.fill",
                label: "Notifications blocked — fix in iOS Settings",
                iconTint: Color.theme.warn,
                iconBgTint: Color.theme.warn.opacity(0.15),
                trailing: chevron
            )
        }
        .buttonStyle(.plain)
    }

    private var permissionAskRow: some View {
        Button {
            Task {
                let status = await prefs.requestPermission()
                if status == .authorized || status == .provisional {
                    PushAppDelegate.registrar.requestSystemRegistration()
                }
            }
        } label: {
            rowContent(
                icon: "bell.badge.fill",
                label: "Enable notifications",
                trailing: chevron
            )
        }
        .buttonStyle(.plain)
    }
}
