//
//  BriefCardsBook.swift
//  Sunny
//
//  Sections 2 to 4 of New Home (README 5.2): What's moving, To decide, Coming up and Remember, Earnings ahead,
//  Your results and Results, Closed and rolled, After hours, Tomorrow's orders, Theta · October, Payback and
//  the Thesis check. Every money figure follows privacy; dividends always sit on their own line.
//

import SwiftUI

// MARK: - What's moving (market hours)

/// Each name's move today against the move its options priced for today: a grey band is the priced move,
/// the dot is where the name is (red when it is past the band). Scale ↓5% to ↑5%.
struct BWhatsMoving: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BTitle(t: card["title"].string)
            BSub(t: card["subtitle"].string)
            BBody(v: card["body"], privacy: privacy)
            VStack(spacing: 10) {
                ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 10) {
                        BLogo(ticker: r["ticker"].string, size: 28)
                        GeometryReader { g in
                            let w = g.size.width, pos = { (p: Double) -> CGFloat in w * CGFloat(0.5 + max(-1, min(1, p / 5)) * 0.48) }
                            let pr = r["pricedPct"].double ?? 0, mv = r["movePct"].double ?? 0, past = r["pastPricedMove"].bool
                            ZStack(alignment: .leading) {
                                Rectangle().fill(S.hairline).frame(height: 1).frame(maxHeight: .infinity)
                                Capsule().fill(S.chip).frame(width: pos(pr) - pos(-pr), height: 10).offset(x: pos(-pr))
                                Rectangle().fill(S.secondary.opacity(0.6)).frame(width: 1, height: 14).offset(x: w / 2)
                                Circle().fill(past ? S.red : S.ink).frame(width: 10, height: 10).offset(x: pos(mv) - 5)
                            }
                        }
                        .frame(height: 20)
                        Text(r["move"].string ?? "").sType(SType(size: 15, weight: 700, line: 18, tracking: 0))
                            .foregroundStyle(BK.color(r["moveColor"].string)).frame(width: 64, alignment: .trailing)
                    }
                }
                HStack {
                    let ax = card["axis"].array.compactMap(\.string)
                    ForEach(Array(ax.enumerated()), id: \.offset) { i, a in
                        Text(a).sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
                        if i < ax.count - 1 { Spacer() }
                    }
                }
                .padding(.leading, 38).padding(.trailing, 74)
            }
            .padding(.top, 6)
            if let l = card["legend"].string {
                HStack(spacing: 8) {
                    Capsule().fill(S.chip).frame(width: 22, height: 8)
                    Text(l).sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink)
                }
            }
            if let w = card["watchlistLine"].string {
                BHairline().padding(.vertical, 4)
                Text(w).sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
            }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - To decide (market hours)

struct BToDecide: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BTitle(t: card["title"].string)
            BSub(t: card["subtitle"].string)
            BBody(v: card["body"], privacy: privacy)
            let w = card["whatIf"]
            if !w.isNull {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(w["label"].string ?? "What if").font(.system(size: 12, weight: .semibold)).foregroundStyle(S.ink)
                            .padding(.horizontal, 8).frame(height: 22).background(Capsule().fill(S.sheetFill))
                        Text(w["title"].string ?? "").font(.system(size: 13, weight: .semibold)).foregroundStyle(S.ink)
                        Spacer()
                        Text(w["by"].string ?? "").sType(BK.label, tabular: false).foregroundStyle(S.secondary)
                    }
                    BWhatIfChart(labels: w["chartLabels"].array).frame(height: 120)
                    HStack(spacing: 14) {
                        ForEach(Array(w["legend"].array.enumerated()), id: \.offset) { i, l in
                            HStack(spacing: 6) {
                                Rectangle().fill(i == 0 ? S.secondary : S.green).frame(width: 14, height: 2)
                                Text(l["t"].string ?? "").sType(BK.label, tabular: false).foregroundStyle(BK.color(l["c"].string))
                            }
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.chip.opacity(0.7)))
            }
            BBody(v: card["footer"], privacy: privacy, type: SType(size: 13, weight: 500, line: 18, tracking: 0))
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

/// The what-if's picture: keeping the sold calls caps the gain at their strike; rolling up moves the cap to the
/// new strike. Walls and strikes from the content's labels sit on the price axis.
struct BWhatIfChart: View {
    let labels: [JSONValue]
    var body: some View {
        let nums = labels.compactMap { l -> (String, Double, String, String)? in
            guard let t = l["t"].string, let v = Double(t.split(separator: " ").last ?? "") else { return nil }
            return (t, v, l["c"].string ?? "secondary", l["kind"].string ?? "")
        }
        let strikes = nums.filter { $0.3 == "strike" }.map(\.1)
        let lo = (nums.map(\.1).min() ?? 33) - 1, hi = (nums.map(\.1).max() ?? 38) + 1
        let keep = strikes.first ?? 36, roll = strikes.last ?? 37.5
        Canvas { ctx, size in
            let x = { (p: Double) -> CGFloat in CGFloat((p - lo) / (hi - lo)) * size.width }
            let y = { (v: Double) -> CGFloat in size.height * 0.8 - CGFloat(v / (hi - lo)) * size.height * 0.6 }
            func line(_ cap: Double, _ cost: Double) -> Path {
                var p = Path(); let steps = 40
                for i in 0...steps { let s = lo + (hi - lo) * Double(i) / Double(steps); let v = min(s, cap) - lo - cost
                    i == 0 ? p.move(to: CGPoint(x: x(s), y: y(v))) : p.addLine(to: CGPoint(x: x(s), y: y(v))) }
                return p
            }
            for n in nums where n.3 == "wall" {
                var p = Path(); p.move(to: CGPoint(x: x(n.1), y: 0)); p.addLine(to: CGPoint(x: x(n.1), y: size.height))
                ctx.stroke(p, with: .color(BK.color(n.2).opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ctx.stroke(line(keep, 0), with: .color(S.secondary), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            ctx.stroke(line(roll, 0.4), with: .color(S.green), lineWidth: 2)
        }
        .accessibilityLabel("What if: keep the calls or roll them up")
    }
}

// MARK: - Dated rows: Coming up, Remember for next week

struct BDatedRows: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BTitle(t: card["title"].string).padding(.bottom, 8)
            if !card["line"].isNull { BBody(v: card["line"], privacy: privacy) }
            ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                if i > 0 { BHairline() }
                HStack(alignment: .center, spacing: 10) {
                    Text(r["date"].string ?? "").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink).frame(width: 96, alignment: .leading)
                    if let t = r["logo"].string { BLogo(ticker: t, size: 32) } else { Color.clear.frame(width: 32, height: 1) }
                    BBody(v: r["text"], privacy: privacy)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
        }
        .briefCard()
        .background(alignment: .bottom) {
            // The calendar card's soft yellow foot (as the design draws it).
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient(colors: [.clear, S.yellow.opacity(0.18)], startPoint: .top, endPoint: .bottom))
        }
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Earnings ahead

struct BEarningsAhead: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BTitle(t: card["title"].string)
            BSub(t: card["subtitle"].string)
            HStack(spacing: 10) {
                BLogo(ticker: card["logo"].string, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card["name"].string ?? "").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text(card["when"].string ?? "").sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                }
            }
            .padding(.top, 4)
            BStats(stats: card["stats"].array, privacy: privacy)
            let ch = card["chart"]
            if !ch.isNull {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        ForEach(Array(ch["legend"].array.compactMap(\.string).enumerated()), id: \.offset) { i, l in
                            HStack(spacing: 5) {
                                Circle().fill(i == 0 ? S.green.opacity(0.35) : i == 1 ? S.green : S.red).frame(width: 9, height: 9)
                                Text(l).sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            }
                        }
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(ch["columns"].array.compactMap(\.string).enumerated()), id: \.offset) { _, col in
                            let d = ch["dots"].array.first { $0["col"].string == col }
                            VStack(spacing: 6) {
                                ZStack(alignment: .top) {
                                    Color.clear.frame(height: 74)
                                    if let e = d?["expectedTop"].double { Circle().fill(S.green.opacity(0.35)).frame(width: 12, height: 12).offset(y: e - 6) }
                                    if let a = d?["actualTop"].double {
                                        Circle().fill(d?["result"].string == "missed" ? S.red : S.green).frame(width: 12, height: 12).offset(y: a - 6)
                                    }
                                }
                                Text(col).font(.system(size: 11, weight: col == "Tue" ? .bold : .medium)).foregroundStyle(col == "Tue" ? S.ink : S.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    if let c = ch["caption"].string { Text(c).sType(BK.label, tabular: false).foregroundStyle(S.secondary) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.chip.opacity(0.7)))
            }
            BNotes(notes: card["notes"].array, privacy: privacy)
            if let s = card["source"].string { Text(s).sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink) }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

/// Label · text rows (Estimates, You, Analysts, Pro Tip, Health...).
struct BNotes: View {
    let notes: [JSONValue]
    let privacy: Bool
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                BHairline()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(n["label"].string ?? "").sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false)
                        .foregroundStyle(S.secondary).frame(width: 90, alignment: .leading)
                    Text(BriefWords.plain(n["text"].string, privacy: privacy)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Your results (post-market) and Results (weekend)

struct BResults: View {
    let card: JSONValue
    let privacy: Bool
    @State private var seg: String = ""
    var body: some View {
        let segs = card["segments"].array.compactMap(\.string)
        let pick = seg.isEmpty ? (card["selected"].string ?? segs.first ?? "") : seg
        let s = card["bySegment"][pick]
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BTitle(t: card["title"].string)
                Spacer()
                if segs.count > 1 {
                    BSegmented(items: segs, selected: Binding(get: { pick }, set: { seg = $0 })).frame(width: 186)
                }
            }
            if let b = s["big"].string {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BriefWords.plain(b, privacy: privacy)).sType(BK.big).foregroundStyle(BK.color(s["bigColor"].string))
                    BSub(t: s["bigSub"].string, privacy: privacy)
                }
            }
            BStats(stats: s["stats"].array, privacy: privacy)
            BBody(v: s["body"], privacy: privacy)
            let dv = s["dividends"]
            if !dv.isNull {
                BHairline()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dv["title"].string ?? "Dividends").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        BBody(v: dv["line"], privacy: privacy, type: SType(size: 12, weight: 500, line: 16, tracking: 0))
                    }
                    Spacer()
                    Text(BriefWords.plain(dv["right"].string, privacy: privacy)).sType(SType(size: 17, weight: 700, line: 22, tracking: 0))
                        .foregroundStyle(BK.color(dv["rightColor"].string))
                }
            }
            ForEach(Array(s["charts"].array.enumerated()), id: \.offset) { _, c in
                BHairline()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(c["title"].string ?? "").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Spacer()
                        if let sub = c["sub"].string { Text(BriefWords.plain(sub, privacy: privacy)).sType(BK.label, tabular: false).foregroundStyle(S.secondary) }
                    }
                    if !c["bars"].array.isEmpty {
                        BBars(bars: c["bars"].array, height: 56, privacy: privacy)
                    } else if !c["groups"].array.isEmpty {
                        BBars(bars: c["groups"].array.map { g in
                            JSONValue.object(["label": g["label"], "highlight": g["highlight"],
                                              "value": g["values"][0]["value"], "valueColor": g["values"][0]["valueColor"]])
                        }, height: 56, privacy: privacy)
                    }
                    if let n = c["note"].string { Text(n).sType(BK.small, tabular: false).foregroundStyle(S.ink) }
                }
            }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Closed and rolled today

struct BClosedRolled: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BTitle(t: card["title"].string)
            BSub(t: card["subtitle"].string)
            ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                if i > 0 { BHairline() }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        BLogo(ticker: r["logo"].string, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r["title"].string ?? "").sType(BK.row, tabular: false).foregroundStyle(S.ink)
                            Text(r["sub"].string ?? "").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(BriefWords.plain(r["value"].string, privacy: privacy)).sType(SType(size: 17, weight: 800, line: 22, tracking: 0))
                                .foregroundStyle(BK.color(r["valueColor"].string))
                            Text(r["valueLabel"].string ?? "").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                        }
                    }
                    BBody(v: r["note"], privacy: privacy)
                }
                .padding(.vertical, 4)
            }
            BFooter(v: card["footer"], privacy: privacy)
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - After hours

struct BAfterHours: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BTitle(t: card["title"].string)
            BSub(t: card["subtitle"].string)
            HStack(spacing: 10) {
                BLogo(ticker: card["logo"].string, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card["name"].string ?? "").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text(card["source"].string ?? "").sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                }
                Spacer()
                Text(card["move"].string ?? "").sType(SType(size: 20, weight: 800, line: 24, tracking: 0)).foregroundStyle(BK.color(card["moveColor"].string))
            }
            BBody(v: card["body"], privacy: privacy)
            let r = card["range"]
            if !r.isNull {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("● \(r["today"].string ?? "")").sType(SType(size: 12, weight: 700, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Spacer()
                        Text("| \(r["avg"].string ?? "")").sType(SType(size: 12, weight: 700, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(S.hairline).frame(height: 4)
                        GeometryReader { g in
                            let lo = Double(r["low"].string?.filter { $0.isNumber || $0 == "." } ?? "") ?? 0
                            let hi = Double(r["high"].string?.filter { $0.isNumber || $0 == "." } ?? "") ?? 1
                            let td = Double(r["today"].string?.filter { $0.isNumber || $0 == "." } ?? "") ?? lo
                            let av = Double((r["avg"].string?.components(separatedBy: " ·").first ?? "").filter { $0.isNumber || $0 == "." }) ?? lo
                            let fx = { (v: Double) -> CGFloat in g.size.width * CGFloat((v - lo) / max(hi - lo, 0.01)) }
                            Capsule().fill(S.secondary.opacity(0.5)).frame(width: max(0, fx(av) - fx(td)), height: 4).offset(x: fx(td), y: g.size.height / 2 - 2)
                            Circle().fill(S.ink).frame(width: 10, height: 10).offset(x: fx(td) - 5, y: g.size.height / 2 - 5)
                            Rectangle().fill(S.ink).frame(width: 2, height: 14).offset(x: fx(av) - 1, y: g.size.height / 2 - 7)
                        }
                    }
                    .frame(height: 16)
                    HStack {
                        Text(r["low"].string ?? "").sType(BK.label, tabular: false).foregroundStyle(S.secondary)
                        Spacer()
                        Text(r["analysts"].string ?? "").sType(BK.label, tabular: false).foregroundStyle(S.secondary)
                        Spacer()
                        Text(r["high"].string ?? "").sType(BK.label, tabular: false).foregroundStyle(S.secondary)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.chip.opacity(0.7)))
            }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Tomorrow's orders

struct BOrders: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                BTitle(t: card["title"].string)
                Spacer()
                Text(card["count"].string ?? "").sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
            }
            BSub(t: card["subtitle"].string, privacy: privacy)
            ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                if i > 0 { BHairline() }
                HStack(alignment: .top, spacing: 12) {
                    BLogo(ticker: r["logo"].string, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r["order"].string ?? "").sType(BK.row, tabular: false).foregroundStyle(S.ink)
                        Text(r["why"].string ?? "").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true)
                        if let t = r["tag"].string { Text(t).sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.secondary) }
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(BriefWords.plain(r["amount"].string, privacy: privacy)).sType(SType(size: 17, weight: 800, line: 22, tracking: 0)).foregroundStyle(S.ink)
                        Text(r["amountLabel"].string ?? "").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            BFooter(v: card["footer"], privacy: privacy)
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Theta · October

struct BThetaMonth: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BTitle(t: card["title"].string)
            BSub(t: card["subtitle"].string)
            HStack(spacing: 14) {
                ForEach(Array(card["legend"].array.compactMap(\.string).enumerated()), id: \.offset) { i, l in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(i == 0 ? S.green : S.red).frame(width: 10, height: 10)
                        Text(l).sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    }
                }
            }
            let weeks = card["weeks"].array
            let mx = weeks.compactMap { Double(($0["ratio"].string ?? "").replacingOccurrences(of: "×", with: "")) }.max() ?? 1
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, w in
                    let r = Double((w["ratio"].string ?? "").replacingOccurrences(of: "×", with: "")) ?? 1
                    let hl = w["highlight"].bool
                    VStack(spacing: 4) {
                        Text(w["ratio"].string ?? "").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(hl ? S.green : S.ink)
                        HStack(alignment: .bottom, spacing: 2) {
                            RoundedRectangle(cornerRadius: 3).fill(hl ? S.green : S.green.opacity(0.3)).frame(height: 80 * CGFloat(r / mx))
                            RoundedRectangle(cornerRadius: 3).fill(hl ? S.red : S.red.opacity(0.3)).frame(height: 80 / CGFloat(mx))
                        }
                        Text(w["label"].string ?? "").font(.system(size: 11, weight: hl ? .bold : .medium)).foregroundStyle(hl ? S.ink : S.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            BBody(v: card["body"], privacy: privacy)
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Payback · month end

struct BPayback: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BTitle(t: card["title"].string)
            BSub(t: card["subtitle"].string)
            Text(card["big"].string ?? "").sType(BK.big).foregroundStyle(BK.color(card["bigColor"].string))
            BSub(t: card["bigSub"].string, privacy: privacy)
            let ch = card["chart"]
            if !ch.isNull {
                Text(ch["title"].string ?? "").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink).padding(.top, 6)
                BBars(bars: ch["bars"].array, height: 64, privacy: privacy)
            }
            ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { _, r in
                BHairline()
                HStack(alignment: .firstTextBaseline) {
                    Text(BriefWords.plain(r["label"].string, privacy: privacy)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(BriefWords.plain(r["value"].string, privacy: privacy)).sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                            .foregroundStyle(BK.color(r["valueColor"].string))
                        if let s = r["valueSub"].string { Text(s).sType(BK.rowSub, tabular: false).foregroundStyle(BK.color(r["valueColor"].string)) }
                    }
                }
                .padding(.vertical, 4)
            }
            if let f = card["footer"].string { Text(f).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary) }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Thesis check

struct BThesisCheck: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BTitle(t: card["title"].string)
            BSub(t: card["subtitle"].string)
            BStats(stats: card["stats"].array, privacy: privacy).padding(.top, 4)
            BNotes(notes: card["notes"].array, privacy: privacy)
            if let s = card["source"].string { Text(s).sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink) }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}
