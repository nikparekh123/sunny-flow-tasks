//
//  TodoViews.swift
//  Sunny
//
//  To do (handoff 2026-11-10-todo, App Explorations 134d, style d2): the quiet "7 to do" on Home's change line and
//  right of the Positions title, the sheet, and the list (SunnyTodo.dc.html): the add field with typed dates and its
//  preview line, rows with a circle, the text (the first book or watchlist ticker 600), the note and the date, a row
//  opened for its note, date and Delete, our own date picker, and Done · N folded. High fidelity: the values below
//  are the design's.
//

import SwiftUI

// MARK: - Tokens (the design's app columns)

enum TD {
    static let ink = S.ink
    static let mu = S.dyn(0x6E6E73, 0x98989D)
    static let rule = S.dynA(0x1D1D1F, 0.08, 0xFFFFFF, 0.10)
    static let ring = S.dynA(0x3C3C43, 0.36, 0xEBEBF5, 0.36)
    static let green = S.dyn(0x327133, 0x65C466)
    static let red = S.dyn(0xBC2E30, 0xFF6961)
    static let orange = S.dyn(0xA34B00, 0xF2A93B)
    static let accent = S.dyn(0x2E5ECA, 0x86A8F0)
    static let accentTint = S.dynA(0x2E5ECA, 0.10, 0x86A8F0, 0.16)
    static let track = S.dynA(0x767680, 0.12, 0x767680, 0.24)
    static let panel = S.dynA(0x767680, 0.08, 0x767680, 0.16)
    static let btn = S.dyn(0x1D1D1F, 0xF5F5F7)
    static let btnInk = S.dyn(0xFFFFFF, 0x000000)
    /// The entry point: one very light gray for the count and the words (Nik asked for it quiet; under 4.5:1 on purpose).
    static let link = S.dyn(0xAEAEB2, 0x636366)

    /// A day's colour on a row: overdue red, today orange, else muted.
    static func dateColor(_ d: String?, today t: String) -> Color { guard let d else { return mu }; return d < t ? red : d == t ? orange : mu }
}

// MARK: - The entry point

extension EnvironmentValues {
    /// Opens the To do sheet; nil hides "7 to do" (no book membership read yet).
    @Entry var todoTap: (() -> Void)? = nil
}

/// "7 to do" (the count 600, " to do" 500, 15/20 tabular, one light gray); "To do" alone with nothing open. A 44 pt
/// target (12 above, below and on the left) that does not grow the line it sits on.
struct TodoLink: View {
    let open: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if open > 0 { Text("\(open)").font(.inter(15, 600, tabular: true)) + Text(" to do").font(.inter(15, 500)) }
                else { Text("To do").font(.inter(15, 500)) }
            }
            .foregroundStyle(TD.link)
            .lineLimit(1).fixedSize()
            .frame(height: 20)
            .padding(.vertical, 12).padding(.leading, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -12).padding(.leading, -12)
        .accessibilityLabel(open > 0 ? "To do, \(open) open" : "To do, nothing open")
    }
}

// MARK: - The sheet

/// Over whatever tab is up, the Time value sheet's recipe: grabber, "To do" 22/28 700 and its line, the close button,
/// and the list scrolling on its own (padding 0 20 28).
struct TodoSheet: View {
    /// The book's and the watchlist's tickers: the first one in a to do's text is 600.
    let known: Set<String>
    let close: () -> Void
    @State private var store = TodoStore.shared

    var body: some View {
        let n = store.openCount
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(S.grabber).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 12)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("To do").sType(SType(size: 22, weight: 700, line: 28, tracking: 0), tabular: false).foregroundStyle(TD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text((store.shared ? "Shared by both accounts · " : "") + (n > 0 ? "\(n) open" : "Nothing open"))
                        .sType(SType(size: 13, weight: 400, line: 18, tracking: 0)).foregroundStyle(TD.mu)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Path { p in p.move(to: CGPoint(x: 2.5, y: 2.5)); p.addLine(to: CGPoint(x: 9.5, y: 9.5)); p.move(to: CGPoint(x: 9.5, y: 2.5)); p.addLine(to: CGPoint(x: 2.5, y: 9.5)) }
                        .stroke(TD.mu, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .frame(width: 12, height: 12)
                        .frame(width: 30, height: 30).background(Circle().fill(S.chip))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -7).padding(.trailing, -7)
                .accessibilityLabel("Close")
            }
            .padding(.top, 2).padding(.bottom, 14)
            .padding(.horizontal, 20)
            ScrollView {
                TodoList(known: known, close: close).padding(.horizontal, 20).padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(S.sheetFill)
        .task { await store.refresh() }
    }
}

// MARK: - The list

struct TodoList: View {
    let known: Set<String>
    var close: (() -> Void)? = nil
    @State private var store = TodoStore.shared
    @State private var draft = ""
    /// The add field's pick: nil = take a date typed in the text; "" = No date (stays without one); else the day.
    @State private var addPick: String?
    /// Which picker is open: "add" or a row's id.
    @State private var pk: String?
    /// The picker's month (yyyy-MM-01).
    @State private var month = ""
    /// The row opened for its note, date and Delete (one at a time).
    @State private var ex: String?
    @State private var notes: [String: String] = [:]
    @State private var doneOpen = false
    @FocusState private var addFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var today: String { TodoDates.today() }
    private var parsed: (iso: String, text: String)? { addPick == nil ? TodoDates.parse(draft, today: today) : nil }
    /// The day the add field will use.
    private var addDay: String? { addPick == "" ? nil : addPick ?? parsed?.iso }

    var body: some View {
        let t = today, open = store.open, done = store.finished
        VStack(alignment: .leading, spacing: 0) {
            addField(t).padding(.bottom, 8)
            ForEach(open) { x in row(x, t).transition(.opacity) }
            if open.isEmpty {
                Text("Nothing on the list.").sType(SType(size: 15, weight: 400, line: 20, tracking: 0), tabular: false).foregroundStyle(TD.mu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14).padding(.bottom, 4)
                    .overlay(alignment: .top) { TD.rule.frame(height: 1) }
            }
            if !done.isEmpty { doneFold(done, t) }
        }
        .animation(reduce ? .easeOut(duration: 0.2) : .easeOut(duration: 0.4), value: open.map(\.id))
        .onKeyPress(.escape) {
            if pk != nil { pk = nil; return .handled }
            if let c = close { c(); return .handled }
            return .ignored
        }
    }

    // MARK: Add

    private func addField(_ t: String) -> some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let label = addDay.map { TodoDates.lab($0, today: t) } ?? "Date"
        let color: Color = (addPick != nil && addPick != "") ? TD.ink : parsed != nil ? TD.accent : TD.mu
        let bg: Color = parsed != nil ? TD.accentTint : pk == "add" ? TD.panel : .clear
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("", text: $draft, prompt: Text("Try “call accountant tomorrow”").foregroundStyle(TD.mu))
                    .font(.inter(15, 400)).foregroundStyle(TD.ink)
                    .focused($addFocus)
                    .submitLabel(.done)
                    .onSubmit(addNew)
                    .accessibilityLabel("Add a to do")
                Button { openPicker("add", current: addDay, today: t) } label: {
                    HStack(spacing: 6) {
                        TodoCalendarIcon().frame(width: 15, height: 15)
                        Text(label).font(.inter(13, 600)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(Capsule().fill(bg))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Date: \(label)")
                .animation(.easeOut(duration: 0.2), value: label)
                Button(action: addNew) {
                    Path { p in p.move(to: CGPoint(x: 7, y: 2)); p.addLine(to: CGPoint(x: 7, y: 12)); p.move(to: CGPoint(x: 2, y: 7)); p.addLine(to: CGPoint(x: 12, y: 7)) }
                        .stroke(TD.btnInk, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 14, height: 14)
                        .frame(width: 32, height: 32).background(Circle().fill(TD.btn))
                        .opacity(empty ? 0.3 : 1)
                        .animation(.easeOut(duration: 0.2), value: empty)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
            }
            .padding(.leading, 16).padding(.trailing, 6)
            .frame(height: 44)
            .background(Capsule().fill(TD.track))
            // The preview line while a date is found in the text: Adds “Call accountant”, due tomorrow.
            if let p = parsed {
                (Text("Adds “") + Text(p.text).font(.inter(13, 500)).foregroundColor(TD.ink) + Text("”, due ")
                 + Text(TodoDates.due(p.iso, today: t)).font(.inter(13, 600)).foregroundColor(TD.accent))
                    .sType(SType(size: 13, weight: 400, line: 18, tracking: 0), tabular: false).foregroundStyle(TD.mu)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            if pk == "add" { picker(current: addDay, today: t) }
        }
    }

    private func addNew() {
        let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let p = parsed
        // A picked date wins and the text stays as typed; No date keeps it without one.
        let text = p?.text ?? TodoDates.capitalized(raw)
        let day = addPick == "" ? nil : addPick ?? p?.iso
        store.add(text, due: day)
        draft = ""; addPick = nil
        if pk == "add" { pk = nil }
        addFocus = true
    }

    // MARK: Rows

    private func row(_ x: TodoStore.Item, _ t: String) -> some View {
        let ck = x.done, isOpen = ex == x.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                circle(ck) { store.toggle(x.id) }
                    .padding(.top, -1)
                    .accessibilityLabel("\(ck ? "Not done" : "Done"): \(x.text)")
                Button { openRow(x.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        rowText(x.text, struck: ck)
                        if !x.note.isEmpty {
                            Text(x.note).sType(SType(size: 13, weight: 400, line: 18, tracking: 0), tabular: false).foregroundStyle(TD.mu)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isOpen ? "Closes the note and date" : "Opens the note, date and Delete")
                if let d = x.due {
                    Text(TodoDates.lab(d, today: t)).font(.inter(13, 500, tabular: true)).foregroundStyle(TD.dateColor(d, today: t))
                        .frame(height: 20).fixedSize()
                }
            }
            .padding(.vertical, 12)
            if isOpen { editor(x, t) }
        }
        .opacity(ck ? 0.5 : 1)
        .animation(.easeOut(duration: 0.4), value: ck)
        .overlay(alignment: .top) { TD.rule.frame(height: 1) }
    }

    /// The text 15/20, the first book or watchlist ticker 600 (Nik: those only).
    private func rowText(_ s: String, struck: Bool) -> Text {
        let base = SType(size: 15, weight: 400, line: 20, tracking: 0)
        if let r = Self.ticker(in: s, known: known) {
            let pre = String(s[..<r.lowerBound]), tk = String(s[r]), post = String(s[r.upperBound...])
            return (Text(pre).strikethrough(struck) + Text(tk).font(.inter(15, 600)).strikethrough(struck) + Text(post).strikethrough(struck))
                .font(.inter(base.size, base.weight)).foregroundColor(TD.ink)
        }
        return Text(s).strikethrough(struck).font(.inter(base.size, base.weight)).foregroundColor(TD.ink)
    }
    /// The design's tk(): the first word of 2 to 5 capitals that is a name in the book or on the watchlist.
    static func ticker(in s: String, known: Set<String>) -> Range<String.Index>? {
        guard let rx = try? NSRegularExpression(pattern: #"\b[A-Z]{2,5}\b"#) else { return nil }
        let ns = s as NSString
        for m in rx.matches(in: s, range: NSRange(location: 0, length: ns.length)) where known.contains(ns.substring(with: m.range)) {
            return Range(m.range, in: s)
        }
        return nil
    }

    private func circle(_ ck: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            ZStack {
                Circle().fill(ck ? TD.green : .clear)
                Circle().strokeBorder(ck ? TD.green : TD.ring, lineWidth: 1.5)
                if ck {
                    Path { p in p.move(to: CGPoint(x: 2.5, y: 6.2)); p.addLine(to: CGPoint(x: 4.8, y: 8.5)); p.addLine(to: CGPoint(x: 9.5, y: 3.6)) }
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 22, height: 22)
            .animation(.easeOut(duration: 0.2), value: ck)
            .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-11)
        .accessibilityAddTraits(ck ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: ck)
    }

    private func openRow(_ id: String) {
        if let was = ex { store.flushNote(was) }
        withAnimation(.easeOut(duration: 0.2)) {
            if ex == id { ex = nil; if pk == id { pk = nil } }
            else { ex = id; if pk != "add" { pk = nil } }
        }
    }

    /// The opened row: the note, then the date button and Delete, the picker under them.
    private func editor(_ x: TodoStore.Item, _ t: String) -> some View {
        let dLabel = x.due.map { TodoDates.lab($0, today: t) } ?? "Add a date"
        let dColor: Color = x.due == nil ? TD.mu : x.due! < t ? TD.red : x.due! == t ? TD.orange : TD.ink
        return VStack(alignment: .leading, spacing: 8) {
            TextField("", text: Binding(get: { notes[x.id] ?? x.note }, set: { notes[x.id] = $0; store.setNote(x.id, $0) }),
                      prompt: Text("Add a note").foregroundStyle(TD.mu), axis: .vertical)
                .font(.inter(13, 400)).foregroundStyle(TD.ink)
                .padding(.vertical, 9).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TD.track))
                .onSubmit { store.flushNote(x.id) }
                .accessibilityLabel("Note")
            HStack(spacing: 10) {
                Button { openPicker(x.id, current: x.due, today: t) } label: {
                    HStack(spacing: 6) {
                        TodoCalendarIcon().frame(width: 15, height: 15)
                        Text(dLabel).font(.inter(13, 600)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(dColor)
                    .padding(.leading, 10).padding(.trailing, 12).frame(height: 32)
                    .background(Capsule().fill(TD.track))
                    .frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Date: \(dLabel)")
                Spacer(minLength: 0)
                Button {
                    store.delete(x.id)
                    withAnimation(.easeOut(duration: 0.2)) { ex = nil; pk = nil }
                } label: {
                    Text("Delete").font(.inter(13, 500)).foregroundStyle(TD.red).frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, -6)
            if pk == x.id { picker(current: x.due, today: t) }
        }
        .padding(.leading, 34).padding(.bottom, 14)
    }

    // MARK: Done

    private func doneFold(_ done: [TodoStore.Item], _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { doneOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("Done · \(done.count)").font(.inter(13, 600))
                    Path { p in p.move(to: CGPoint(x: 3.5, y: 1.5)); p.addLine(to: CGPoint(x: 7, y: 5)); p.addLine(to: CGPoint(x: 3.5, y: 8.5)) }
                        .stroke(TD.mu, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 10, height: 10)
                        .rotationEffect(.degrees(doneOpen ? 90 : 0))
                }
                .foregroundStyle(TD.mu)
                .frame(height: 18)
                .padding(.top, 12).padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { TD.rule.frame(height: 1) }
            .accessibilityValue(doneOpen ? "Open" : "Folded")
            if doneOpen {
                ForEach(done) { x in
                    HStack(alignment: .top, spacing: 12) {
                        circle(true) { store.toggle(x.id) }.padding(.top, -1)
                            .accessibilityLabel("Not done: \(x.text)")
                        Text(x.text).strikethrough().sType(SType(size: 15, weight: 400, line: 20, tracking: 0), tabular: false).foregroundStyle(TD.mu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let d = x.due {
                            Text(TodoDates.lab(d, today: t)).font(.inter(13, 400, tabular: true)).foregroundStyle(TD.mu).frame(height: 20).fixedSize()
                        }
                    }
                    .padding(.vertical, 12)
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: The date picker (our own, not the system's)

    private func openPicker(_ target: String, current: String?, today t: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            if pk == target { pk = nil } else { pk = target; month = String((current ?? t).prefix(8)) + "01" }
        }
    }
    private func pick(_ s: String?) {
        guard let target = pk else { return }
        if target == "add" { addPick = s ?? "" } else { store.setDue(target, s) }
        withAnimation(.easeOut(duration: 0.2)) { pk = nil }
    }

    /// Chips (Today · Tomorrow · Day after · Friday when 3 or more days off · Next week · No date when one is set),
    /// the month with ‹ ›, and the grid Monday first. A pick closes it.
    private func picker(current: String?, today t: String) -> some View {
        let t0 = TodoDates.weekday(t), fr = (5 - t0 + 7) % 7
        var qs: [(String, Int)] = [("Today", 0), ("Tomorrow", 1), ("Day after", 2)]
        if fr > 2 { qs.append(("Friday", fr)) }
        let nw = (1 - t0 + 7) % 7
        qs.append(("Next week", nw == 0 ? 7 : nw))
        var seen = Set<String>(), chips: [(t: String, d: String)] = []
        for (w, n) in qs { let d = TodoDates.plus(t, n); if seen.insert(d).inserted { chips.append((w, d)) } }
        let p = TodoDates.ymd(month) ?? TodoDates.ymd(t)!
        let lead = (TodoDates.weekday(month) + 6) % 7, nd = TodoDates.daysIn(p.y, p.m)
        let cells: [String?] = Array(repeating: nil, count: lead) + (1...nd).map { TodoDates.make(p.y, p.m, $0) }
        let padded = cells + Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return VStack(alignment: .leading, spacing: 10) {
            TodoFlow(spacing: 6) {
                ForEach(chips, id: \.d) { c in chip(c.t, on: current == c.d, fg: current == c.d ? TD.btnInk : TD.ink) { pick(c.d) } }
                if current != nil { chip("No date", on: false, fg: TD.mu) { pick(nil) } }
            }
            HStack(spacing: 8) {
                Text("\(TodoDates.monthsLong[p.m - 1]) \(String(p.y))").font(.inter(15, 600)).foregroundStyle(TD.ink)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    monthButton(left: true) { month = TodoDates.make(p.y, p.m - 1, 1) }.accessibilityLabel("Previous month")
                    monthButton(left: false) { month = TodoDates.make(p.y, p.m + 1, 1) }.accessibilityLabel("Next month")
                }
            }
            .padding(.leading, 4).padding(.top, 2)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, w in
                        Text(w).font(.inter(11, 600)).foregroundStyle(TD.mu).frame(maxWidth: .infinity).frame(height: 20)
                    }
                }
                .accessibilityHidden(true)
                ForEach(0..<(padded.count / 7), id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { c in day(padded[r * 7 + c], current: current, today: t) }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(TD.panel))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pick a date")
        .transition(.opacity)
    }

    private func chip(_ s: String, on: Bool, fg: Color, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Text(s).font(.inter(13, 600)).foregroundStyle(fg)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(on ? TD.btn : TD.track))
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -7)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func monthButton(left: Bool, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Path { p in
                if left { p.move(to: CGPoint(x: 7.5, y: 2)); p.addLine(to: CGPoint(x: 3.5, y: 6)); p.addLine(to: CGPoint(x: 7.5, y: 10)) }
                else { p.move(to: CGPoint(x: 4.5, y: 2)); p.addLine(to: CGPoint(x: 8.5, y: 6)); p.addLine(to: CGPoint(x: 4.5, y: 10)) }
            }
            .stroke(TD.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: 12, height: 12)
            .frame(width: 32, height: 32).contentShape(Circle())
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(-6)
    }

    @ViewBuilder private func day(_ s: String?, current: String?, today t: String) -> some View {
        if let s, let p = TodoDates.ymd(s) {
            let on = s == current, td = s == t
            Button { pick(s) } label: {
                Text("\(p.d)").font(.inter(15, on || td ? 700 : 400, tabular: true))
                    .foregroundStyle(on ? TD.btnInk : td ? TD.accent : s < t ? TD.mu : TD.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(on ? TD.btn : .clear))
                    .animation(.easeOut(duration: 0.15), value: on)
                    .frame(maxWidth: .infinity).frame(height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodoDates.full(s) + (td ? ", today" : ""))
            .accessibilityAddTraits(on ? .isSelected : [])
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 40).accessibilityHidden(true)
        }
    }
}

/// The design's calendar (a 24 grid: the page, its top rule and two rings), stroked 1.8 at 24, in the text's colour.
struct TodoCalendarIcon: View {
    var body: some View {
        GeometryReader { g in
            let k = g.size.width / 24
            Path { p in
                p.addRoundedRect(in: CGRect(x: 3.5 * k, y: 5 * k, width: 17 * k, height: 15.5 * k), cornerSize: CGSize(width: 3 * k, height: 3 * k))
                p.move(to: CGPoint(x: 3.5 * k, y: 10 * k)); p.addLine(to: CGPoint(x: 20.5 * k, y: 10 * k))
                p.move(to: CGPoint(x: 8 * k, y: 3 * k)); p.addLine(to: CGPoint(x: 8 * k, y: 7 * k))
                p.move(to: CGPoint(x: 16 * k, y: 3 * k)); p.addLine(to: CGPoint(x: 16 * k, y: 7 * k))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Chips 6 apart, wrapping to a new line when they run out of room (the design's flex-wrap).
struct TodoFlow: Layout {
    var spacing: CGFloat = 6
    private func rows(_ maxW: CGFloat, _ subviews: Subviews) -> [CGRect] {
        var out: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + spacing + sz.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            let px = x > 0 ? x + spacing : 0
            out.append(CGRect(x: px, y: y, width: sz.width, height: sz.height))
            x = px + sz.width; rowH = max(rowH, sz.height)
        }
        return out
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = rows(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? r.map(\.maxX).max() ?? 0, height: r.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rows(bounds.width, subviews)
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: bounds.minX + r[i].minX, y: bounds.minY + r[i].minY), proposal: ProposedViewSize(r[i].size))
        }
    }
}
