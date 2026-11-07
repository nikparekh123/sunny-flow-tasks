//
//  BriefDebugMenu.swift
//  Sunny
//
//  The debug menu (handoff 6 Nov 2026, Pass 3, README 2: "a debug menu that pins the clock, the account and the
//  holiday so each state can be opened on purpose"). A long press on Home's title opens it. Pinning a moment or a
//  holiday asks sunny-home for New Home built as if it were that moment (the book as it stands now, written
//  nowhere) and shows it under an orange "Pinned" bar; Back to live drops it. The account and privacy switch here
//  too. Positions keeps the live book.
//

import SwiftUI
import Supabase

/// A pinned state: the moment, and a made-up holiday this week or an early close today.
struct BriefPin: Equatable {
    var moment: Moment
    var holiday: String?      // "week" | "early"

    var words: String {
        [BriefPin.names[moment] ?? moment.rawValue, holiday == "week" ? "Holiday week" : holiday == "early" ? "Early close" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
    static let names: [Moment: String] = [.futures: "Overnight futures", .pre: "Pre-market", .bell: "The bell", .open: "Market hours",
                                          .last20: "Last 20 minutes", .last5: "Last 5 minutes", .post: "Post-market", .weekend: "Weekend"]
}

enum BriefPinClient {
    nonisolated struct Reply: Decodable, Sendable {
        nonisolated struct Pinned: Decodable, Sendable { let moment: String; let date: String; let mins: Int }
        let pinned: Pinned
        let brief: JSONValue
        let overview: JSONValue?
    }

    static func fetch(book: String, pin: BriefPin) async throws -> Reply {
        #if DEBUG && targetEnvironment(simulator)
        // Screens checked without signing in: `-pinnedDir <dir>` reads <dir>/<book>-<moment>-<holiday or ->.json.
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-pinnedDir"), i + 1 < a.count {
            let f = URL(fileURLWithPath: a[i + 1]).appendingPathComponent("\(book)-\(pin.moment.rawValue)-\(pin.holiday ?? "-").json")
            return try await decode(try Data(contentsOf: f))
        }
        #endif
        var r = URLRequest(url: URL(string: Secrets.supabaseURL + "/functions/v1/sunny-home")!, timeoutInterval: 60)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        let token = try await SupabaseService.client.auth.session.accessToken
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["mode": "doc", "book": book, "moment": pin.moment.rawValue]
        if let h = pin.holiday { body["holiday"] = h }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try await decode(d)
    }

    nonisolated private static func decode(_ data: Data) async throws -> Reply {
        try await Task.detached(priority: .userInitiated) { try JSONDecoder().decode(Reply.self, from: data) }.value
    }

    /// The pinned New York day and minute as a date (the day card's sky and clock follow it).
    static func date(_ day: String, _ mins: Int) -> Date? {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "America/New_York"); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: "\(day) \(String(format: "%02d:%02d", mins / 60, mins % 60))")
    }
}

extension BriefState {
    /// Pins a moment (and holiday) on the book on screen, or drops the pin with nil.
    func applyPin(_ p: BriefPin?) async {
        guard let p else { unpin(); return }
        pinLoading = true; pinError = nil
        defer { pinLoading = false }
        do {
            // The book from the account on screen (Overview reads Sunny's), so a switch just made counts at once.
            let b = account == .nicolay ? "N" : accounts.contains(.sunny) ? "S" : (book ?? "S")
            let r = try await BriefPinClient.fetch(book: b, pin: p)
            setPinned(p, live: BriefLive(r.brief), at: BriefPinClient.date(r.pinned.date, r.pinned.mins), overview: r.overview)
        } catch {
            pinError = "Could not build that moment. Try again."
        }
    }
}

struct BriefDebugMenu: View {
    @Environment(BriefState.self) private var brief
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @Environment(\.dismiss) private var dismiss
    @State private var moment: Moment?
    @State private var holiday: String?

    var body: some View {
        NavigationStack {
            List {
                Section("When") {
                    row("Live, follow the clock", moment == nil) { moment = nil }
                    ForEach(Moment.allCases) { m in row(BriefPin.names[m] ?? m.rawValue, moment == m) { moment = m } }
                }
                Section("Holiday") {
                    row("None", holiday == nil) { holiday = nil }
                    row("A holiday this week", holiday == "week") { holiday = "week"; if moment == nil { moment = .open } }
                    row("Early close today", holiday == "early") { holiday = "early"; if moment == nil { moment = .open } }
                }
                if brief.accounts.count > 1 {
                    Section("Account") {
                        ForEach(brief.accounts) { a in row(a.name, brief.account == a) { brief.pick(a) } }
                    }
                }
                Section("Privacy") { Toggle("Hide book money", isOn: $privacy) }
                Section {
                    Text("A pinned moment shows the book as it stands now, as Home would write it at that moment. Positions stays live. Sample data is a launch option (-sample).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let e = brief.pinError { Text(e).foregroundStyle(S.red) }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(brief.pinLoading ? "Building…" : "Show") {
                        Task {
                            await brief.applyPin(moment.map { BriefPin(moment: $0, holiday: holiday) })
                            if brief.pinError == nil { dismiss() }
                        }
                    }
                    .disabled(brief.pinLoading)
                }
            }
        }
        .onAppear { moment = brief.pin?.moment; holiday = brief.pin?.holiday }
    }

    private func row(_ t: String, _ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack { Text(t).foregroundStyle(S.ink); Spacer(); if on { Image(systemName: "checkmark").foregroundStyle(S.ink) } }
        }
    }
}

/// The orange bar while a moment is pinned: what is pinned, and the way back to live.
struct BriefPinBar: View {
    @Environment(BriefState.self) private var brief
    var body: some View {
        if let p = brief.pin {
            HStack(spacing: 10) {
                Text("Pinned · \(p.words)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Button("Back to live") { Task { await brief.applyPin(nil) } }
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 14).frame(height: 34)
            .background(Capsule().fill(S.act))
            .padding(.horizontal, S.margin)
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
        }
    }
}
