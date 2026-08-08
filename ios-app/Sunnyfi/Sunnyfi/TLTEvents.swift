//
//  TLTEvents.swift
//  Sunnyfi — TLT-only macro events calendar
//
//  Faithful port of the handoff's TLTExtras: the long-end's scheduled events,
//  viewed By event (one card per class, its next date the hero) or By date (one
//  card per date). Each card carries what the same print did to TLT last time.
//

import SwiftUI
import Supabase

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
    @State private var adding = false
    private let store = EventsStore.shared
    private var macro: [TLTBook.MacroClass] { store.classes }

    private var flatDates: [(m: TLTBook.MacroClass, x: TLTBook.MacroDate)] {
        macro.flatMap { m in m.dates.map { (m, $0) } }
            .filter { $0.x.inDays >= 0 }
            .sorted { $0.x.inDays < $1.x.inDays }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkSectionHead(title: "Events calendar", count: "\(flatDates.count) ahead", icon: "plus", onAction: { adding = true })
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
        .sheet(isPresented: $adding) { AddEventSheet(store: store) }
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

// MARK: - store (Supabase tlt_macro_events)

@MainActor @Observable final class EventsStore {
    static let shared = EventsStore()
    var rows: [Row] = []
    private let client = SupabaseService.client
    private init() { Task { await load() } }

    struct Row: Codable, Identifiable {
        var id: String; var class_key: String; var class_name: String; var class_cat: String
        var event_date: String; var label: String; var tag: String?; var outcome: String?; var tlt_move: Double?
    }
    struct NewRow: Codable {
        var class_key: String; var class_name: String; var class_cat: String
        var event_date: String; var label: String; var tag: String?
    }

    func load() async {
        rows = (try? await client.from("tlt_macro_events").select().order("event_date").execute().value) ?? []
    }
    func add(_ r: NewRow) { Task { try? await client.from("tlt_macro_events").insert(r).execute(); await load() } }

    /// Group the flat rows into the calendar's classes: future dates ahead, and
    /// each class's most recent settled print as its "last time".
    var classes: [TLTBook.MacroClass] {
        let today = Self.todayISO
        var order: [String] = []; var byKey: [String: [Row]] = [:]
        for r in rows { if byKey[r.class_key] == nil { order.append(r.class_key) }; byKey[r.class_key, default: []].append(r) }
        return order.compactMap { key in
            let rs = (byKey[key] ?? []).sorted { $0.event_date < $1.event_date }
            guard let first = rs.first else { return nil }
            let past = rs.filter { $0.event_date < today && $0.outcome != nil }
            let last = past.last.map { TLTBook.MacroLast(label: $0.label, what: $0.outcome ?? "", move: $0.tlt_move ?? 0) }
                ?? TLTBook.MacroLast(label: "—", what: "No prior print on file.", move: 0)
            let future = rs.filter { $0.event_date >= today }.map {
                TLTBook.MacroDate(d: $0.event_date, label: $0.label, tag: $0.tag ?? "", last: nil, inDays: Self.daysTo($0.event_date))
            }
            return TLTBook.MacroClass(key: key, name: first.class_name, cat: first.class_cat, last: last, dates: future)
        }
    }
    var classOptions: [(key: String, name: String, cat: String)] { classes.map { (key: $0.key, name: $0.name, cat: $0.cat) } }

    private static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York"); return f }()
    static var todayISO: String { fmt.string(from: Date()) }
    static func daysTo(_ iso: String) -> Int {
        guard let d = fmt.date(from: iso) else { return 0 }
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
    }
}

// MARK: - add event

private struct AddEventSheet: View {
    let store: EventsStore
    @Environment(\.dismiss) private var dismiss
    @State private var classSel = ""          // class_key; "" = a new class
    @State private var newName = ""
    @State private var newCat = ""
    @State private var date = Date()
    @State private var label = ""
    @State private var tag = ""

    private var canAdd: Bool { !label.isEmpty && (!classSel.isEmpty || (!newName.isEmpty && !newCat.isEmpty)) }

    var body: some View {
        let opts = store.classOptions
        return ZStack {
            Ink.canvas.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Add event").font(InkFont.serif(25)).tracking(25 * -0.01).foregroundStyle(Ink.text)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Ink.text)
                            .frame(width: 34, height: 34).overlay(Circle().strokeBorder(Ink.hair, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
                .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        labelled("Class") {
                            Menu {
                                ForEach(opts, id: \.key) { o in Button(o.name) { classSel = o.key } }
                                Button("New class…") { classSel = "" }
                            } label: {
                                HStack {
                                    Text(classSel.isEmpty ? "New class…" : (opts.first { $0.key == classSel }?.name ?? classSel))
                                        .font(InkFont.display(15, .regular)).foregroundStyle(Ink.text)
                                    Spacer()
                                    Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(Ink.dim)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 11)
                                .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
                            }
                        }
                        if classSel.isEmpty {
                            field("Class name (e.g. Jobs)", $newName)
                            field("Category (e.g. Labour)", $newCat)
                        }
                        labelled("Date") {
                            DatePicker("", selection: $date, displayedComponents: .date).labelsHidden().tint(Ink.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        field("Label (e.g. Sep 15–16)", $label)
                        field("Tag (e.g. SEP · projections)", $tag)
                    }
                    .padding(20)
                }

                Button { add() } label: {
                    Text("ADD EVENT").font(InkFont.mono(11)).tracking(11 * 0.08)
                        .foregroundStyle(canAdd ? Ink.invertText : Ink.dim)
                        .frame(maxWidth: .infinity).frame(minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(canAdd ? Ink.invertBg : Ink.hair))
                }
                .buttonStyle(.plain).disabled(!canAdd)
                .padding(EdgeInsets(top: 14, leading: 20, bottom: 30, trailing: 20))
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Ink.canvas)
    }

    private func add() {
        let key = classSel.isEmpty ? newName.lowercased().replacingOccurrences(of: " ", with: "-") : classSel
        let name = classSel.isEmpty ? newName : (store.classOptions.first { $0.key == classSel }?.name ?? newName)
        let cat = classSel.isEmpty ? newCat : (store.classOptions.first { $0.key == classSel }?.cat ?? newCat)
        store.add(.init(class_key: key, class_name: name, class_cat: cat,
                        event_date: EventsStore.fmt.string(from: date), label: label, tag: tag.isEmpty ? nil : tag))
        dismiss()
    }

    @ViewBuilder private func labelled<C: View>(_ k: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(k.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim)
            content()
        }
    }
    private func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        labelled(placeholder.components(separatedBy: " (").first ?? placeholder) {
            TextField(placeholder, text: text)
                .font(InkFont.display(15, .regular)).foregroundStyle(Ink.text)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
        }
    }
}
