//
//  BriefLive.swift
//  Sunny
//
//  The server's brief on the real book (handoff 6 Nov 2026, Pass 2). sunny-home writes `payload.brief`: Home's
//  page for the moment (`doc`, the same shape as the design's sample), Your position (`position`, from the one
//  book engine), the Time value sheet's sold legs and each name's status. The phone only reads and draws it;
//  BriefState decodes it once per update, never inside a view's body.
//

import Foundation

struct BriefLive {
    let doc: BriefDoc?
    let position: YourPositionModel?
    /// False for a book with nothing held (the cards read "Nothing held yet").
    let hasBook: Bool
    let timeValue: JSONValue
    /// The economy sheet: the twelve FRED indicators (econ-sync), watch first.
    let economy: JSONValue
    let names: [JSONValue]
    let error: String?

    init(_ j: JSONValue) {
        let d = j["doc"]
        let m = d["moment"].string.flatMap(Moment.init(rawValue:)) ?? j["moment"].string.flatMap(Moment.init(rawValue:)) ?? .open
        doc = d.isNull || !d["error"].isNull ? nil : BriefDoc(d, moment: m)
        position = YourPositionModel(json: j["position"])
        hasBook = !j["names"].array.isEmpty
        timeValue = j["timeValue"]
        economy = d["economy"]
        names = j["names"].array
        error = j["error"].string ?? d["error"].string
    }
}

extension YourPositionModel {
    /// The server's Your position (book-engine.ts yourPosition): the same fields the sample engine builds.
    init?(json j: JSONValue) {
        guard case .object = j, !j["grid"].array.isEmpty else { return nil }
        subtitle = j["subtitle"].string ?? ""
        sentence = BriefSpan.list(j["sentence"])
        grid = j["grid"].array.compactMap(\.double)
        friday = j["friday"].array.compactMap(\.double)
        today = j["today"].array.compactMap(\.double)
        shortAt = j["shortAt"].double
        stats = j["stats"].array.map { (value: $0["v"].string ?? "", label: $0["l"].string ?? "", color: $0["c"].string ?? "ink") }
        cover = j["cover"].string ?? ""
        assign = j["assign"].string
        count = j["count"].string ?? ""
        countColor = j["countColor"].string ?? "secondary"
        rows = j["rows"].array.map { r in
            Row(id: r["id"].string ?? "", name: r["name"].string ?? "", line: r["line"].string ?? "", lineColor: r["lineColor"].string ?? "secondary",
                right: r["right"].string ?? "", rightColor: r["rightColor"].string ?? "ink", at: r["at"].string ?? "", st: Int(r["st"].double ?? 0))
        }
        aria = j["aria"].string ?? ""
        guard grid.count == friday.count, grid.count == today.count else { return nil }
    }
}
