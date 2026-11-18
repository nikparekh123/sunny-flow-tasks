//
//  YourBookCheck.swift
//  Sunny
//
//  DEBUG, simulator only: `-yourbook <file.json>` shows Your book (Positions) alone, from a saved brief_inputs.parts
//  ({book: {sh, hc, ip, sc, sp}}), with no sign-in, so the card can be checked against real figures.
//  `-yourbookOpen Hedge` opens a group. Under it, each name's own book (§2.3) with Hedge open.
//  `-payoffCheck <file.json>` ({wire, name, inputs}: a sunny-positions reply and its brief_inputs) shows that name's
//  Payoff with the date and range sliders; `-payAt 0` and `-payRange 30` set them, `-payTarget 37.5` adds a target.
//

#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct YourBookCheck: View {
    let path: String
    @State private var open: Set<String> = Set(ProcessInfo.processInfo.arguments.firstIndex(of: "-yourbookOpen")
        .flatMap { i in ProcessInfo.processInfo.arguments.indices.contains(i + 1) ? [ProcessInfo.processInfo.arguments[i + 1]] : nil } ?? [])

    @State private var own: String? = "Hedge"

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
                PosYourBook(groups: PosBook.groups(j?["book"] ?? .null), open: $open, privacy: false, reduce: false)
                    .padding(.horizontal, 16)
                ForEach(["NKE", "BABA", "FIS", "NVDA", "SPCX"], id: \.self) { t in
                    if case .object = j?["names"][t] ?? .null {
                        Text(t).sType(PT.t(20, 26, 700), tabular: false).foregroundStyle(PC.ink).padding(.horizontal, 16)
                        PosNameBook(t: t, groups: PosBook.groups(j?["names"][t] ?? .null), open: $own, privacy: false, reduce: false)
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
                let ai = min(at ?? nm.dateEnd, nm.dateEnd)
                if let p = PosName.payoff(m, off: PosName.offs(m, flip: []), stop: nm.dates[ai].i, range: Double(range) / 100, hold: nm.dates.map(\.i)) {
                    PosPayoffView(t: m.t, S0: m.S0, p: p, privacy: false, changed: false, dates: nm.dates,
                                  at: Binding(get: { ai }, set: { at = $0 }), rangePct: $range, target: target)
                        .padding(.horizontal, 16).padding(.top, 60)
                }
            } else {
                Text("Could not read \(path)").padding(.top, 80)
            }
        }
        .background(SBackground(glows: true))
        .preferredColorScheme(.dark)
    }
}
#endif
