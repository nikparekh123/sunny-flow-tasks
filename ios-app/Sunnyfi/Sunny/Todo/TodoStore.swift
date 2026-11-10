//
//  TodoStore.swift
//  Sunny
//
//  To do (handoff 2026-11-10-todo): Nik's own notes, no trades. One list for the app and the web, kept in Supabase
//  (`public.todos`, migration 20261110150000). Nik, 10 Nov 2026: "only for me to see, not Nicolay": the table's RLS
//  lets only book S's owners (Nik's two logins) read or write it, and the app shows the To do link only to them, so
//  the cousin's login (book N only) never sees it. Writes land at once (the list shows them before the server
//  answers); a failed write reads the list again.
//
//  DEBUG, simulator only: `-todoSample` fills the list with the design's sample, dated from today, kept in memory.
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class TodoStore {
    static let shared = TodoStore()

    struct Item: Identifiable, Equatable, Decodable {
        let id: String
        var text: String
        var due: String?
        var note: String
        var done: Bool
        let created_at: String
    }

    private(set) var items: [Item] = []
    /// An owner of book S is signed in: the link shows and the list reads.
    private(set) var allowed = false
    /// Ticked in the last 1.2 s: still in the open list, faded and struck through, until it moves into Done.
    private(set) var linger: Set<String> = []

    var openCount: Int { items.filter { !$0.done }.count }
    /// Open first by date (overdue on top, no date last), ties in the order they were added; a just-ticked one stays.
    var open: [Item] {
        items.filter { !$0.done || linger.contains($0.id) }
            .sorted { ($0.due ?? "9999", $0.created_at) < ($1.due ?? "9999", $1.created_at) }
    }
    /// Done, in the order they were added (the design's), kept for good (Nik: forever).
    var finished: [Item] { items.filter { $0.done && !linger.contains($0.id) }.sorted { $0.created_at < $1.created_at } }

    private let sample: Bool = {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-todoSample")
        #else
        false
        #endif
    }()
    private var lingerTasks: [String: Task<Void, Never>] = [:]
    private var noteTasks: [String: Task<Void, Never>] = [:]

    private init() {
        if sample { allowed = true; items = Self.sampleItems(TodoDates.today()) }
    }

    // MARK: Reading

    /// Who may see it, and the list. Called when Home comes up, when the app comes back, and when the sheet opens.
    func refresh() async {
        guard !sample else { return }
        do {
            struct Member: Decodable { let book_id: String; let role: String }
            let ms: [Member] = try await SupabaseService.client.from("book_members").select("book_id,role")
                .eq("book_id", value: "S").eq("role", value: "owner").execute().value
            allowed = !ms.isEmpty
            guard allowed else { items = []; return }
            let rows: [Item] = try await SupabaseService.client.from("todos")
                .select("id,text,due,note,done,created_at").order("created_at").execute().value
            // A tick still lingering keeps its place until its 1.2 s are up.
            items = rows
        } catch {
            print("[Todo] refresh failed: \(error)")
        }
    }

    // MARK: Writing

    func add(_ text: String, due: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let local = Item(id: "local-\(UUID().uuidString)", text: t, due: due, note: "", done: false,
                         created_at: ISO8601DateFormatter().string(from: Date()))
        items.append(local)
        guard !sample else { return }
        Task {
            struct New: Encodable { let text: String; let due: String? }
            do {
                let row: Item = try await SupabaseService.client.from("todos").insert(New(text: t, due: due))
                    .select("id,text,due,note,done,created_at").single().execute().value
                if let i = items.firstIndex(where: { $0.id == local.id }) { items[i] = row }
            } catch { print("[Todo] add failed: \(error)"); await refresh() }
        }
    }

    /// The circle: a tick lingers 1.2 s in place (a second tap in that time takes it back), then moves into Done.
    func toggle(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        lingerTasks[id]?.cancel(); lingerTasks[id] = nil
        let done = !items[i].done
        items[i].done = done
        if done {
            linger.insert(id)
            lingerTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                self?.linger.remove(id)
            }
        } else {
            linger.remove(id)
        }
        write(id, Patch.done(done))
    }

    func setDue(_ id: String, _ due: String?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].due = due
        write(id, Patch.due(due))
    }

    /// The note saves 0.6 s after the last keystroke (and at once when the row closes: `flushNote`).
    func setNote(_ id: String, _ note: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].note != note else { return }
        items[i].note = note
        noteTasks[id]?.cancel()
        noteTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flushNote(id)
        }
    }
    func flushNote(_ id: String) {
        noteTasks[id]?.cancel(); noteTasks[id] = nil
        guard let x = items.first(where: { $0.id == id }) else { return }
        write(id, Patch.note(x.note))
    }

    /// Delete has no undo (Nik, 10 Nov 2026).
    func delete(_ id: String) {
        items.removeAll { $0.id == id }
        linger.remove(id)
        guard !sample, !id.hasPrefix("local-") else { return }
        Task {
            do { try await SupabaseService.client.from("todos").delete().eq("id", value: id).execute() }
            catch { print("[Todo] delete failed: \(error)"); await refresh() }
        }
    }

    /// One field written as is (a null due clears the date).
    private enum Patch: Encodable {
        case done(Bool), due(String?), note(String)
        enum K: String, CodingKey { case done, due, note }
        func encode(to e: Encoder) throws {
            var c = e.container(keyedBy: K.self)
            switch self {
            case .done(let b): try c.encode(b, forKey: .done)
            case .due(let d): try c.encode(d, forKey: .due)
            case .note(let n): try c.encode(n, forKey: .note)
            }
        }
    }
    private func write(_ id: String, _ p: Patch) {
        guard !sample, !id.hasPrefix("local-") else { return }
        Task {
            do { try await SupabaseService.client.from("todos").update(p).eq("id", value: id).execute() }
            catch { print("[Todo] update failed: \(error)"); await refresh() }
        }
    }

    // MARK: The design's sample (a -todoSample run)

    private static func sampleItems(_ t: String) -> [Item] {
        // The design's list, its dates moved so its today (Tue Oct 27) is ours.
        let rows: [(String, Int?, String, Bool)] = [
            ("Download the September statements", -1, "", false), ("Call IBKR about the margin rate", 0, "Ask what the rate is over $250K", false),
            ("Check the NKE ex-dividend date before Friday", 2, "", false), ("Move cash over for the Jan calls", 3, "About $12K from savings", false),
            ("Read the BABA earnings preview", 7, "", false), ("Look at LULU again after the holidays", 69, "", false),
            ("Set up the 2026 tax lot report", nil, "", false), ("Renew the market data subscription", -4, "", true), ("Update the watchlist", nil, "", true),
        ]
        return rows.enumerated().map { i, r in
            Item(id: "s\(i)", text: r.0, due: r.1.map { TodoDates.plus(t, $0) }, note: r.2, done: r.3, created_at: String(format: "2026-10-01T00:00:%02dZ", i))
        }
    }
}
