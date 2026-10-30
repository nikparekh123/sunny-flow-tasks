//
//  SearchStore.swift
//  Sunny
//
//  What Search has open (block 27): the suggestions (Nik, 28 Oct 2026: in
//  place of your last 10, picked from the book each time Search opens), what
//  you are typing, the voice, and the thread of answers. A follow-up chip, or
//  a question that starts with And, What about or How about, adds to the
//  thread; anything else starts fresh. Back (or a swipe from the left edge)
//  leaves Search for the tab you came from, after closing the microphone sheet
//  or stopping the voice; Search opens fresh on the suggestions next time.
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

    private(set) var suggestions: [SXSuggestion] = []
    /// Words the listening should expect: the book's tickers, their names, its terms.
    private(set) var hints: [String] = []
    private(set) var entries: [Entry] = []
    var query = ""
    var typing = false
    /// Read aloud: the entry being read.
    var speaking: UUID?
    /// Scroll to this entry when an answer starts (nil scrolls to the top).
    private(set) var jump: UUID?
    private(set) var jumpTick = 0
    /// The last press and hold on the search button that opened listening.
    var listenSeen = 0

    // MARK: Loading

    /// Search opens fresh on the suggestions each time (Nik, 28 Oct 2026: back leaves Search, so the last
    /// conversation does not wait behind it).
    func open() {
        entries = []
        jump = nil
        Task { await loadSuggestions() }
    }

    /// Up to six questions picked from the book now, each with why it is there.
    func loadSuggestions() async {
        if let r: SuggestReply = try? await SXClient.post(["suggest": true]) { suggestions = r.suggestions; hints = r.hints ?? [] }
    }

    // MARK: Asking

    /// Whether a typed question carries on the thread (it starts with And, What about, How about or Also).
    func continues(_ q: String) -> Bool {
        !entries.isEmpty && q.range(of: #"^(and|what about|how about|also)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// spoken: the words came from the voice, so Sunny reads a misheard word for what was meant.
    func ask(_ raw: String, cont: Bool? = nil, spoken: Bool = false) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let keep = cont ?? continues(q)
        let thread = keep ? threadText() : []
        let e = Entry(q: q)
        if keep { entries.append(e) } else { entries = [e] }
        query = ""
        typing = false
        jump = keep ? e.id : nil
        jumpTick += 1
        // The question moves to the top of your searches at once; the server keeps the real list.
        Task { await run(e.id, q, thread, deep: false, spoken: spoken) }
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

    private func run(_ id: UUID, _ q: String, _ thread: [[String: String]], deep: Bool, spoken: Bool = false) async {
        // The request's id: the server keeps the answer under it, so one lost on the way is fetched again.
        let rid = UUID().uuidString
        do {
            let a = try await SXClient.ask(q, thread: thread, deep: deep, spoken: spoken, rid: rid) { [weak self] step, work in
                guard let self, let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
                let cur = deep ? self.entries[i].deep : self.entries[i].phase
                // Sunny's own data shows the soft pulse; live data, research and the web say what they are doing.
                if work || { if case .working = cur { return true }; return false }() {
                    if case .working = cur {} else { self.entries[i].bar = Date.now.timeIntervalSinceReferenceDate }
                    self.set(id, deep: deep, .working(step))
                }
            }
            set(id, deep: deep, .done(a))
        } catch {
            // The connection dropped while the server finished (29 Oct 2026): ask for the saved answer every 2 s for
            // up to 40 s, telling the server what went wrong here so it is on record.
            let why = (error as NSError).localizedDescription + " [\((error as NSError).domain) \((error as NSError).code)]"
            for _ in 0..<20 {
                if let r: RecoverReply = try? await SXClient.post(["answer_for": rid, "client_error": why]), let a = r.answer {
                    set(id, deep: deep, .done(a)); return
                }
                try? await Task.sleep(for: .seconds(2))
            }
            set(id, deep: deep, .done(SXAnswer(parts: [.none(why: "Sunny couldn't reach your data just now. Try again in a moment.", didYouMean: nil)])))
        }
    }

    private struct RecoverReply: Decodable { let answer: SXAnswer? }

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

    private struct SuggestReply: Decodable { let suggestions: [SXSuggestion]; let hints: [String]? }
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
    static func ask(_ q: String, thread: [[String: String]], deep: Bool, spoken: Bool = false, rid: String = UUID().uuidString,
                    step: @escaping @MainActor (String, Bool) -> Void) async throws -> SXAnswer {
        let (bytes, _) = try await URLSession.shared.bytes(for: try await request(["ask": q, "thread": thread, "deep": deep, "voice": spoken, "rid": rid, "stream": true, "draws": ["whatif"]]))
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
