//
//  SearchStore.swift
//  Sunny
//
//  What Search has open (block 27): your last 10 (kept on the server per
//  login, so they follow you across days and devices), what you are typing,
//  the voice, and the thread of answers. A follow-up chip, or a question
//  that starts with And, What about or How about, adds to the thread;
//  anything else starts fresh. Answers and threads clear each morning at
//  9:00 AM New York time; the last 10 stay, and tapping one asks again with
//  today's numbers. Back steps out one level at a time: voice, typing, the
//  answer, your searches, then the tab you came from.
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class SearchStore {
    struct Entry: Identifiable, Equatable {
        enum Phase: Equatable { case loading, working(String), done(SXAnswer), failed }
        let id = UUID()
        let q: String
        var phase: Phase = .loading
        var deep: Phase?
        var feedback: String?
        var notAsked = false
        var bar = 0.0           // the Working it out bar's start, for its fill
    }

    private(set) var recents: [SXRecent] = []
    private(set) var recentsLoaded = false
    private(set) var questions: [String] = []
    private(set) var tries: [String] = []
    private(set) var entries: [Entry] = []
    var query = ""
    var typing = false
    /// Read aloud: the entry being read.
    var speaking: UUID?
    /// Scroll to this entry when an answer starts (nil scrolls to the top).
    private(set) var jump: UUID?
    private(set) var jumpTick = 0
    private var threadDay: Date?
    /// The last press and hold on the search button that opened listening.
    var listenSeen = 0

    // MARK: Loading

    func open() {
        clearIfMorningPassed()
        Task { await loadRecents() }
        if questions.isEmpty { Task { await loadQuestions() } }
    }

    func loadRecents() async {
        if let r: RecentsReply = try? await SXClient.post(["recents": true]) { recents = r.recents }
        recentsLoaded = true
    }

    private func loadQuestions() async {
        if let r: QuestionsReply = try? await SXClient.post(["questions": true]) { questions = r.questions; tries = r.tries }
    }

    /// Threads clear each morning at 9:00 AM New York: an answer from before the latest 9:00 AM goes.
    private func clearIfMorningPassed() {
        guard let born = threadDay, born < Self.lastNineAM() else { return }
        entries = []
        threadDay = nil
    }
    static func lastNineAM(_ now: Date = .now) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        return nine <= now ? nine : cal.date(byAdding: .day, value: -1, to: nine)!
    }

    // MARK: Asking

    /// Whether a typed question carries on the thread (it starts with And, What about, How about or Also).
    func continues(_ q: String) -> Bool {
        !entries.isEmpty && q.range(of: #"^(and|what about|how about|also)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    func ask(_ raw: String, cont: Bool? = nil) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let keep = cont ?? continues(q)
        let thread = keep ? threadText() : []
        let e = Entry(q: q)
        if keep { entries.append(e) } else { entries = [e]; threadDay = .now }
        query = ""
        typing = false
        jump = keep ? e.id : nil
        jumpTick += 1
        // The question moves to the top of your searches at once; the server keeps the real list.
        Task { await run(e.id, q, thread, deep: false) }
    }

    func goDeeper(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }), case .done(let a) = entries[i].phase, entries[i].deep == nil else { return }
        entries[i].deep = .loading
        let thread = threadText(upTo: i) + [["q": entries[i].q, "a": a.recap ?? a.spoken]]
        Task { await run(id, entries[i].q, thread, deep: true) }
    }

    private func threadText(upTo end: Int? = nil) -> [[String: String]] {
        entries.prefix(end ?? entries.count).suffix(6).compactMap { e in
            guard case .done(let a) = e.phase else { return nil }
            return ["q": e.q, "a": a.recap ?? a.spoken]
        }
    }

    private func set(_ id: UUID, deep: Bool, _ p: Entry.Phase) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        if deep { entries[i].deep = p } else { entries[i].phase = p }
    }

    private func run(_ id: UUID, _ q: String, _ thread: [[String: String]], deep: Bool) async {
        do {
            let a = try await SXClient.ask(q, thread: thread, deep: deep) { [weak self] step, work in
                guard let self, let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
                let cur = deep ? self.entries[i].deep : self.entries[i].phase
                // Sunny's own data shows the soft pulse; live data, research and the web say what they are doing.
                if work || { if case .working = cur { return true }; return false }() {
                    if case .working = cur {} else { self.entries[i].bar = Date.now.timeIntervalSinceReferenceDate }
                    self.set(id, deep: deep, .working(step))
                }
            }
            set(id, deep: deep, .done(a))
            if !deep { await loadRecents() }
        } catch {
            set(id, deep: deep, .done(SXAnswer(parts: [.none(why: "Sunny couldn't reach your data just now. Try again in a moment.", didYouMean: nil)])))
        }
    }

    // MARK: Feedback

    func thumb(_ id: UUID, _ v: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let next = entries[i].feedback == v ? nil : v
        entries[i].feedback = next
        send(i, next ?? "")
    }

    func notAsked(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }), !entries[i].notAsked else { return }
        entries[i].notAsked = true
        send(i, "not_asked")
    }

    private func send(_ i: Int, _ v: String) {
        guard case .done(let a) = entries[i].phase, let aid = a.id else { return }
        Task { let _: OkReply? = try? await SXClient.post(["feedback": ["id": aid, "value": v]]) }
    }

    // MARK: Back

    var listening = false

    /// One level back: typing, then the answers, then your searches. False when there is nothing left (go to the tab).
    func back() -> Bool {
        if typing || !query.isEmpty { query = ""; typing = false; return true }
        if !entries.isEmpty { entries = []; threadDay = nil; jump = nil; jumpTick += 1; return true }
        return false
    }

    // MARK: Suggestions while typing

    struct Suggestion: Identifiable { let id: String; let recent: SXRecent?; let a: String, b: String, c: String }

    /// The first row asks exactly what was typed; then past searches that match (up to 3), then questions that work,
    /// six rows at most, the typed words split out so they show in gray.
    func suggestions() -> (rows: [Suggestion], noMatch: Bool) {
        let q = query.trimmingCharacters(in: .whitespaces)
        let nq = norm(q), words = nq.split(separator: " ").map(String.init)
        let hit = { (t: String) in words.allSatisfy { self.norm(t).contains($0) } }
        func seg(_ t: String) -> (String, String, String) {
            guard let r = norm(t).range(of: nq) else { return (t, "", "") }
            let lo = norm(t).distance(from: norm(t).startIndex, to: r.lowerBound), n = q.count
            let s = Array(t)
            return (String(s[..<lo]), String(s[lo..<min(s.count, lo + n)]), String(s[min(s.count, lo + n)...]))
        }
        let rec = recents.filter { hit($0.q) }.prefix(3)
        let seen = Set(rec.map { norm($0.q) })
        let sug = questions.filter { hit($0) && !seen.contains(norm($0)) }.prefix(6 - rec.count)
        var rows = [Suggestion(id: "ask", recent: nil, a: "", b: "", c: q)]
        rows += rec.map { let (a, b, c) = seg($0.q); return Suggestion(id: "r\($0.id)", recent: $0, a: a, b: b, c: c) }
        rows += sug.map { let (a, b, c) = seg($0); return Suggestion(id: "q" + $0, recent: nil, a: a, b: b, c: c) }
        return (rows, rec.isEmpty && sug.isEmpty)
    }

    private func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'") }

    private struct RecentsReply: Decodable { let recents: [SXRecent] }
    private struct QuestionsReply: Decodable { let questions: [String]; let tries: [String] }
    private struct OkReply: Decodable { let ok: Bool }
}

// MARK: - The network

enum SXClient {
    static let url = URL(string: Secrets.supabaseURL + "/functions/v1/sunny-search")!

    private static func request(_ body: [String: Any]) async throws -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 120)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        #if DEBUG && targetEnvironment(simulator)
        // Screens checked without signing in (-skipAuth): the scheduler's key, passed at launch, never stored.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-searchKey"), i + 1 < args.count {
            r.setValue(args[i + 1], forHTTPHeaderField: "x-cron-key")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            return r
        }
        #endif
        let token = try await SupabaseService.client.auth.session.accessToken
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let x = parseDate(s) { return x }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "date \(s)"))
        }
        return d
    }()

    /// Postgres times ("2026-10-28T14:43:10.123456+00:00"): ISO 8601, the fraction cut to milliseconds.
    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cut = s.replacing(/(\.\d{3})\d+/) { $0.output.1 }
        if let d = f.date(from: cut) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func post<T: Decodable>(_ body: [String: Any]) async throws -> T {
        let (data, _) = try await URLSession.shared.data(for: try await request(body))
        return try decoder.decode(T.self, from: data)
    }

    /// Asks, streamed: one line per step while it reads, the answer last.
    static func ask(_ q: String, thread: [[String: String]], deep: Bool,
                    step: @escaping @MainActor (String, Bool) -> Void) async throws -> SXAnswer {
        let (bytes, _) = try await URLSession.shared.bytes(for: try await request(["ask": q, "thread": thread, "deep": deep, "stream": true]))
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let s = o["step"] as? String { await step(s, o["work"] as? Bool ?? false) }
            if let a = o["answer"] {
                return try decoder.decode(SXAnswer.self, from: JSONSerialization.data(withJSONObject: a))
            }
            if let e = o["error"] as? String { throw NSError(domain: "sunny-search", code: 1, userInfo: [NSLocalizedDescriptionKey: e]) }
        }
        throw URLError(.badServerResponse)
    }
}
