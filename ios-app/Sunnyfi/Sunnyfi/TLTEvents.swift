//
//  TLTEvents.swift
//  Sunnyfi — TLT-only macro events calendar
//
//  Faithful port of the handoff's TLTExtras: the long-end's scheduled events,
//  viewed By event (one card per class, its next date the hero) or By date (one
//  card per date). Each card carries what the same print did to TLT last time.
//

import SwiftUI

private func evMove(_ label: String, _ last: TLTBook.MacroLast) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
            Text("\(label) · \(last.label)".uppercased()).font(InkFont.mono(11)).tracking(11 * 0.08).foregroundStyle(Ink.dim)
            Spacer(minLength: 0)
            Text("TLT \(last.move >= 0 ? "+" : "−")\(String(format: "%.1f", abs(last.move)))%")
                .font(InkFont.mono(15)).tracking(15 * -0.02).foregroundStyle(last.move >= 0 ? Ink.gain : Ink.loss)
        }
        Text(last.what).font(InkFont.display(13, .regular)).foregroundStyle(Ink.dim)
            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - By event · one card per class

private struct MacroCard: View {
    let m: TLTBook.MacroClass
    var body: some View {
        let dates = m.dates.filter { $0.inDays >= 0 }
        let next = dates.first
        let soon = (next?.inDays ?? 99) <= 7
        return InkCard(relevance: soon ? .r1 : .r2, stamp: (.delayed, "Scheduled · from the published calendar")) {
            InkBody {
                InkEyebrow(cat: m.name) { InkBand(skin: soon ? .mod : .low, text: m.cat) }
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(next.map { $0.inDays <= 0 ? "today" : "\($0.inDays)" } ?? "—")
                            .font(InkFont.mono(40, .medium)).tracking(40 * -0.04).foregroundStyle(next != nil ? Ink.text : Ink.dim)
                        Text((next.map { $0.inDays <= 0 ? "it is today" : $0.inDays == 1 ? "day away" : "days away" } ?? "nothing scheduled").uppercased())
                            .font(InkFont.mono(11.5, .medium)).tracking(11.5 * 0.05).foregroundStyle(Ink.dim).padding(.top, 12)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    if let next {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(next.label).font(InkFont.mono(20, .regular)).tracking(20 * -0.03).foregroundStyle(Ink.text)
                            Text("NEXT").font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim).padding(.top, 8).fixedSize()
                        }
                        .padding(.leading, 14).overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
                    }
                }
                .padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(Array(dates.prefix(4).enumerated()), id: \.element.id) { i, x in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(x.label).font(InkFont.mono(15.5)).tracking(15.5 * -0.01).foregroundStyle(Ink.text)
                                Text(x.tag.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text((x.inDays == 0 ? "today" : "in \(x.inDays)d").uppercased())
                                .font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim).fixedSize()
                        }
                        .frame(minHeight: 40)
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Ink.hair).frame(height: 1) } }
                        .inkRelevance(i == 0 ? .r1 : i == 1 ? .r2 : .r3)
                    }
                }
                .padding(.top, 20)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
                InkSpacer()
            }
            InkFoot { evMove("Last time", m.last) }
        }
    }
}

// MARK: - By date · one card per date

private struct DateCard: View {
    let m: TLTBook.MacroClass
    let x: TLTBook.MacroDate
    var body: some View {
        let soon = x.inDays <= 7
        let L = x.last ?? m.last
        return InkCard(relevance: soon ? .r1 : .r2, compact: true, height: 340, stamp: (.delayed, "Scheduled")) {
            InkBody(compact: true) {
                InkEyebrow(cat: m.name) { InkBand(skin: soon ? .mod : .low, text: x.label) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(x.inDays <= 0 ? "today" : "\(x.inDays)").font(InkFont.mono(40, .medium)).tracking(40 * -0.04).foregroundStyle(Ink.text)
                    Text((x.inDays <= 0 ? "it is today" : x.inDays == 1 ? "day away" : "days away").uppercased())
                        .font(InkFont.mono(11.5, .medium)).tracking(11.5 * 0.05).foregroundStyle(Ink.dim).padding(.top, 11)
                }
                .padding(.top, 16)
                Text(x.tag).font(InkFont.display(14.5, .regular)).foregroundStyle(Ink.text)
                    .padding(.top, 16).padding(.top, 13)
                    .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1).offset(y: 13) }
                    .fixedSize(horizontal: false, vertical: true)
                InkSpacer()
            }
            InkFoot(compact: true) { evMove("Last one", L) }
        }
    }
}

// MARK: - the section

struct TLTEventsScreen: View {
    @State private var byDate = false
    private let macro = TLTBook.macro

    private var flatDates: [(m: TLTBook.MacroClass, x: TLTBook.MacroDate)] {
        macro.flatMap { m in m.dates.map { (m, $0) } }
            .filter { $0.x.inDays >= 0 }
            .sorted { $0.x.inDays < $1.x.inDays }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkSectionHead(title: "Events calendar", count: "\(flatDates.count) ahead")
            HStack(spacing: 6) {
                chip("By event", on: !byDate) { byDate = false }
                chip("By date", on: byDate) { byDate = true }
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if byDate {
                        ForEach(Array(flatDates.enumerated()), id: \.offset) { i, r in
                            DateCard(m: r.m, x: r.x).inkEntrance(min(i, 4))
                        }
                    } else {
                        ForEach(Array(macro.enumerated()), id: \.element.id) { i, m in
                            MacroCard(m: m).inkEntrance(min(i, 4))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ label: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label).font(InkFont.mono(11.5)).tracking(11.5 * -0.01)
                .foregroundStyle(on ? Ink.invertText : Ink.dim)
                .padding(.horizontal, 12).frame(minHeight: 32)
                .background(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous).fill(on ? Ink.invertBg : .clear))
                .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous).strokeBorder(on ? .clear : Ink.hair, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
