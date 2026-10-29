//
//  SearchModels.swift
//  Sunny
//
//  Search at launch (handoff "Search for launch", block 27, 28 Oct 2026):
//  what sunny-search sends back. Answers are text only: a lead sentence, a
//  big number or three numbers, lines, an explanation, From the web, one
//  panel per topic for an update on one name, or a plain "can't answer".
//  Every figure in them was written by Sunny from its own data, never by
//  the model; the text marks numbers {b:x} bold, {g:x} green, {r:x} red and
//  {o:x} orange.
//

import SwiftUI

struct SXAnswer: Decodable, Equatable {
    let id: Int?
    let parts: [SXPart]
    let source: SXSource?
    let followUps: [String]
    let recap: String?
    let canAnswer: Bool

    enum CodingKeys: String, CodingKey { case id, parts, source, followUps = "follow_ups", recap, canAnswer = "can_answer" }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        parts = (try? c.decode([SXPart].self, forKey: .parts)) ?? []
        source = try? c.decodeIfPresent(SXSource.self, forKey: .source)
        followUps = (try? c.decode([String].self, forKey: .followUps)) ?? []
        recap = try? c.decodeIfPresent(String.self, forKey: .recap)
        canAnswer = (try? c.decode(Bool.self, forKey: .canAnswer)) ?? false
    }
    init(parts: [SXPart]) { id = nil; self.parts = parts; source = nil; followUps = []; recap = nil; canAnswer = false }

    /// The words Read aloud speaks, in screen order, without the colour marks.
    var spoken: String {
        parts.map(\.spoken).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct SXSource: Decodable, Equatable { let kind: String; let text: String }

struct SXItem: Decodable, Equatable {
    let label: String?, value: String?, sub: String?, tone: String?, subTone: String?
    enum CodingKeys: String, CodingKey { case label, value, sub, tone, subTone = "sub_tone" }
}

struct SXBar: Decodable, Equatable { let from: Double, to: Double, at: Double }

struct SXRow: Decodable, Equatable {
    let a: String?, b: String?, r: String?, aTone: String?, bTone: String?, rTone: String?, sub: String?, bar: SXBar?
    enum CodingKeys: String, CodingKey { case a, b, r, aTone = "a_tone", bTone = "b_tone", rTone = "r_tone", sub, bar }
}

struct SXTable: Decodable, Equatable {
    struct Row: Decodable, Equatable { let label: String?; let values: [String?]; let tone: String? }
    let cols: [String]
    let rows: [Row]
}

struct SXWebSource: Decodable, Equatable { let site: String; let url: String; let title: String; let date: String? }

enum SXPart: Decodable, Equatable {
    case say(String)
    case body(String)
    case big(label: String?, value: String, n: Double?, count: Bool, fmt: String, sub: String?, tone: String?)
    case trio([SXItem])
    case rows(head: String?, rows: [SXRow])
    case panel(title: String?, say: String?, trio: [SXItem]?, rows: [SXRow]?, table: SXTable?, note: String?, source: SXSource?)
    case web(summary: String, sources: [SXWebSource], line: String)
    /// The payoff card (block 28): one name, what was sold, or the book by Friday.
    case payoff(SXPayoff)
    case none(why: String?, didYouMean: String?)

    private enum K: String, CodingKey {
        case type, text, label, value, n, count, fmt, sub, tone, items, head, rows, title, say, trio, table, note, source
        case summary, sources, line, why, didYouMean = "did_you_mean"
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        let s = { (k: K) in (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
        switch try c.decode(String.self, forKey: .type) {
        case "say": self = .say(s(.text) ?? "")
        case "body": self = .body(s(.text) ?? "")
        case "big":
            self = .big(label: s(.label), value: s(.value) ?? "", n: try? c.decodeIfPresent(Double.self, forKey: .n),
                        count: (try? c.decodeIfPresent(Bool.self, forKey: .count)) ?? false, fmt: s(.fmt) ?? "",
                        sub: s(.sub), tone: s(.tone))
        case "trio": self = .trio((try? c.decode([SXItem].self, forKey: .items)) ?? [])
        case "rows": self = .rows(head: s(.head), rows: (try? c.decode([SXRow].self, forKey: .rows)) ?? [])
        case "panel":
            self = .panel(title: s(.title), say: s(.say), trio: try? c.decodeIfPresent([SXItem].self, forKey: .trio),
                          rows: try? c.decodeIfPresent([SXRow].self, forKey: .rows), table: try? c.decodeIfPresent(SXTable.self, forKey: .table),
                          note: s(.note), source: try? c.decodeIfPresent(SXSource.self, forKey: .source))
        case "web":
            self = .web(summary: s(.summary) ?? "", sources: (try? c.decode([SXWebSource].self, forKey: .sources)) ?? [], line: s(.line) ?? "From the web")
        case "payoff":
            // A card that will not read is left out; the sentence above it still stands.
            self = (try? SXPayoff(from: d)).map { .payoff($0) } ?? .rows(head: nil, rows: [])
        default: self = .none(why: s(.why), didYouMean: s(.didYouMean))
        }
    }

    var spoken: String {
        let p = SXText.plain
        switch self {
        case .say(let t), .body(let t): return p(t)
        case .big(let label, let value, _, _, _, let sub, _): return [label.map { $0 + ":" }, value, sub].compactMap { $0 }.joined(separator: " ") + "."
        case .trio(let xs): return xs.map { "\($0.label ?? "") \($0.value ?? "")" }.joined(separator: ". ") + "."
        case .rows: return ""
        case .panel(let title, let say, _, _, _, _, _): return say.map { "\(title ?? ""). \(p($0))" } ?? ""
        case .web(let summary, _, _): return "From the web: " + summary
        case .payoff: return ""
        case .none(let why, _): return "I can't answer that from your data. " + (why ?? "")
        }
    }
}

/// A question Search suggests, and why it is there ("NKE reports Nov 4").
struct SXSuggestion: Decodable, Equatable, Identifiable {
    let q: String
    let why: String
    var id: String { q }
}

// MARK: - Text marks

enum SXText {
    /// {b:x} bold ink, {g:x} green, {r:x} red, {o:x} orange; all four bold.
    static let mark = /\{([gbro]):([^}]*)\}/

    static func plain(_ s: String) -> String { s.replacing(mark) { String($0.output.2) } }

    /// The text with its marks as bold, coloured runs.
    static func styled(_ s: String, bold: Font? = nil) -> AttributedString {
        var out = AttributedString()
        var rest = s[...]
        while let m = rest.firstMatch(of: mark) {
            out += AttributedString(String(rest[rest.startIndex..<m.range.lowerBound]))
            var run = AttributedString(String(m.output.2))
            run.foregroundColor = tone(String(m.output.1))
            run.inlinePresentationIntent = .stronglyEmphasized
            if let bold { run.font = bold }
            out += run
            rest = rest[m.range.upperBound...]
        }
        out += AttributedString(String(rest))
        return out
    }

    /// The same, the marked runs in the bold cut of the role's own size.
    static func styled(_ s: String, _ t: SXType, _ dts: DynamicTypeSize) -> AttributedString {
        styled(s, bold: SXScale.font(t.weighted(.bold), dts).monospacedDigit())
    }

    static func tone(_ k: String) -> Color {
        switch k { case "g": SX.up; case "r": SX.down; case "o": SX.thin; default: SX.ink }
    }
}
