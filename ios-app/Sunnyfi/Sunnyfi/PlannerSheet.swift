import Foundation

/// The `sheet` block of one `tlt-planner` response.
///
/// Typed against a LIVE response, not against the design fixture. That distinction
/// has already cost a day once: an optional tolerates a *missing* key but never a
/// *wrong* one, so a field modelled from a hand-written sample decodes cleanly in
/// the sample and fails silently against the server.
///
/// The engine owns every string here — including its emphasis markers. Nothing in
/// the view formats, rounds, or assembles a sentence. See docs/TLT_ACCUMULATION.md.
struct PlannerSheet: Decodable {
    let ticker: String
    let boot: Boot?
    let asOf: AsOf
    let phase: String
    let instruction: Instruction
    /// The second card. Same shape as `instruction` so one renderer draws both.
    /// Optional so a deploy that predates it still decodes to a single card.
    let callCard: CallCard?
    /// The call card's explanation, moved out of its stat labels so the two swipe
    /// cards stay the same height. Same shape as `why`, so it reuses that renderer.
    let cover: Why?
    let ladder: Ladder
    let tonight: Tonight?          // null when nothing is expiring
    let holdback: Holdback?        // null when the calendar is not damping
    let calls: Calls
    let why: Why
    let position: Where            // `where` is a Swift keyword — remapped below
    let progress: Progress
    let ceiling: Ceiling
    let conviction: Conviction
    let coming: Coming
    let book: Book
    let sources: Sources

    enum CodingKeys: String, CodingKey {
        case ticker, boot, asOf, phase, instruction, callCard, cover, ladder, tonight, holdback, calls, why
        case position = "where"
        case progress, ceiling, conviction, coming, book, sources
    }

    struct AsOf: Decodable {
        let label: String
        let refresh: String
        /// Optional so a function deploy that predates it still decodes; the head
        /// falls back to the spot freshness stamp when it is absent.
        let market: Market?
        struct Market: Decodable { let open: Bool; let label: String }
    }

    /// Deliberately mirrors Instruction rather than sharing it: the two cards are
    /// free to diverge, and `when` exists only here.
    struct CallCard: Decodable {
        let label: String, verb: String, meta: String
        let commit: [[String]]
        let basis: Instruction.Pair
        let earn: Instruction.Earn
        let mark: String?
        let when: String?

        /// The two cards render identically, so the call card borrows the hero.
        var asInstruction: Instruction {
            .init(label: label, verb: verb, meta: meta, commit: commit,
                  basis: basis, earn: earn, mark: mark)
        }
    }

    struct Instruction: Decodable {
        let label: String, verb: String, meta: String
        /// [[figure, caption], …] — homogeneous, so a plain nested array decodes.
        let commit: [[String]]
        let basis: Pair
        let earn: Earn
        let mark: String?
        struct Pair: Decodable { let value: String; let label: String }
        struct Earn: Decodable { let value: String; let label: String }
    }

    struct Ladder: Decodable {
        let label: String
        let rows: [Row]
        let verdict: String?
        let fallback: Fallback?
        struct Row: Decodable {
            let strike: String, detail: String, basis: String
            let chosen: Bool
        }
        struct Fallback: Decodable { let state: String; let headline: String; let note: String }
    }

    struct Tonight: Decodable {
        let label: String, tag: String, headline: String
        let lines: [String]
        let foot: String?
    }

    struct Holdback: Decodable {
        let label: String, action: String, headline: String, cause: String, note: String
    }

    struct Calls: Decodable {
        let label: String
        let lines: [Line]
        let note: String
        /// `["they cost money and shares", "in a rally"]` — but the FIRST line ships
        /// as `["…", null]`. A nullable tail in a JSON array needs the unkeyed
        /// container; `[String]` would throw on the null and take the whole sheet
        /// down with it.
        struct Line: Decodable {
            let text: String
            let emphasis: String?
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                text = try c.decode(String.self)
                if c.isAtEnd { emphasis = nil }
                else if try c.decodeNil() { emphasis = nil }
                else { emphasis = try c.decode(String.self) }
            }
        }
    }

    struct Why: Decodable {
        let label: String
        let chain: [Step]
        let verdict: String
        struct Step: Decodable { let text: String; let out: String }
    }

    struct Where: Decodable { let label: String; let headline: String; let lines: [String] }

    struct Progress: Decodable {
        let label: String
        let rows: [Row]
        let standing: String
        let band: String
        struct Row: Decodable { let label: String; let value: String; let pct: Double; let note: String }
    }

    struct Ceiling: Decodable {
        let label: String, head: String, value: String, of: String
        let pct: Double
        let room: String, before: String, state: String
        let cut: String?
    }

    struct Conviction: Decodable {
        let label: String
        let score: Int, base: Int, calendar: Int
        let movers: String
        let normalised: String?
        let families: [Family]
        struct Family: Decodable {
            let label: String, score: String, cap: String
            let pct: Double
            let read: String
            let top: Bool?, damper: Bool?, down: String?
            var isTop: Bool { top == true }
            var isDamper: Bool { damper == true }
        }
    }

    struct Coming: Decodable {
        let label: String
        let events: [Event]
        /// `["Aug 12", "CPI · July", true]` — String, String, Bool in one array.
        /// Heterogeneous, so this cannot be `[[String]]`.
        struct Event: Decodable {
            let date: String, what: String, isToday: Bool
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                date = try c.decode(String.self)
                what = try c.decode(String.self)
                isToday = c.isAtEnd ? false : ((try? c.decode(Bool.self)) ?? false)
            }
        }
    }

    struct Book: Decodable {
        let label: String
        let legs: [Leg]
        struct Leg: Decodable { let qty: String; let leg: String; let when: String }
    }

    struct Boot: Decodable { let stages: [String]; let mark: String? }

    struct Sources: Decodable {
        let label: String
        /// [[name, kind, age], …] — all strings, so the nested array is safe here.
        let rows: [[String]]
    }
}

private struct Progress: Decodable {
    let stages: [String]?
    let stage: Int?
}

private struct PlannerResponse: Decodable {
    let ok: Bool?
    let sheet: PlannerSheet?
    let error: String?
}

// MARK: - Store

@Observable
@MainActor
final class PlannerSheetStore {
    /// Which edge function to read. NVDA and TLT return the SAME 17-section sheet —
    /// verified field by field, no key differs — so one model and one screen serve
    /// both and the ticker is the only thing that varies.
    private let function: String

    init(function: String) { self.function = function }

    private(set) var sheet: PlannerSheet?
    private(set) var loading = false
    /// Named rather than swallowed. A blank screen that says nothing is the one
    /// failure mode that costs an afternoon — a decode mismatch should say which
    /// key and which type, on screen.
    private(set) var decodeError: String?

    /// Stage list and index, driven by the engine's NDJSON progress lines. Never by
    /// a timer: the boot layer's whole claim is that a stage completing means that
    /// step completed, and a client cannot see inside one atomic fetch.
    private(set) var stages: [String] = []
    private(set) var stage = 0
    var booting: Bool { sheet == nil && decodeError == nil }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        decodeError = nil
        stage = 0

        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/\(function)") else {
            decodeError = "bad url"; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data(#"{"stream":true}"#.utf8)

        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                decodeError = "HTTP \(http.statusCode)"
                return
            }
            let dec = JSONDecoder()
            // A function that has not been redeployed yet ignores `stream` and answers
            // with one unbroken JSON body. That arrives as a single line and decodes
            // here exactly the same way, so an old deploy degrades to no progress
            // rather than to no sheet.
            for try await line in bytes.lines {
                guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                if let p = try? dec.decode(Progress.self, from: data) {
                    if let st = p.stages { stages = st }
                    if let n = p.stage { stage = n }
                    if p.stages != nil || p.stage != nil { continue }
                }
                let parsed = try dec.decode(PlannerResponse.self, from: data)
                if let sh = parsed.sheet {
                    if stages.isEmpty, let b = sh.boot { stages = b.stages }
                    stage = max(stage, stages.count)
                    sheet = sh
                } else {
                    decodeError = parsed.error ?? "no sheet in response"
                }
            }
            if sheet == nil && decodeError == nil { decodeError = "stream ended with no sheet" }
        } catch let DecodingError.keyNotFound(key, ctx) {
            decodeError = "missing key '\(key.stringValue)' at \(path(ctx))"
        } catch let DecodingError.typeMismatch(type, ctx) {
            decodeError = "expected \(type) at \(path(ctx))"
        } catch let DecodingError.valueNotFound(type, ctx) {
            decodeError = "null where \(type) expected at \(path(ctx))"
        } catch {
            decodeError = error.localizedDescription
        }
    }

    private func path(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.map(\.stringValue).joined(separator: ".")
    }
}
