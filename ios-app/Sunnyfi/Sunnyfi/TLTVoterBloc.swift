//
//  TLTVoterBloc.swift
//  Sunnyfi — TLT-only Voter bloc
//
//  The September question, the committee (three stance blocks), and a hand editor.
//  Leans are user-owned and persist on device (UserDefaults, the app's stand-in
//  for the prototype's localStorage). One table drives the question card, the
//  three blocks and the editor — change a lean and the tally recomputes.
//

import SwiftUI
import Supabase

// MARK: - model

struct BlocSeat: Identifiable, Codable {
    let code: String
    var name: String
    let seat: String
    var lean: Int              // −2 dove … +2 hawk
    var seen: String
    var note: String? = nil
    var chair: Bool = false
    var moved: String? = nil   // "in" | "out"
    var id: String { code }
}

@MainActor @Observable final class BlocStore {
    static let shared = BlocStore()

    var seats: [BlocSeat]
    var need: Int
    var verified = "Aug 6"
    var reverifyBy = "Aug 27"
    var swingWindow = "All four move on CPI Aug 12 → PCE Aug 28."

    private let client = SupabaseService.client

    private static let fixture: [BlocSeat] = [
        .init(code: "HAM", name: "Hammack", seat: "Cleveland", lean: 2, seen: "Jul 30"),
        .init(code: "LOG", name: "Logan", seat: "Dallas", lean: 2, seen: "Jul 28"),
        .init(code: "KAS", name: "Kashkari", seat: "Minneapolis", lean: 2, seen: "Aug 4", moved: "in"),
        .init(code: "WAR", name: "Warsh", seat: "Chair", lean: 1, seen: "Jul 29", note: "low-guidance", chair: true, moved: "in"),
        .init(code: "PHL", name: "Philadelphia", seat: "Philadelphia", lean: 1, seen: "Jul 21"),
        .init(code: "WIL", name: "Williams", seat: "New York", lean: 0, seen: "Jul 31"),
        .init(code: "JEF", name: "Jefferson", seat: "Vice Chair", lean: 0, seen: "Jul 22"),
        .init(code: "COO", name: "Cook", seat: "Governor", lean: 0, seen: "Jul 25"),
        .init(code: "BAR", name: "Barr", seat: "Supervision", lean: 0, seen: "Jul 18", moved: "out"),
        .init(code: "G1", name: "Governor", seat: "Governor", lean: -1, seen: "—"),
        .init(code: "G2", name: "Governor", seat: "Governor", lean: -1, seen: "—"),
        .init(code: "G3", name: "Governor", seat: "Governor", lean: -2, seen: "—"),
    ]

    private init() {
        seats = BlocStore.fixture
        need = 7
        Task { await load() }
    }

    // derived tally — never stored
    var committed: [BlocSeat] { seats.filter { $0.lean >= 2 } }
    var leaning: [BlocSeat] { seats.filter { $0.lean == 1 } }
    var swings: [BlocSeat] { seats.filter { $0.lean == 0 } }
    var secured: Int { committed.count + leaning.count }
    var short: Int { max(0, need - secured) }

    // ── Supabase rows (tlt_voter_bloc · tlt_bloc_meta) ──
    private struct SeatRow: Codable {
        let code: String; var name: String; let seat: String; var lean: Int
        var seen: String?; var note: String?; var chair: Bool?; var moved: String?; let sort: Int
    }
    private struct MetaRow: Codable { let id: Int; var need: Int; let verified: String?; let reverify_by: String?; let swing_window: String? }

    /// Read the committee off the DB — device-independent. Falls back to the
    /// seeded fixture if the table is unreachable.
    func load() async {
        if let rows: [SeatRow] = try? await client.from("tlt_voter_bloc").select().order("sort").execute().value, !rows.isEmpty {
            seats = rows.map { BlocSeat(code: $0.code, name: $0.name, seat: $0.seat, lean: $0.lean,
                                        seen: $0.seen ?? "—", note: $0.note, chair: $0.chair ?? false, moved: $0.moved) }
        }
        if let metas: [MetaRow] = try? await client.from("tlt_bloc_meta").select().eq("id", value: 1).execute().value, let m = metas.first {
            need = m.need
            verified = m.verified ?? verified; reverifyBy = m.reverify_by ?? reverifyBy; swingWindow = m.swing_window ?? swingWindow
        }
    }

    func writeSeat(_ i: Int) {
        guard seats.indices.contains(i) else { return }
        let s = seats[i]
        let row = SeatRow(code: s.code, name: s.name, seat: s.seat, lean: s.lean,
                          seen: s.seen, note: s.note, chair: s.chair, moved: s.moved, sort: i)
        Task { try? await client.from("tlt_voter_bloc").upsert(row, onConflict: "code").execute() }
    }
    func writeNeed() {
        let row = MetaRow(id: 1, need: need, verified: verified, reverify_by: reverifyBy, swing_window: swingWindow)
        Task { try? await client.from("tlt_bloc_meta").upsert(row, onConflict: "id").execute() }
    }
    func reset() {
        seats = Self.fixture; need = 7
        Task {
            for (i, s) in seats.enumerated() {
                let row = SeatRow(code: s.code, name: s.name, seat: s.seat, lean: s.lean,
                                  seen: s.seen, note: s.note, chair: s.chair, moved: s.moved, sort: i)
                try? await client.from("tlt_voter_bloc").upsert(row, onConflict: "code").execute()
            }
        }
        writeNeed()
    }
}

private enum Lean {
    static let hue: (Int) -> Color = { $0 > 0 ? Ink.loss : $0 < 0 ? Ink.gain : Ink.dim }
    static func mark(_ lean: Int) -> String {
        lean >= 2 ? "▲" : lean == 1 ? "△" : lean == 0 ? "·" : lean == -1 ? "▽" : "▼"
    }
}

// MARK: - the September question

private struct SeptemberCard: View {
    let b = BlocStore.shared
    var body: some View {
        InkCard(height: 496, stamp: (.stale, "Your count · edit to change it")) {
            InkBody {
                InkEyebrow(cat: "The September question") { InkBand(skin: .mod, text: "\(b.need) to hike") }
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("\(b.secured)").font(InkFont.mono(40, .medium)).tracking(40 * -0.04).foregroundStyle(Ink.text)
                            Text(" / \(b.need)").font(InkFont.mono(40, .medium)).tracking(40 * -0.04).foregroundStyle(Ink.dim)
                        }
                        Text("VOTES TOWARD A HIKE").font(InkFont.mono(11.5, .medium)).tracking(11.5 * 0.05)
                            .foregroundStyle(Ink.dim).padding(.top, 12)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(b.short)").font(InkFont.mono(20, .regular)).tracking(20 * -0.03).foregroundStyle(Ink.text)
                        Text("STILL TO WIN").font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim).padding(.top, 8).fixedSize()
                    }
                    .padding(.leading, 14).overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
                }
                .padding(.top, 20)
                voteBar
                InkSpacer()
                VStack(spacing: 0) {
                    countLine("▲", "Committed", b.committed.count, Ink.loss, first: true)
                    countLine("△", "Leaning", b.leaning.count, Ink.loss)
                    countLine("·", "Undecided", b.swings.count, Ink.dim)
                }
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            }
            InkFoot {
                footRow("Next evidence", "\(TLTBook.evidence.label) in \(TLTBook.evidence.inDays)d")
                footRow("Market says", "\(TLTBook.hike.odds)%")
            }
        }
    }

    private var voteBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<b.need, id: \.self) { i in
                let kind = i < b.committed.count ? "hawk" : i < b.secured ? "lean" : "open"
                RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous)
                    .fill(kind == "hawk" ? Ink.loss : .clear)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .overlay {
                        if kind != "hawk" {
                            RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous)
                                .strokeBorder(kind == "lean" ? Ink.loss : Ink.dim,
                                              style: .init(lineWidth: 1, dash: kind == "open" ? [3, 3] : []))
                        }
                    }
            }
        }
        .padding(.top, 18)
    }

    private func countLine(_ mark: String, _ k: String, _ v: Int, _ hue: Color, first: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(mark).font(.system(size: 11)).foregroundStyle(hue).frame(width: 14)
            Text(k).font(InkFont.display(14, .regular)).foregroundStyle(Ink.text)
            Spacer(minLength: 0)
            Text("\(v)").font(InkFont.mono(16, .regular)).tracking(16 * -0.02).foregroundStyle(Ink.text)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Ink.hair).frame(height: 1) } }
    }
    private func footRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k.uppercased()).font(InkFont.mono(11)).tracking(11 * 0.08).foregroundStyle(Ink.dim)
            Spacer()
            Text(v).font(InkFont.mono(14)).foregroundStyle(Ink.text)
        }
    }
}

// MARK: - the three stance blocks

private struct StanceCard: View {
    let stance: String        // "hawk" | "undecided" | "dove"
    let b = BlocStore.shared

    private var meta: (title: String, note: String, test: (BlocSeat) -> Bool, hue: Color?) {
        switch stance {
        case "hawk": return ("Hawkish", "Would vote to hike.", { $0.lean > 0 }, Ink.loss)
        case "dove": return ("Dovish", "Would vote to hold.", { $0.lean < 0 }, Ink.gain)
        default:     return ("Undecided", "The votes the hike has to win.", { $0.lean == 0 }, nil)
        }
    }

    var body: some View {
        let m = meta
        let seats = b.seats.filter(m.test).sorted { ($1.chair ? 1 : 0) < ($0.chair ? 1 : 0) }
        let moved = seats.filter { $0.moved != nil }.count
        return InkCard(height: 496, stamp: (.stale, "Set by hand · lean is your read")) {
            InkBody {
                InkEyebrow(cat: m.title) { InkBand(skin: .mod, text: "\(seats.count) of \(b.seats.count)") }
                Text(m.note.uppercased()).font(InkFont.mono(11.5)).tracking(11.5 * 0.05).foregroundStyle(Ink.dim).padding(.top, 14)
                VStack(spacing: 0) {
                    ForEach(Array(seats.enumerated()), id: \.element.id) { i, s in
                        seatRow(s, hue: m.hue, first: i == 0)
                    }
                }
                .padding(.top, 14)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
                InkSpacer()
            }
            InkFoot {
                Text((moved > 0 ? "\(moved) changed since last check" : "No change since last check").uppercased())
                    .font(InkFont.mono(11)).tracking(11 * 0.08).foregroundStyle(Ink.dim)
                Text(stance == "undecided" ? b.swingWindow : "Verified \(b.verified) · re-verify by \(b.reverifyBy).")
                    .font(InkFont.display(13.5, .regular)).foregroundStyle(Ink.dim)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func seatRow(_ s: BlocSeat, hue: Color?, first: Bool) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Text(Lean.mark(s.lean)).font(.system(size: 12)).foregroundStyle(hue ?? Ink.dim).frame(width: 14)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(s.name).font(InkFont.display(15, .regular)).foregroundStyle(Ink.text).lineLimit(1)
                    if s.chair {
                        Text("CHAIR").font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(Ink.invertText)
                            .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(Ink.invertBg))
                    }
                }
                Text("\(s.seat)\(s.note.map { " · " + $0 } ?? "")".uppercased())
                    .font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let moved = s.moved {
                Text((moved == "in" ? "moved in" : "moved out").uppercased())
                    .font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(Ink.dim)
                    .padding(.horizontal, 7).padding(.vertical, 3).overlay(Capsule().strokeBorder(Ink.dim, lineWidth: 1))
            }
            Text(s.seen.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim).fixedSize()
        }
        .frame(minHeight: 52)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Ink.hair).frame(height: 1) } }
    }
}

// MARK: - the section

struct TLTVoterBlocScreen: View {
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkSectionHead(title: "Voter bloc", action: "edit", onAction: { editing = true })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    SeptemberCard().inkEntrance(0)
                    StanceCard(stance: "hawk").inkEntrance(1)
                    StanceCard(stance: "undecided").inkEntrance(2)
                    StanceCard(stance: "dove").inkEntrance(3)
                }
                .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(isPresented: $editing) { BlocEditor(onClose: { editing = false }) }
    }
}

// MARK: - the editor

private struct BlocEditor: View {
    let onClose: () -> Void
    let b = BlocStore.shared

    var body: some View {
        ZStack { Ink.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 13) {
                    Button(action: onClose) {
                        Image(systemName: "arrow.left").font(.system(size: 15)).foregroundStyle(Ink.text)
                            .frame(width: 36, height: 36).overlay(Circle().strokeBorder(Ink.hair, lineWidth: 1))
                    }.buttonStyle(.plain)
                    Text("Voter bloc").font(InkFont.serif(27)).tracking(27 * -0.01).foregroundStyle(Ink.text)
                    Spacer()
                }
                .padding(EdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16))
                .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("\(b.secured) of \(b.need) · \(b.short) to win".uppercased())
                                .font(InkFont.mono(11.5)).tracking(11.5 * 0.06).foregroundStyle(Ink.dim)
                            Spacer()
                            Button { b.reset() } label: {
                                Text("RESET").font(InkFont.mono(10.5)).tracking(10.5 * 0.07).foregroundStyle(Ink.text)
                                    .padding(.horizontal, 13).frame(minHeight: 32)
                                    .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 18)

                        ForEach(b.seats.indices, id: \.self) { i in seatEditor(i) }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("VOTES NEEDED TO HIKE").font(InkFont.mono(11.5)).tracking(11.5 * 0.06).foregroundStyle(Ink.dim)
                            HStack(spacing: 0) {
                                ForEach([6, 7, 8], id: \.self) { n in seg("\(n)", on: b.need == n) { b.need = n; b.writeNeed() } }
                            }
                            .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: Ink.radiusElement))
                            Text("Saved on this device. The question card and all three blocks read from this table.")
                                .font(InkFont.display(13.5, .regular)).foregroundStyle(Ink.dim)
                                .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                        }
                        .padding(.top, 18).padding(.bottom, 40)
                        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func seatEditor(_ i: Int) -> some View {
        let s = b.seats[i]
        let k = s.lean > 0 ? "hawk" : s.lean < 0 ? "dove" : "undecided"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("name", text: Binding(get: { b.seats[i].name }, set: { b.seats[i].name = $0; b.writeSeat(i) }))
                    .font(InkFont.display(15, .regular)).foregroundStyle(Ink.text)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
                TextField("seen", text: Binding(get: { b.seats[i].seen }, set: { b.seats[i].seen = $0; b.writeSeat(i) }))
                    .font(InkFont.mono(13)).foregroundStyle(Ink.text).frame(width: 84)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
            }
            Text(s.seat.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim)
            HStack(spacing: 0) {
                seg("Hawk", on: k == "hawk", tint: Ink.loss) { setStance(i, "hawk") }
                seg("Undecided", on: k == "undecided") { setStance(i, "undecided") }
                seg("Dove", on: k == "dove", tint: Ink.gain) { setStance(i, "dove") }
            }
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Ink.radiusElement))
            if k != "undecided" {
                HStack(spacing: 0) {
                    seg("Committed", on: abs(s.lean) == 2) { setFirm(i, true) }
                    seg("Leaning", on: abs(s.lean) == 1) { setFirm(i, false) }
                }
                .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Ink.radiusElement))
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }

    private func seg(_ label: String, on: Bool, tint: Color? = nil, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label.uppercased()).font(InkFont.mono(11.5)).tracking(11.5 * -0.01)
                .foregroundStyle(on ? Ink.invertText : (tint ?? Ink.dim))
                .frame(maxWidth: .infinity).frame(minHeight: 36)
                .background(on ? Ink.invertBg : .clear)
        }.buttonStyle(.plain)
    }
    private func setStance(_ i: Int, _ k: String) {
        let cur = b.seats[i].lean
        b.seats[i].lean = k == "undecided" ? 0 : k == "hawk" ? (abs(cur) == 1 ? 1 : 2) : (abs(cur) == 1 ? -1 : -2)
        b.writeSeat(i)
    }
    private func setFirm(_ i: Int, _ firm: Bool) {
        let cur = b.seats[i].lean
        b.seats[i].lean = cur == 0 ? 0 : (cur > 0 ? 1 : -1) * (firm ? 2 : 1)
        b.writeSeat(i)
    }
}
