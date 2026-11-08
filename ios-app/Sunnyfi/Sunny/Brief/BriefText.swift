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
    /// When privacy masks an amount, VoiceOver reads the whole sentence with "hidden" in place of each $•••
    /// (Pass 5: it read "dollar bullet bullet bullet"). The label is set on the Text itself, so it holds
    /// inside a parent that combines its children too.
    static func text(_ spans: [BriefSpan], base: SType, baseColor: Color = S.ink, boldWeight: CGFloat = 700,
                     privacy: Bool = false) -> Text {
        var a = AttributedString()
        var said = "", masked = false
        for s in spans {
            let shown = privacy ? BriefMask.mask(s.t) : s.t
            if shown != s.t { masked = true }
            said += shown
            var r = AttributedString(shown)
            let t = s.b ? base.weighted(boldWeight) : base
            r.font = t.font(tabular: true)
            r.foregroundColor = s.c == nil ? baseColor : s.color
            a += r
        }
        let t = Text(a)
        return masked ? t.accessibilityLabel(BriefMask.spoken(said)) : t
    }

    /// A plain string with the mask applied when privacy is on.
    static func plain(_ s: String?, privacy: Bool) -> String { privacy ? BriefMask.mask(s ?? "") : (s ?? "") }

    /// The same string as VoiceOver should say it: each masked amount reads "hidden". For an
    /// `.accessibilityLabel` next to `Text(BriefWords.plain(s, privacy:))`.
    static func spoken(_ s: String?, privacy: Bool) -> String { BriefMask.spoken(plain(s, privacy: privacy)) }

    /// A plain string as one Text: masked when privacy is on, and spoken with "hidden" for each mask.
    /// A drop-in for `Text(BriefWords.plain(s, privacy:))`.
    static func line(_ s: String?, privacy: Bool) -> Text {
        let shown = plain(s, privacy: privacy)
        let t = Text(shown)
        return shown.contains(BriefMask.shown) ? t.accessibilityLabel(BriefMask.spoken(shown)) : t
    }

    /// Card words as VoiceOver should say them, for a spoken label built from what the card shows: the mask
    /// reads "hidden", "$15K" reads "15 thousand dollars", arrows read "up" and "down", "Δ" reads "delta",
    /// "%" reads "percent" and "·" is a pause. The words on screen never change.
    static func speech(_ s: String) -> String {
        var o = BriefMask.spoken(s)
        if let re = try? NSRegularExpression(pattern: #"\$(\d[\d,]*(?:\.\d+)?)([KMB])"#) {
            for m in re.matches(in: o, range: NSRange(o.startIndex..., in: o)).reversed() {
                guard let r = Range(m.range, in: o), let n = Range(m.range(at: 1), in: o), let u = Range(m.range(at: 2), in: o) else { continue }
                let unit = o[u] == "K" ? "thousand" : o[u] == "M" ? "million" : "billion"
                o.replaceSubrange(r, with: "\(o[n]) \(unit) dollars")
            }
        }
        for (g, w) in [("↑", " up "), ("▲", " up "), ("↓", " down "), ("▼", " down "), ("Δ", " delta "), ("%", " percent "), (" · ", ", ")] {
            o = o.replacingOccurrences(of: g, with: w)
        }
        while o.contains("  ") { o = o.replacingOccurrences(of: "  ", with: " ") }
        return o.replacingOccurrences(of: " ,", with: ",").replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - The privacy mask

enum BriefMask {
    /// What a masked amount shows.
    static let shown = "$•••"

    /// What VoiceOver says for a masked string: "hidden" in place of each $•••, the rest as it is.
    static func spoken(_ masked: String) -> String { masked.replacingOccurrences(of: shown, with: "hidden") }

    /// Words that make the $ figure after them a price, not money (block 33, plus "under"/"over" for the Time value
    /// sheet's "Under $0.05 a share"). Never "from"/"to": "Paying went from $885 to $2,217 a week" is book money.
    private static let priceWords: Set<String> = ["above", "below", "at", "near", "today", "avg", "low", "high", "under", "over"]

    static func mask(_ s: String) -> String {
        guard s.contains("$") else { return s }
        let ns = s as NSString
        // Thousands commas only (",ddd"), so the comma after "$1,275, calls" stays (AUDIT-LOG 5).
        let re = try! NSRegularExpression(pattern: #"\$\d+(?:,\d{3})*(?:\.\d+)?[KMB]?"#)
        var out = s
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            // The word before the figure decides: a price stays.
            let before = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
            let prev = before.split(whereSeparator: { $0 == " " || $0 == "·" || $0 == "(" }).last.map { String($0).lowercased() } ?? ""
            if priceWords.contains(prev) || before.hasSuffix(":") && prev.hasSuffix(":") { continue }
            if let r = Range(m.range, in: out) { out.replaceSubrange(r, with: shown) }
        }
        return out
    }
}

/// `BriefWords.text` at the phone's text size (Pass 5). The runs carry their own fonts, so the outer `.sType`
/// never reaches them; the sentence reads the text size here and scales its base style itself.
struct BriefSentence: View {
    let spans: [BriefSpan]
    let base: SType
    var baseColor: Color = S.ink
    var boldWeight: CGFloat = 700
    var privacy = false
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales

    init(_ spans: [BriefSpan], base: SType, baseColor: Color = S.ink, boldWeight: CGFloat = 700, privacy: Bool = false) {
        self.spans = spans; self.base = base; self.baseColor = baseColor; self.boldWeight = boldWeight; self.privacy = privacy
    }

    var body: some View {
        // The base's line height, as `.sType` gives plain text (Audit 1: sentences ran on the font's natural line,
        // 17.9 for 15/21, so every sentence was short): leading between lines, half the rest above and below.
        let t = scales ? base.scaled(dts) : base
        let gap = t.line - t.uiFont().lineHeight
        BriefWords.text(spans, base: t, baseColor: baseColor, boldWeight: boldWeight, privacy: privacy)
            .lineSpacing(max(0, gap))
            .padding(.vertical, gap / 2)
    }
}
