//
//  BriefCards.swift
//  Sunny
//
//  Every Home card, chosen by its type (README 5.2). A card with no view of its own yet is drawn by the
//  generic card: its title, sub line, rows and footer, so nothing in the content goes missing while the
//  dedicated views are built.
//

import SwiftUI

struct BriefCardView: View {
    let card: JSONValue
    let privacy: Bool

    var body: some View {
        switch card["type"].string ?? "" {
        case "indexCards", "futuresCards", "theWeekIndexes": BIndexRow(card: card)
        case "overnight", "worldThisWeek": BMarketsCard(card: card)
        case "economy": BEconomyRow(card: card)
        case "outToday": BOutToday(card: card)
        case "sectors": BSectorsRow(card: card)
        case "yourNames": BNamesRow(card: card)
        case "whatsMoving": BWhatsMoving(card: card, privacy: privacy)
        case "yourPosition": YourPositionCard(card: card, privacy: privacy)
        case "toDecide": BToDecide(card: card, privacy: privacy)
        case "comingUp", "remember": BDatedRows(card: card, privacy: privacy)
        case "earningsAhead": BEarningsAhead(card: card, privacy: privacy)
        case "yourResults", "results": BResults(card: card, privacy: privacy)
        case "closedRolled": BClosedRolled(card: card, privacy: privacy)
        case "afterHours": BAfterHours(card: card, privacy: privacy)
        case "tomorrowOrders": BOrders(card: card, privacy: privacy)
        case "thetaMonth": BThetaMonth(card: card, privacy: privacy)
        case "payback": BPayback(card: card, privacy: privacy)
        case "thesisCheck": BThesisCheck(card: card, privacy: privacy)
        default: GenericBriefCard(card: card, privacy: privacy).padding(.horizontal, S.margin)
        }
    }
}

/// Title (20/24 bold), sub line (13/16 medium secondary), then whatever rows the card carries, then a
/// small source line. Rows are label · value pairs, or a list of strings.
struct GenericBriefCard: View {
    let card: JSONValue
    let privacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = card["title"].string {
                Text(t).sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
            }
            if let s = card["subtitle"].string ?? card["sub"].string {
                Text(BriefWords.plain(s, privacy: privacy)).sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.secondary)
            }
            let body = card["body"].isNull ? card["text"] : card["body"]
            if !body.isNull {
                BriefWords.text(BriefSpan.list(body), base: SType(size: 15, weight: 500, line: 21, tracking: 0), privacy: privacy)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                if i > 0 { Rectangle().fill(S.hairline).frame(height: 0.5) }
                row(r)
            }
            if let f = card["footer"].string ?? card["source"].string {
                Text(f).sType(SType(size: 11, weight: 600, line: 13, tracking: 0), tabular: false).foregroundStyle(S.secondary)
            }
        }
        .briefCard()
    }

    @ViewBuilder private func row(_ r: JSONValue) -> some View {
        if case .object = r {
            let label = r["label"].string ?? r["name"].string ?? r["date"].string ?? r["t"].string ?? r["title"].string ?? ""
            let value = r["value"].string ?? r["amount"].string ?? r["v"].string ?? r["right"].string ?? ""
            let sub = r["sub"].string ?? r["line"].string ?? r["text"].string ?? r["what"].string
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BriefWords.plain(label, privacy: privacy)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
                    if let sub { Text(BriefWords.plain(sub, privacy: privacy)).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.secondary) }
                }
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(BriefWords.plain(value, privacy: privacy)).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                }
            }
        } else if case .array(let a) = r {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ForEach(Array(a.enumerated()), id: \.offset) { i, x in
                    Text(BriefWords.plain(x.string ?? "", privacy: privacy))
                        .sType(SType(size: 15, weight: i == 0 ? 600 : 500, line: 20, tracking: 0))
                        .foregroundStyle(i == 0 ? S.ink : S.secondary)
                    if i == 0 { Spacer(minLength: 8) }
                }
            }
        } else {
            Text(BriefWords.plain(r.string ?? "", privacy: privacy)).sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.ink)
        }
    }
}
