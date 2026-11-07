//
//  BriefText.swift
//  Sunny
//
//  The words of New Home: rich spans (ledes, headlines, sentences with a bold green or red number), the
//  privacy mask, and a loose JSON value for the cards' content.
//
//  ⚠ PRIVACY MASKS MONEY, NEVER PRICES (block 33, AUDIT-LOG 5): every $ amount on a book card reads $•••,
//  but a price after "above", "below", "at", "near", "Today", "Avg", "Low" or "High" stays (prices are
//  market data), and the comma and space after a masked amount stay where they were.
//

import SwiftUI

// MARK: - A loose JSON value (cards carry whatever their design shows)

enum JSONValue: Decodable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }

    subscript(_ k: String) -> JSONValue { if case .object(let o) = self { return o[k] ?? .null }; return .null }
    subscript(_ i: Int) -> JSONValue { if case .array(let a) = self, a.indices.contains(i) { return a[i] }; return .null }

    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s):
            var t = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: "+", with: "").trimmingCharacters(in: .whitespaces)
            var mult = 1.0
            if let last = t.last, "KMB".contains(last) { mult = last == "K" ? 1e3 : last == "M" ? 1e6 : 1e9; t.removeLast() }
            return Double(t).map { $0 * mult }
        default: return nil
        }
    }
    var bool: Bool { if case .bool(let b) = self { return b }; return false }
    var array: [JSONValue] { if case .array(let a) = self { return a }; return [] }
    var object: [String: JSONValue] { if case .object(let o) = self { return o }; return [:] }
    var isNull: Bool { if case .null = self { return true }; return false }
    /// The keys in the order they were written are lost in a dictionary; cards that need order use arrays.
    var keys: [String] { object.keys.sorted() }
}

// MARK: - Spans

/// One run of a sentence: its text, bold or not, and its colour role.
struct BriefSpan: Hashable {
    var t: String
    var b = false
    var c: String? = nil

    init(_ t: String, b: Bool = false, c: String? = nil) { self.t = t; self.b = b; self.c = c }

    /// From the content JSON: an array of { t, b, c }, or a plain string (one ink run).
    static func list(_ v: JSONValue) -> [BriefSpan] {
        if let s = v.string, case .string = v { return [BriefSpan(s)] }
        return v.array.compactMap { x in
            if let s = x.string, case .string = x { return BriefSpan(s) }
            guard let t = x["t"].string else { return nil }
            return BriefSpan(t, b: x["b"].bool, c: x["c"].string)
        }
    }

    var color: Color {
        switch c {
        case "green": S.green
        case "red": S.red
        case "orange": S.act
        case "secondary", "muted": S.secondary
        default: S.ink
        }
    }
}

enum BriefWords {
    /// Spans as one Text: each run keeps its colour and weight; the base style comes from the caller.
    static func text(_ spans: [BriefSpan], base: SType, baseColor: Color = S.ink, boldWeight: CGFloat = 700,
                     privacy: Bool = false) -> Text {
        var a = AttributedString()
        for s in spans {
            var r = AttributedString(privacy ? BriefMask.mask(s.t) : s.t)
            let t = s.b ? base.weighted(boldWeight) : base
            r.font = t.font(tabular: true)
            r.foregroundColor = s.c == nil ? baseColor : s.color
            a += r
        }
        return Text(a)
    }

    /// A plain string with the mask applied when privacy is on.
    static func plain(_ s: String?, privacy: Bool) -> String { privacy ? BriefMask.mask(s ?? "") : (s ?? "") }
}

// MARK: - The privacy mask

enum BriefMask {
    /// Words that make the $ figure after them a price, not money.
    private static let priceWords: Set<String> = ["above", "below", "at", "near", "today", "avg", "low", "high", "under", "over", "from", "to"]

    static func mask(_ s: String) -> String {
        guard s.contains("$") else { return s }
        let ns = s as NSString
        let re = try! NSRegularExpression(pattern: #"\$\d[\d,]*(?:\.\d+)?[KMB]?"#)
        var out = s
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            // The word before the figure decides: a price stays.
            let before = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
            let prev = before.split(whereSeparator: { $0 == " " || $0 == "·" || $0 == "(" }).last.map { String($0).lowercased() } ?? ""
            if priceWords.contains(prev) || before.hasSuffix(":") && prev.hasSuffix(":") { continue }
            if let r = Range(m.range, in: out) { out.replaceSubrange(r, with: "$•••") }
        }
        return out
    }
}
