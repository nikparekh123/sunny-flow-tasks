//
//  HomeStore.swift
//  Sunny
//
//  Reads the one Home row and keeps it live (block 25, Refresh):
//  · every 30 s while a session runs (4:00 to 20:00 New York, trading days),
//    every 15 s from 9:30 to 16:00 (Nik, 14 Oct 2026), each fetch timed just
//    after the server's rebuild; closed, nothing ticks and the numbers are the
//    close;
//  · one request for the whole page, never two at once (a pull during a tick
//    joins it), the 30 s clock restarting after each good update;
//  · a failure keeps the last good numbers; open and no good update for 90 s
//    is the "Not updating" state, no network is "Offline";
//  · no polling in the background, and coming back refreshes at once if the
//    last update is older than 30 s.
//

import Foundation
import Network
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
    /// Bumped when Home opens and on pull to refresh: the account block's
    /// Time value label shows its one-word read for a few seconds (Nik, 16 Oct 2026).
    private(set) var readTick = 0
    private var lastPulse: Date?
    /// Legs bought, sold, closed or resized since the last update, and the
    /// toast's count: "Positions updated · 3 changed". Price moves are not a
    /// change (Nik, 14 Oct 2026: on every tick they were "just noise").
    private(set) var changedLegs: Set<String> = []
    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?
    private(set) var health: Health = .fresh
    private(set) var loadError: String?

    private var inFlight: Task<Void, Never>?
    private var lastAttemptFailedOffline = false
    private let path = NWPathMonitor()

    init() {
        // Back online: refresh at once (block 01).
        path.pathUpdateHandler = { [weak self] p in
            guard p.status == .satisfied else { return }
            Task { @MainActor in
                guard let self, self.health == .offline else { return }
                await self.refresh(.tick)
            }
        }
        path.start(queue: DispatchQueue(label: "sunny.path"))
    }

    // MARK: Loading

    /// One fetch; a second caller waits for the one already running.
    enum Reason { case open, pull, tick }

    func refresh(_ reason: Reason = .pull) async {
        if let t = inFlight {
            await t.value
            if reason != .tick, let h = home { words = h }
            if reason == .pull { readTick += 1 }
            return
        }
        let t = Task { await self.fetch(reason) }
        inFlight = t
        await t.value
        inFlight = nil
        if reason == .pull { readTick += 1 }
    }

    private func fetch(_ reason: Reason) async {
        do {
            let data = try await Self.source()
            let payload = try Self.decoder.decode(Row.self, from: data).payload
            if let old = home, reason == .tick || reason == .pull {
                let before = Dictionary(old.legs.map { ($0.id, $0.n) }, uniquingKeysWith: +)
                let after = Dictionary(payload.legs.map { ($0.id, $0.n) }, uniquingKeysWith: +)
                let changed = Set(after.keys.filter { before[$0] != after[$0] })
                    .union(before.keys.filter { after[$0] == nil })
                changedLegs = changed
                if !changed.isEmpty { showToast("Positions updated · \(changed.count) changed") }
            }
            home = payload
            if reason != .tick || words == nil || !MarketClock.isRegular(SClock.now(), calendar: payload.calendar) {
                words = payload
            }
            lastGood = SClock.now()
            tick += 1
            // The glow keeps its 30 s rhythm when updates come every 15 s (Nik).
            if MarketClock.inSession(SClock.now(), calendar: payload.calendar),
               lastPulse.map({ SClock.now().timeIntervalSince($0) >= 28 }) ?? true {
                livePulse += 1
                lastPulse = SClock.now()
            }

            health = .fresh
            loadError = nil
            lastAttemptFailedOffline = false
            #if DEBUG && targetEnvironment(simulator)
            if let ago = DebugPreset.double("store.ago") { lastGood = SClock.now().addingTimeInterval(-ago) }
            switch DebugPreset.string("store.health") {
            case "notUpdating": health = .notUpdating
            case "offline": health = .offline
            case "cantReach": health = .cantReach
            default: break
            }
            if let t = DebugPreset.string("store.toast") { showToast(t.replacingOccurrences(of: "_", with: " "), hold: 600) }
            #endif
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

    private func showToast(_ t: String, hold: Double = 2) {
        toastTask?.cancel()
        toast = t
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            self.toast = nil
            self.changedLegs = []
        }
    }

    // MARK: The 30 s clock

    /// Runs while the app is active. Ticks only inside a session; the caller
    /// cancels it when the scene leaves the foreground.
    func live() async {
        if let g = lastGood, SClock.now().timeIntervalSince(g) < 30, home != nil {
            // Fresh enough: the clock starts from the last good update.
        } else {
            await refresh(.open)
        }
        readTick += 1
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.untilNextBuild(calendar: home?.calendar ?? [])))
            if Task.isCancelled { break }
            if MarketClock.inSession(SClock.now(), calendar: home?.calendar ?? []) {
                await refresh(.tick)
                updateHealth()
            } else if let h = home, MarketClock.ny(SClock.now()).date != h.today {
                // Midnight New York: the deck and the day's words move on.
                await refresh(.open)
            }
        }
    }

    /// Seconds to the next server rebuild plus a beat: sunny-home builds at
    /// :06 :21 :36 :51 in the regular session and :06 :36 otherwise, so the
    /// app asks at :08 :23 :38 :53 (or :08 :38).
    static func untilNextBuild(calendar: [CalendarDay]) -> Double {
        let step = MarketClock.isRegular(SClock.now(), calendar: calendar) ? 15.0 : 30.0
        let now = SClock.now().timeIntervalSince1970, offset = 8.0
        var next = offset + (((now - offset) / step).rounded(.down) + 1) * step
        if next - now < 1 { next += step }
        return next - now
    }

    /// Open and nothing good for 90 s: the pill turns red (block 01).
    private func updateHealth() {
        guard let g = lastGood else { return }
        if SClock.now().timeIntervalSince(g) > 90, health == .fresh { health = .notUpdating }
    }
}
