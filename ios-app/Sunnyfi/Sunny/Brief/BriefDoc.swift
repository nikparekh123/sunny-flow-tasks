//
//  BriefDoc.swift
//  Sunny
//
//  One Home at one moment for one account (block 29): the title and date line, the day card's caption,
//  the lede, the deck alert, and the numbered sections with their cards. In sample mode it comes from
//  Brief/Sample/brief-home.json (the design's hand-written sample); from Pass 2 the server builds it from
//  the account's data in the same shape. Cards stay loose JSON: each card view reads the keys it draws.
//

import Foundation

struct BriefDoc {
    var title: String
    var dateLine: String
    var dayCaption: String
    var dayCaptionOrange: Bool
    var lede: [BriefSpan]
    var ledePrivacy: [BriefSpan]?
    var alert: JSONValue
    var sections: [BriefSection]

    init(_ j: JSONValue, moment: Moment) {
        title = j["title"].string ?? moment.title
        dateLine = j["dateLine"].string ?? ""
        let cap = j["dayCaption"]
        if case .object = cap {
            dayCaption = cap["text"].string ?? cap["caption"].string ?? ""
            dayCaptionOrange = cap["orange"].bool
        } else {
            dayCaption = cap.string ?? ""
            dayCaptionOrange = j["dayCaptionOrange"].bool
        }
        lede = BriefSpan.list(j["lede"])
        let lp = j["privacy"]["lede"]
        ledePrivacy = lp.isNull ? nil : BriefSpan.list(lp)
        alert = j["alert"]
        sections = j["sections"].array.enumerated().map { BriefSection($0.element, index: $0.offset) }
    }
}

struct BriefSection: Identifiable {
    let id: Int
    var num: String
    var kicker: String
    var headline: [BriefSpan]
    var headlinePrivacy: [BriefSpan]?
    var cards: [JSONValue]

    init(_ j: JSONValue, index: Int) {
        id = index
        num = j["num"].string ?? String(index + 1)
        kicker = j["kicker"].string ?? ""
        headline = BriefSpan.list(j["headline"])
        let hp = j["privacy"]["headline"]
        headlinePrivacy = hp.isNull ? nil : BriefSpan.list(hp)
        cards = j["cards"].array
    }
}

/// The sample content files, read once from the app bundle (DEBUG sample mode).
enum BriefSample {
    static let home: JSONValue = load("brief-home")
    static let overview: JSONValue = load("brief-overview")
    static let sheets: JSONValue = load("brief-sheets")

    private static func load(_ name: String) -> JSONValue {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let v = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return v
    }

    /// One moment for one account. The file may nest moment → account or account → moment; both are read.
    static func doc(_ m: Moment, _ acct: String) -> BriefDoc? {
        var j = home["states"][m.rawValue][acct]
        if j.isNull, m == .bell || m == .last20 || m == .last5 { j = home["states"]["open"][acct] }
        if j.isNull, m == .futures { j = home["states"]["pre"][acct] }
        return j.isNull ? nil : BriefDoc(j, moment: m)
    }

    /// The 11 sector heat maps for a day or a week (stored once; a sectors card names which).
    static func sectorMaps(_ ref: String) -> JSONValue { home["sectorMaps"][ref] }
}
