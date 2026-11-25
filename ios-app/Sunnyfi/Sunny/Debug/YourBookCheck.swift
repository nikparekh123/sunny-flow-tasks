//
//  YourBookCheck.swift
//  Sunny
//
//  DEBUG, simulator only: `-yourbook <file.json>` shows Your book (Positions) alone, from a saved brief_inputs.parts
//  ({book: {sh, hc, ip, sc, sp}, names: {...}}), with no sign-in, so the card can be checked against real figures.
//  Under it, each name's own book (§2.3).
//  `-payoffCheck <file.json>` ({wire, name, inputs}: a sunny-positions reply and its brief_inputs) shows that name's
//  Payoff with the date and range sliders; `-payAt 0` and `-payRange 30` set them, `-payTarget 37.5` adds a target.
//  Under it, that name's Every leg, its chips and switches live (no tries, no Sold in SD rows).
//

#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct YourBookCheck: View {
    let path: String

    static let file: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-yourbook"), a.indices.contains(i + 1) else { return nil }
        return a[i + 1]
    }()

    var body: some View {
        let j = (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Positions").sType(PT.title, tabular: false).foregroundStyle(PC.ink).padding(.horizontal, 16)
                PosYourBook(parts: PosBook.parts(j?["book"] ?? .null), tickers: (j?["names"] ?? .null).object.count, privacy: false)
                    .padding(.horizontal, 16)
                ForEach(["NKE", "BABA", "FIS", "NVDA", "SPCX"], id: \.self) { t in
                    if case .object = j?["names"][t] ?? .null {
                        Text(t).sType(PT.t(20, 26, 700), tabular: false).foregroundStyle(PC.ink).padding(.horizontal, 16)
                        PosNameBook(t: t, parts: PosBook.parts(j?["names"][t] ?? .null), privacy: false)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 60)
        }
        .background(SBackground(glows: true))
        .preferredColorScheme(.dark)
    }
}

struct PayoffCheck: View {
    let path: String
    @State private var at: Int? = ProcessInfo.processInfo.arguments.firstIndex(of: "-payAt").flatMap { i in Int(ProcessInfo.processInfo.arguments[i + 1]) }
    @State private var range: Int = ProcessInfo.processInfo.arguments.firstIndex(of: "-payRange").flatMap { i in Int(ProcessInfo.processInfo.arguments[i + 1]) } ?? 12
    @State private var chips: Set<String> = []
    @State private var flip: Set<String> = []
    private let target: Double? = ProcessInfo.processInfo.arguments.firstIndex(of: "-payTarget").flatMap { i in Double(ProcessInfo.processInfo.arguments[i + 1]) }

    static let file: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-payoffCheck"), a.indices.contains(i + 1) else { return nil }
        return a[i + 1]
    }()

    var body: some View {
        let raw = try? Data(contentsOf: URL(fileURLWithPath: path))
        let j = raw.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let wire = raw.flatMap { d -> PositionsWire? in
            guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let w = o["wire"],
                  let wd = try? JSONSerialization.data(withJSONObject: w) else { return nil }
            return try? JSONDecoder().decode(PositionsWire.self, from: wd)
        }
        ScrollView {
            if let wire, let j {
                let m = PositionsModel(wire: wire, name: j["name"])
                let nm = PosName.build(m, inputs: j["inputs"])
                let ai = min(at ?? nm.dateOpen, nm.dateEnd)
                if let p = PosName.payoff(m, off: PosName.offs(m, flip: []), stop: nm.dates[ai].i, range: Double(range) / 100, hold: nm.dates.map(\.i)) {
                    PosPayoffView(t: m.t, S0: m.S0, p: p, privacy: false, changed: false, dates: nm.dates,
                                  at: Binding(get: { ai }, set: { at = $0 }), rangePct: $range, target: target)
                        .padding(.horizontal, 16).padding(.top, 60)
                }
                let now = { let f = DateFormatter(); f.timeZone = TimeZone(identifier: "America/New_York"); f.dateFormat = "yyyy-MM-dd"
                            return f.string(from: SClock.now()) }()
                let ev = PosEvery.build(m, inputs: j["inputs"], offs: PosName.offs(m, flip: flip), chips: chips, sold: [], tries: [],
                                        S0: m.S0, today: now, mins: 600, closed: [])
                PosEveryBook(t: m.t, m: ev, privacy: false,
                             toggle: { l in if flip.contains(l.id) { flip.remove(l.id) } else { flip.insert(l.id) } },
                             setL: { _, _ in }, chip: { c in if chips.contains(c) { chips.remove(c) } else { chips.insert(c) } },
                             all: { chips = ev.anyOn ? chips.union(ev.allOffChips) : [] }, remove: { _ in })
                    .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 80)
            } else {
                Text("Could not read \(path)").padding(.top, 80)
            }
        }
        .background(SBackground(glows: true))
        .preferredColorScheme(.dark)
    }
}
#endif
