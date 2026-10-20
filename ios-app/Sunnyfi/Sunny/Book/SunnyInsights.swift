//
//  SunnyInsights.swift
//  Sunny
//
//  Block 14c (handoff 28, 20 Oct 2026) · This week's insights: six plain points
//  about one name, in the order its strategy cares about, the last always
//  delta. A sheet from every Position card. Black and white, written as
//  sentences on the server (Nik: fixed sentence rules from the reads); a few
//  words underlined. It explains; it never tells you what to trade.
//

import SwiftUI

struct SunnyInsightsSheet: View {
    let t: String
    let insights: NameInsights?
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: close) {
                    Path { q in
                        q.move(to: CGPoint(x: 1, y: 1)); q.addLine(to: CGPoint(x: 13, y: 13))
                        q.move(to: CGPoint(x: 13, y: 1)); q.addLine(to: CGPoint(x: 1, y: 13))
                    }
                    .stroke(S.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(Circle())
                }
                .buttonStyle(SPressStyle(scale: 0.95))
                .accessibilityLabel("Close")
                .padding(.bottom, 12)
                Text("Insights").sType(.largeTitle, tabular: false)
                    .accessibilityAddTraits(.isHeader)
                (Text(insights?.name ?? t).font(SType(size: 20, weight: 700, line: 24, tracking: 0).font())
                 + Text(" This week").foregroundStyle(S.muted))
                    .sType(SType(size: 20, weight: 500, line: 24, tracking: 0), tabular: false)
                    .padding(.top, 10)
                if let ins = insights, !ins.points.isEmpty {
                    Text("\(ins.points.count) things to know").sType(.sectionTitle, tabular: false)
                        .padding(.top, 20).padding(.bottom, 16)
                    ForEach(Array(ins.points.enumerated()), id: \.offset) { i, p in
                        point(i + 1, p)
                            .opacity(shown || reduce ? 1 : 0)
                            .offset(y: shown || reduce ? 0 : 10)
                            .animation(reduce ? nil : S.standard(0.5).delay(Double(i) * S.stagger), value: shown)
                    }
                } else {
                    Text("No insights for \(t) yet").sType(SType(size: 17, weight: 600, line: 22, tracking: 0), tabular: false)
                        .padding(.top, 20)
                }
            }
            .foregroundStyle(S.ink)
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onAppear { shown = true }
    }

    /// "1." then the lead in semibold and the body in regular, its _marked_ words underlined.
    private func point(_ n: Int, _ p: NameInsights.Point) -> some View {
        let f = SType(size: 17, weight: 400, line: 25, tracking: 0)
        let lead = Text(p.lead + " ").font(SType(size: 17, weight: 600, line: 25, tracking: 0).font())
        let body = p.body.components(separatedBy: "_").enumerated().reduce(Text("")) { acc, e in
            acc + (e.offset % 2 == 1 ? Text(e.element).underline() : Text(e.element))
        }
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(n).").sType(SType(size: 17, weight: 600, line: 25, tracking: 0)).frame(width: 30, alignment: .leading)
            (lead + body).sType(f, tabular: false).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(n). \(p.lead) \(p.body.replacingOccurrences(of: "_", with: ""))")
    }
}
