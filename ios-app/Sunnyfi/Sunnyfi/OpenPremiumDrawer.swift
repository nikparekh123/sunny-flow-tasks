//
//  OpenPremiumDrawer.swift
//  Sunnyfi — Ink · the open-premium drawer
//
//  Every short option still open, across the WHOLE book, on every tab.
//
//  ── Why it is global ─────────────────────────────────────────────────────────
//  Nik: "It will stay on top irrelevant whether you're Nvidia, TLT or income...
//  because of so many positions I'm kind of getting lost." Every other screen in
//  the app is per-ticker. This is the only thing that answers "where am I" across
//  all of them, so it hangs off the nav rather than living inside a tab.
//
//  ── The design ───────────────────────────────────────────────────────────────
//  Claude Design's grad drawer, returned 2026-08-17 as ~/Downloads/income_export 2.
//  Four placements were drawn; the README says ship the gradient one. Closed, an
//  outlined tab peeks 40pt below the nav at 0.4 opacity carrying the total value
//  left. Open, the sheet slides down OVER the list without moving it, behind a
//  dimming scrim that closes on tap. 520ms, cubic-bezier(.32,.72,0,1).
//
//  The gradient breaks Ink Law 1 (hue belongs on chrome, not data). The design
//  takes that exception knowingly, on this one surface, and says so.
//
//  ── The contract ─────────────────────────────────────────────────────────────
//  Every string comes from open-premium. This file formats nothing.
//

import SwiftUI

// MARK: - payload

struct OpenPremium: Decodable {
    var ok: Bool?
    var build: String?
    var any_open: Bool?
    var unpriced: Int?
    var tape: Tape?
    var error: String?

    struct Cell: Decodable {
        var k: String
        var v: String
        var text: Bool?
        var mark: Bool?
    }
    struct Tape: Decodable {
        var lab: String
        var mini: String
        var cells: [Cell]
        var note: String?
    }
}

@Observable
final class OpenPremiumStore {
    var data: OpenPremium?
    var loading = false

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/open-premium") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("{}".utf8)
        if let (d, _) = try? await URLSession.shared.data(for: req),
           let parsed = try? JSONDecoder().decode(OpenPremium.self, from: d),
           parsed.error == nil {
            data = parsed
        }
    }
}

// MARK: - the drawer

struct OpenPremiumDrawer: View {
    let tape: OpenPremium.Tape
    @Binding var open: Bool

    /// The design's own curve and duration. Slower than the app's usual motion on
    /// purpose: the sheet travels its whole height, and at Ink's normal speed it
    /// reads as a flicker rather than a drawer.
    private var motion: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.52) }

    var body: some View {
        ZStack(alignment: .top) {
            sheet
                .offset(y: open ? 0 : -(sheetHeight))
                .animation(motion, value: open)
        }
        .frame(height: 42, alignment: .top)   // only the tab occupies layout
        .zIndex(20)
    }

    /// The sheet's own height is unknown until it lays out, so the closed offset
    /// is measured rather than guessed: a fixed guess left a sliver of the ledger
    /// showing above the tab on the taller "nothing open" copy.
    @State private var sheetHeight: CGFloat = 320

    private var sheet: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tape.lab.uppercased())
                    .font(InkFont.mono(12.5)).tracking(12.5 * 0.16)
                    .foregroundStyle(Ink.dim)
                    .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
                ledger
                if let note = tape.note {
                    Text(note).font(InkFont.mono(11.5)).tracking(11.5 * 0.04)
                        .foregroundStyle(Ink.dim)
                        .padding(EdgeInsets(top: 0, leading: 18, bottom: 14, trailing: 18))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(gradient)
            .clipShape(UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 0, bottomLeading: Ink.radiusCard,
                                   bottomTrailing: Ink.radiusCard, topTrailing: 0),
                style: .continuous))
            .shadow(color: .black.opacity(0.34), radius: 15, y: 14)
            .padding(.horizontal, 16)
            .background(GeometryReader { g in
                Color.clear.onAppear { sheetHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in sheetHeight = h }
            })

            tab
        }
    }

    /// severe into fire into surface, per the design. The one place in the app
    /// where hue sits on chrome rather than on data.
    private var gradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.62, green: 0.30, blue: 0.16).opacity(0.52), location: 0.0),
                .init(color: Color(red: 0.85, green: 0.47, blue: 0.14).opacity(0.34), location: 0.52),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom)
        .background(Ink.surface)
    }

    private var ledger: some View {
        // 2x2. Four figures is exactly the point: any more and it stops being
        // readable at a glance, which is the only job it has.
        let cells = tape.cells
        return VStack(spacing: 18) {
            ForEach(0..<((cells.count + 1) / 2), id: \.self) { row in
                HStack(alignment: .top, spacing: 24) {
                    ForEach(0..<2, id: \.self) { col in
                        let i = row * 2 + col
                        if i < cells.count { cell(cells[i]) } else { Spacer() }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 0, leading: 18, bottom: 16, trailing: 18))
    }

    private func cell(_ c: OpenPremium.Cell) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.k.uppercased()).font(InkFont.mono(12.5)).tracking(12.5 * 0.07)
                .foregroundStyle(Ink.dim).lineLimit(1).minimumScaleFactor(0.85)
            Group {
                if c.text == true {
                    Text(c.v).font(InkFont.display(15)).foregroundStyle(Ink.text)
                } else {
                    Text(c.v).font(InkFont.mono(20)).tracking(20 * -0.03)
                        .foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.bottom, c.mark == true ? 3 : 0)
            .overlay(alignment: .bottom) {
                if c.mark == true { Rectangle().fill(Ink.text).frame(height: 1.5) }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The tab: 30pt tall, bottom-rounded, no top border, and dim until touched.
    /// Closed it carries the total value left, which is the one figure worth
    /// seeing without opening anything.
    private var tab: some View {
        Button {
            withAnimation(motion) { open.toggle() }
        } label: {
            HStack(spacing: 10) {
                Text(open ? tape.lab.uppercased() : tape.mini)
                    .font(InkFont.mono(open ? 12 : 13))
                    .tracking(open ? 12 * 0.14 : 13 * 0.02)
                    .foregroundStyle(open ? Ink.dim : Ink.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.dim)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 0, bottomLeading: 16,
                                       bottomTrailing: 16, topTrailing: 0),
                    style: .continuous)
                .fill(open ? AnyShapeStyle(gradientPill) : AnyShapeStyle(Color.clear)))
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 0, bottomLeading: 16,
                                       bottomTrailing: 16, topTrailing: 0),
                    style: .continuous)
                .strokeBorder(open ? .clear : Ink.text, lineWidth: 1))
            .opacity(open ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .frame(height: 42, alignment: .top)
    }

    private var gradientPill: LinearGradient {
        LinearGradient(colors: [Ink.surface,
                                Color(red: 0.85, green: 0.47, blue: 0.14).opacity(0.16)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// The scrim. Its own view so it can sit behind the sheet but above the list,
/// covering the whole screen rather than the drawer's 42pt of layout.
struct OpenPremiumScrim: View {
    @Binding var open: Bool
    var body: some View {
        if open {
            Ink.canvas.opacity(0.66)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture { withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.52)) { open = false } }
                .transition(.opacity)
                .zIndex(10)
        }
    }
}
