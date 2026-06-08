//
//  SettingsScreen.swift
//  Sunnyfi
//
//  Settings sheet — biometric toggle + lock timeout, notification
//  toggles per category, sign-out, privacy/support links, version.
//  Reached from the gear icon on the Home screen.
//

import SwiftUI

struct SettingsScreen: View {
    let auth: AuthStore
    let lock: AppLock
    let prefs: NotificationPrefs
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacy: Bool = false
    @State private var showSignOutConfirm: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    securitySection
                    notificationsSection
                    dataSourcesSection
                    aboutSection
                    accountSection
                    versionFooter
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Color.theme.page)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.theme.neon)
                }
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyPolicyView()
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await auth.signOut()
                        lock.onboardingDone = false  // re-show onboarding on re-sign-in
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need the 10-digit code to sign back in.")
            }
        }
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
        .task { await prefs.refreshSystemPermission() }
    }

    // MARK: - Sections

    private var securitySection: some View {
        sectionCard(title: "SECURITY") {
            settingsRow {
                Image(systemName: lock.biometricKind.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.theme.neon)
                Text(lock.biometricKind.label)
                    .font(.ui(size: 14, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
                Spacer()
                Toggle("", isOn: Binding(
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
                .labelsHidden()
                .tint(Color.theme.neon)
            }
            if lock.biometricEnabled {
                Divider().overlay(Color.theme.soft)
                settingsRow {
                    Text("Lock after")
                        .font(.ui(size: 14, weight: .medium))
                        .foregroundStyle(Color.theme.fg2)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { lock.lockTimeout },
                        set: { lock.lockTimeout = $0 }
                    )) {
                        ForEach(AppLock.LockTimeout.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.theme.neon)
                }
            }
        }
    }

    private var notificationsSection: some View {
        sectionCard(title: "NOTIFICATIONS") {
            // System permission banner
            if prefs.systemPermission == .denied {
                permissionDeniedRow
                Divider().overlay(Color.theme.soft)
            } else if prefs.systemPermission == .notDetermined {
                permissionAskRow
                Divider().overlay(Color.theme.soft)
            }

            // Per-category toggles grouped by tier.
            tierHeader(.critical)
            ForEach(NotificationPrefs.Category.allCases.filter { $0.tier == .critical }) { c in
                categoryRow(c, locked: true)
            }
            Divider().overlay(Color.theme.soft)

            tierHeader(.awareness)
            ForEach(NotificationPrefs.Category.allCases.filter { $0.tier == .awareness }) { c in
                categoryRow(c, locked: false)
            }
            Divider().overlay(Color.theme.soft)

            tierHeader(.macro)
            ForEach(NotificationPrefs.Category.allCases.filter { $0.tier == .macro }) { c in
                categoryRow(c, locked: false)
            }
        }
    }

    @ViewBuilder
    private func tierHeader(_ tier: NotificationPrefs.Tier) -> some View {
        HStack {
            Text(tier.label.uppercased())
                .font(.ui(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.theme.fg3)
            Spacer()
            if tier == .critical {
                Text("always on")
                    .font(.ui(size: 9, weight: .semibold))
                    .foregroundStyle(Color.theme.fg4)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func categoryRow(_ cat: NotificationPrefs.Category, locked: Bool) -> some View {
        settingsRow {
            Text(cat.label)
                .font(.ui(size: 13, weight: .medium))
                .foregroundStyle(locked ? Color.theme.fg3 : Color.theme.fg1)
            Spacer()
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.theme.fg4)
            } else {
                Toggle("", isOn: Binding(
                    get: { prefs.isEnabled(cat) },
                    set: { prefs.setEnabled($0, for: cat) }
                ))
                .labelsHidden()
                .tint(Color.theme.neon)
            }
        }
    }

    private var permissionDeniedRow: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.theme.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications blocked")
                        .font(.ui(size: 12, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Text("Tap to fix in iOS Settings")
                        .font(.ui(size: 10, weight: .medium))
                        .foregroundStyle(Color.theme.fg3)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }
            .padding(.vertical, 6)
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
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.theme.neon)
                Text("Enable notifications")
                    .font(.ui(size: 13, weight: .bold))
                    .foregroundStyle(Color.theme.fg1)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var dataSourcesSection: some View {
        sectionCard(title: "DATA SOURCES") {
            settingsRow {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.theme.neon)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manual entry (use sparingly)")
                        .font(.ui(size: 14, weight: .semibold))
                        .foregroundStyle(Color.theme.fg1)
                    Text("IBKR Flex sync is your primary source. Enable this only for out-of-broker fills or if sync is paused.")
                        .font(.ui(size: 11, weight: .regular))
                        .foregroundStyle(Color.theme.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { AppPrefs.shared.manualEntryEnabled },
                    set: { AppPrefs.shared.manualEntryEnabled = $0 }
                ))
                .labelsHidden()
                .tint(Color.theme.neon)
            }
        }
    }

    private var aboutSection: some View {
        sectionCard(title: "ABOUT") {
            Button {
                showPrivacy = true
            } label: {
                settingsRow {
                    Text("Privacy & data")
                        .font(.ui(size: 14, weight: .medium))
                        .foregroundStyle(Color.theme.fg1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.theme.fg3)
                }
            }
            .buttonStyle(.plain)
            Divider().overlay(Color.theme.soft)
            Link(destination: URL(string: "mailto:support@sunnyfi.co")!) {
                settingsRow {
                    Text("Email support")
                        .font(.ui(size: 14, weight: .medium))
                        .foregroundStyle(Color.theme.fg1)
                    Spacer()
                    Image(systemName: "envelope")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.theme.fg3)
                }
            }
        }
    }

    private var accountSection: some View {
        sectionCard(title: "ACCOUNT") {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                settingsRow {
                    Text("Sign out")
                        .font(.ui(size: 14, weight: .semibold))
                        .foregroundStyle(Color.theme.neg)
                    Spacer()
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.theme.neg)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var versionFooter: some View {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return HStack {
            Spacer()
            Text("Sunnyfi · v\(v) (\(b))")
                .font(.numeric(size: 10))
                .foregroundStyle(Color.theme.fg4)
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.ui(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.theme.fg3)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.theme.cardSolid)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(Color.theme.soft, lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func settingsRow<C: View>(@ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .center, spacing: 10) { content() }
            .padding(.vertical, 2)
    }
}

// MARK: - Privacy policy

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What we collect")
                        .font(.ui(size: 14, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Text("Sunnyfi stores the trades you record (option positions, share lots, sells) and the market data needed to display them (option Greeks, ticker quotes, daily closes). No location data, contacts, or device identifiers are collected.")
                        .font(.ui(size: 12, weight: .medium))
                        .foregroundStyle(Color.theme.fg2)

                    Text("Where it lives")
                        .font(.ui(size: 14, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Text("Your data is stored in Supabase (Postgres) in the US. Market data is pulled from Polygon on a 15-minute cadence during US market hours.")
                        .font(.ui(size: 12, weight: .medium))
                        .foregroundStyle(Color.theme.fg2)

                    Text("Auth model")
                        .font(.ui(size: 14, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Text("Sunnyfi uses a shared team account. The 10-digit code is the password for that account; anyone with the code can sign in and see the same data. Face ID / Touch ID is an additional device-level lock you control.")
                        .font(.ui(size: 12, weight: .medium))
                        .foregroundStyle(Color.theme.fg2)

                    Text("Delete account")
                        .font(.ui(size: 14, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Text("Since Sunnyfi is a single shared account, individual data deletion isn't applicable. To wipe the entire dataset, email support@sunnyfi.co.")
                        .font(.ui(size: 12, weight: .medium))
                        .foregroundStyle(Color.theme.fg2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
            }
            .background(Color.theme.page)
            .navigationTitle("Privacy & data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.theme.neon)
                }
            }
        }
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
    }
}
