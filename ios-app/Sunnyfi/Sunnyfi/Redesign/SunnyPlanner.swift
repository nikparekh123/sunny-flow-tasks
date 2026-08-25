//
//  SunnyPlanner.swift
//  Sunny — the planner card (M). handoff/cards/planner-card.md.
//
//  The card that says DO SOMETHING. The only card in the deck carrying an
//  instruction, and the second of exactly two not on white.
//
//  ⚠ IT ONLY EXISTS ONCE THE TRIGGER HAS FIRED. Two red sessions back to back
//  put it in the feed. There is no waiting state, no pending state, no "1 of 2"
//  counter, no dashed circle. If the rule is not met the card is ABSENT — not
//  greyed, not conditional. A pre-planner state was tried and cut.
//
//  ⚠ THE TRIGGER COMES FROM tlt-planner, NEVER FROM A LOCAL COUNT. Reading
//  `tlt_daily_closes` on 24 Aug showed red on the 20th and red on the 21st and
//  looked armed; the engine said redStreak 0, because it reads live closes and
//  TLT was +0.68% that morning, which breaks the run. Two things counting red
//  days is how the scanner and the book ended up disagreeing about CPB. One
//  engine owns the gate.
//
//  ⚠ RULED LINES, NOT THE DIGEST'S DOT GRID. The digest is a page you read, the
//  planner is a line you write on. The two treatments stay distinct: no dots
//  here, no rules there. And no inset ring — the deckle edge is the digest's.
//
//  ⚠ THE INSTRUCTION IS HANDWRITTEN. THE EVIDENCE IS NOT. Both session
//  percentages are Inter 600 tabular. A handwritten percentage reads as
//  decorative and the trigger stops being believable.
//

import SwiftUI

struct PlannerModel {
    let zoneLabel: String        // "NOW"
    let stamp: String            // an execution DATE, never a status word
    let instruction: String      // handwritten, the only hand on the card
    let sessions: [Session]      // exactly two. never three.
    let footer: [FooterPart]

    struct Session { let pct: String }        // UNSIGNED — the red disc carries direction
    struct FooterPart { let text: String; let strong: Bool }
}

struct SunnyPlannerCard: View {
    let m: PlannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            body_
            Spacer(minLength: 0)
            footer
        }
        .padding(S.padPlannerM)                 // 16 / 19 / 15 — NOT --pad-card-m
        .frame(maxWidth: .infinity)
        .aspectRatio(S.Size.m.ratio, contentMode: .fit)
        .background {
            ZStack {
                S.plannerGround
                RuledLines()                    // 25px pitch, 1px line
            }
        }
        // overflow: hidden is REQUIRED here, unlike white cards — the ruled
        // ground must clip to the radius.
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        // Heavier than --shadow-card because the ground is darker than white and
        // the standard shadow disappears against it. NO inset ring.
        .shadow(color: S.shadowInk(0.09), radius: 2, x: 0, y: 2)
        .shadow(color: S.shadowInk(0.10), radius: 11, x: 0, y: 9)
        .measure("planner-card")
    }

    // MARK: header — live dot, zone label, then the stamp pushed right

    private var header: some View {
        HStack(spacing: S.gap3) {
            // Filled, never a ring. A ring means "watched, no open leg" on the
            // P&L cards; reusing it here would say the opposite.
            Circle().fill(S.plannerDot).frame(width: S.dot, height: S.dot)
            Text(m.zoneLabel)
                .font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, 0.13))
                .textCase(.uppercase)
                .foregroundStyle(S.plannerLabel)
            Spacer(minLength: 0)
            stamp
        }
        .frame(height: 22)
    }

    /// A RUBBER STAMP, not a chip — outline only, squared at 5px rather than
    /// pilled, and it carries a date, never a status word. −2.5° is the only
    /// rotation on the card, and it is deliberately not the digest chip's −1.4°.
    private var stamp: some View {
        Text(m.stamp)
            .font(S.inter(S.t11, S.wBoldN))
            .tracking(S.track(S.t11, 0.06))
            .textCase(.uppercase)
            .foregroundStyle(S.stampInk)
            .padding(S.padStamp)
            .overlay(RoundedRectangle(cornerRadius: S.stampRadius)
                .strokeBorder(S.stampBorder, lineWidth: 1.5))
            .rotationEffect(.degrees(S.stampTilt))
    }

    // MARK: body — instruction takes the slack, evidence sits on its baseline

    private var body_: some View {
        // flex-end: the instruction's last line and the percentages share a
        // bottom edge. Centre-aligning makes the discs float.
        HStack(alignment: .bottom, spacing: S.gap7) {
            /* ⚠ .95 CANNOT BE DONE WITH .lineSpacing — IT CLAMPS AT ZERO.
               The sheet wants an advance BELOW the font's own line height, so
               the two lines close up into one written gesture; SwiftUI's
               lineSpacing only ever adds. Passing it a negative number is a
               silent no-op, which is what the first build did: the lines sat a
               full line box apart and the instruction read as two statements
               rather than one.

               A VStack takes a negative spacing, so the lines are separate Texts
               and the overlap is explicit. Split on the newline the model
               already carries, so the model is unchanged. */
            VStack(alignment: .leading,
                   spacing: S.leadingHand(S.tHandInstruction, S.lhHandInstruction)) {
                ForEach(Array(m.instruction.split(separator: "\n").enumerated()),
                        id: \.offset) { _, line in
                    Text(String(line))
                        .font(S.hand(S.tHandInstruction))
                        .foregroundStyle(S.ink)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: S.gapDisc) {
                ForEach(Array(m.sessions.enumerated()), id: \.offset) { _, s in
                    VStack(spacing: S.gap2) {
                        ZStack {
                            Circle().fill(S.lossBar)
                                .frame(width: S.streakDiscM, height: S.streakDiscM)
                            // ⚠ THE GROUND COLOUR, NOT WHITE. On paper a white
                            // glyph glares; the ground reads as the sheet showing
                            // through the ink. The one place a background colour
                            // is used as a foreground, and it is intentional.
                            Text("\u{2193}")
                                .font(S.inter(S.streakGlyphM, S.wBoldN))
                                .foregroundStyle(S.plannerGround)
                        }
                        Text(s.pct)
                            .font(S.inter(S.streakPct, S.wSemiN))
                            .foregroundStyle(S.loss)
                            .monospacedDigit()
                    }
                }
            }
            .fixedSize()
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            ForEach(Array(m.footer.enumerated()), id: \.offset) { _, p in
                Text(p.text)
                    .font(S.inter(S.t12, p.strong ? S.wBoldN : S.wMidN))
                    .foregroundStyle(p.strong ? S.ink : S.plannerBody)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }
}

/// 25px pitch, 1px line. Ruled lines are NOT aligned to the type — they run
/// under it like real ruled paper, which is the point: a note written across a
/// sheet, not text set on a baseline grid.
private struct RuledLines: View {
    var body: some View {
        Canvas { ctx, size in
            var y = S.plannerRulePitch
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(S.plannerRuleInk))
                y += S.plannerRulePitch
            }
        }
        .allowsHitTesting(false)
    }
}


// MARK: - the store, and the gate that decides the card exists

/// ⚠ SELL, NEVER BUY. The build sheet's specimen reads "Buy 10 TLT puts" and it
/// is wrong for this book — that phrasing is the reference card's placeholder.
/// docs/STRATEGIES.md: TLT has no block and no floor, so there is nothing to
/// protect and nothing to hedge. "Sell puts on the second red day of a slide,
/// nearest Friday, nearest strike, flat size. Assignment is how you buy it. The
/// put IS the trade." Buying puts here would be the income sleeve's floor leg
/// applied to the one book that has no floor. Nik confirmed: sell, not buy.
@Observable
final class PlannerStore {
    /// Nil is the normal state and the correct one. The card exists only while
    /// two red sessions are confirmed; the rest of the time it is ABSENT, not
    /// greyed and not pending.
    var card: PlannerModel?
    var error: String?
    private var loading = false

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/tlt-planner") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        r.httpBody = Data("{}".utf8)

        /* Verification only. The gate is shut most days — that is the point of
           the gate — so the fired card cannot be screenshot or measured from
           live data on demand.

           ⚠ IT FEEDS A PAYLOAD THROUGH THE REAL DECODER, not a hand-built
           PlannerModel. Everything under test runs: the open-gate guard, the
           contracts guard, the two-day cap, "Sell" rather than "Buy", the stamp
           format and the footer. A probe that constructs the model directly
           would prove only that a struct can hold values. */
        if ProcessInfo.processInfo.arguments.contains("-plannerFired") {
            let canned = """
            {"gate":{"redStreak":2,"open":true,"days":[{"pct":0.42},{"pct":0.79}]},
             "plan":{"expiry":"2026-08-28","puts":{"contracts":22,"strike":83}},
             "asof":"2026-08-25","day":"Tuesday"}
            """
            card = (try? JSONDecoder().decode(PlannerPayload.self, from: Data(canned.utf8)))
                .flatMap(PlannerModel.init)
            return
        }

        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { error = "HTTP \(h.statusCode)"; return }
            let p = try JSONDecoder().decode(PlannerPayload.self, from: d)
            card = PlannerModel(p)
        } catch { self.error = String(describing: error) }
    }
}

private struct PlannerPayload: Decodable {
    struct Gate: Decodable {
        var redStreak: Int
        var open: Bool
        var days: [Day]?
        struct Day: Decodable { var pct: Double }
    }
    struct Plan: Decodable {
        var expiry: String?
        var puts: Puts?
        struct Puts: Decodable { var contracts: Double?; var strike: Double? }
    }
    var gate: Gate?
    var plan: Plan?
    var asof: String?
    var day: String?
}

extension PlannerModel {
    /// Returns nil whenever the card should not be in the feed at all.
    fileprivate init?(_ p: PlannerPayload) {
        guard let g = p.gate, g.open else { return nil }
        let n = Int(p.plan?.puts?.contracts ?? 0)
        /* An open gate with nothing to write is still nothing to do. The card
           says DO SOMETHING; "Sell 0 TLT puts" is not something. */
        guard n > 0 else { return nil }

        // Exactly two, never three, however long the run is. The streak widget
        // is where a longer run belongs.
        let days = (g.days ?? []).prefix(2)
        guard days.count == 2 else { return nil }

        zoneLabel = "Planner"
        stamp = PlannerModel.stamp(p.asof ?? "")
        instruction = "Sell \(n)\nTLT puts"
        sessions = days.map { Session(pct: String(format: "%.2f%%", $0.pct)) }
        /* ⚠ NO EM DASH. The reference footer is "Two red days back to back —
           place it Monday"; Nik's rule is no em dashes anywhere in app copy, so
           the joint is a middle dot. The strong half is the ACTION, the quiet
           half is the reason, which is the shape the sheet ships. */
        footer = [
            FooterPart(text: "Two red days back to back · ", strong: false),
            FooterPart(text: "place it \(p.day ?? "today")", strong: true),
        ]
    }

    private static func stamp(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let o = DateFormatter(); o.dateFormat = "MMM d"
        return o.string(from: d)          // "Aug 25"; the view uppercases it
    }
}
