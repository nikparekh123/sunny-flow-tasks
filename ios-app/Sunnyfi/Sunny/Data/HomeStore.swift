//
//  HomeStore.swift
//  Sunny
//
//  Reads the one Home row and keeps it live (block 25, Refresh):
//  · every 30 s while a session runs (4:00 to 20:00 New York, trading days);
//    closed, nothing ticks and the numbers are the close;
//  · one request for the whole page, never two at once (a pull during a tick
//    joins it), the 30 s clock restarting after each good update;
//  · a failure keeps the last good numbers; open and no good update for 90 s
//    is the "Not updating" state, no network is "Offline";
//  · no polling in the background, and coming back refreshes at once if the
//    last update is older than 30 s.
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class HomeStore {
    enum Health: Equatable { case fresh, notUpdating, offline, cantReach }

    private(set) var home: HomePayload?
    /// The payload insight words are written from (blocks 10, 22, 23). It
    /// moves only on open, on pull to refresh and after the close, never on
    /// the 30 s tick, so a sentence does not change under the reader.
    private(set) var words: HomePayload?
    /// When the last good update landed (the Updated pill's time).
    private(set) var lastGood: Date?
    /// Bumped on every good update: the live glow pulses and numbers roll on it.
    private(set) var tick = 0
    /// Bumped on a good update while a session runs: the live glow pulses
    /// (block 24). Closed, it stays still and the glow fades out.
    private(set) var livePulse = 0
    private(set) var health: Health = .fresh
    private(set) var loadError: String?

    private var inFlight: Task<Void, Never>?
    private var lastAttemptFailedOffline = false

    // MARK: Loading

    /// One fetch; a second caller waits for the one already running.
    enum Reason { case open, pull, tick }

    func refresh(_ reason: Reason = .pull) async {
        if let t = inFlight { await t.value; if reason != .tick, let h = home { words = h }; return }
        let t = Task { await self.fetch(reason) }
        inFlight = t
        await t.value
        inFlight = nil
    }

    private func fetch(_ reason: Reason) async {
        do {
            let data = try await Self.source()
            let payload = try Self.decoder.decode(Row.self, from: data).payload
            home = payload
            if reason != .tick || words == nil || !MarketClock.isRegular(Date(), calendar: payload.calendar) {
                words = payload
            }
            lastGood = Date()
            tick += 1
            if MarketClock.inSession(Date(), calendar: payload.calendar) { livePulse += 1 }
            health = .fresh
            loadError = nil
            lastAttemptFailedOffline = false
        } catch {
            loadError = String(describing: error)
            lastAttemptFailedOffline = (error as? URLError)?.code == .notConnectedToInternet
            health = lastAttemptFailedOffline ? .offline : .cantReach
        }
    }

    /// The row, or in a DEBUG simulator run with `-fixture <path>` a saved copy
    /// of it, so screens can be checked without signing in.
    private static func source() async throws -> Data {
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-fixture"), i + 1 < a.count {
            return try Data(contentsOf: URL(fileURLWithPath: a[i + 1]))
        }
        #endif
        let res = try await SupabaseService.client.from("home_snapshot")
            .select("payload,built_at").eq("id", value: 1).single().execute()
        return res.data
    }

    private struct Row: Decodable { let payload: HomePayload }
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: The 30 s clock

    /// Runs while the app is active. Ticks only inside a session; the caller
    /// cancels it when the scene leaves the foreground.
    func live() async {
        if let g = lastGood, Date().timeIntervalSince(g) < 30, home != nil {
            // Fresh enough: the clock starts from the last good update.
        } else {
            await refresh(.open)
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled { break }
            if MarketClock.inSession(Date(), calendar: home?.calendar ?? []) {
                await refresh(.tick)
                updateHealth()
            } else if let h = home, MarketClock.ny(Date()).date != h.today {
                // Midnight New York: the deck and the day's words move on.
                await refresh(.open)
            }
        }
    }

    /// Open and nothing good for 90 s: the pill turns red (block 01).
    private func updateHealth() {
        guard let g = lastGood else { return }
        if Date().timeIntervalSince(g) > 90, health == .fresh { health = .notUpdating }
    }
}
