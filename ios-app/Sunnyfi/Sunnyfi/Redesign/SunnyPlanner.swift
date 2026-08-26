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
    let zoneLabel: String        // "PLANNER"
    let stamp: String            // an execution DATE, never a status word
    /// ⚠ THE INSTRUCTION IS THE CARD'S ANSWER, so it takes the largest slot and
    /// the ONE bold. `verb` is context at 300, `answer` is the answer at 700 —
    /// "Sell" then "22 TLT puts". One bold, the same rule as every other card.
    let verb: String
    let answer: String
    /// ⚠ AND IT MUST NOT RESTATE THE DISCS. The discs print the two magnitudes;
    /// the sentence names the PATTERN and the tag gives the verdict. It used to
    /// carry "−0.42% then −0.79%", which is the same fact twice on one row.
    let evidence: String
    let sessions: [Session]      // exactly two. never three.
    let footerLead: String       // "Place it "
    let footerAnswer: String     // "Tuesday" — the actionable half, at 700

    struct Session { let pct: String }        // UNSIGNED — the disc's arrow is the sign
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
        .padding(S.padCardM)                    // 17 19 16 — the retired ruled build used 16/19/15
        .frame(maxWidth: .infinity)
        .aspectRatio(S.Size.m.ratio, contentMode: .fit)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCard)
        .measure("planner-card")
    }

    /* ⚠ AN AMBER CHIP, NOT A RED STAMP, AND NO ROTATION ANYWHERE. The ruled
       build used a tilted 1.5px outlined stamp in --stamp-ink; that was a hand
       affordance and it went with the hand. Amber is the deck's attention
       pairing, and a date is attention, not loss.

       The market-state dot that used to sit before the label is gone and stays
       gone — the rule against a ticker strip and a state dot applies here too. */
    private var header: some View {
        HStack(spacing: S.gap6) {
            Text(m.zoneLabel)
                .font(InkFont.display(S.t10, S.wBold))
                .tracking(S.track(S.t10, S.lsLabel))
                .textCase(.uppercase)
                .foregroundStyle(S.mute)
            Spacer(minLength: 0)
            SunnyChip(text: m.stamp)
        }
    }

    private var body_: some View {
        HStack(alignment: .center, spacing: S.gap7) {
            VStack(alignment: .leading, spacing: 7) {
                Text(instruction)
                    .lineSpacing(S.leading(S.t19, S.wLightN, S.lhTight))
                    .fixedSize(horizontal: false, vertical: true)
                Text(evidenceRuns)
                    .lineSpacing(S.leading(S.tDigestBody, S.wLightN, S.lhLoose))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            discs
        }
    }

    /// One bold, and it is the thing to do. `Sell` is context.
    private var instruction: AttributedString {
        var lead = AttributedString(m.verb + " ")
        lead.font = S.inter(S.t19, S.wLightN)
        var ans = AttributedString(m.answer)
        ans.font = S.inter(S.t19, S.wBoldN)
        var all = lead + ans
        all.foregroundColor = S.ink
        all.tracking = S.track(S.t19, -0.01)
        return all
    }

    private var evidenceRuns: AttributedString {
        var out = AttributedString(m.evidence)
        out.font = S.inter(S.tDigestBody, S.wLightN)
        out.foregroundColor = S.ink
        out += AttributedString(" ") + BracketTag.bearish.attributed()
        return out
    }

    /// The trigger DRAWN rather than described. A five-session change strip in
    /// the 5-day card's idiom was built and rejected: it showed the streak in
    /// context, but the card's subject is the confirmed pattern, not the week's
    /// shape, and the strip needed dimmed context bars to make that point at all.
    private var discs: some View {
        HStack(spacing: S.gapDisc) {
            ForEach(Array(m.sessions.enumerated()), id: \.offset) { _, s in
                VStack(spacing: S.gap2) {
                    ZStack {
                        Circle().fill(S.lossBar)
                            .frame(width: S.streakDiscM, height: S.streakDiscM)
                        /* ⚠ WHITE NOW, NOT THE GROUND TOKEN. The rule is "the
                           glyph is the card's ground colour" — it was butter on
                           the ruled sheet and the ground changed. */
                        Text("\u{2193}")
                            .font(S.inter(S.streakGlyphM, S.wBoldN))
                            .foregroundStyle(S.onLoss)
                    }
                    // UNSIGNED. The arrow is the sign; a minus beside a downward
                    // arrow inside a red circle is the same fact three times.
                    Text(s.pct)
                        .font(S.inter(S.streakPct, S.wBoldN))
                        .foregroundStyle(S.loss)
                        .monospacedDigit()
                }
            }
        }
        .fixedSize()
    }

    /// Same one-bold rule as the body: the day is the actionable part. --ink-2
    /// rather than --mute because it is an instruction, not a caption.
    private var footer: some View {
        Text(footerRuns).fixedSize(horizontal: false, vertical: true)
    }

    private var footerRuns: AttributedString {
        var lead = AttributedString(m.footerLead)
        lead.font = S.inter(S.t12, S.wMidSmN)
        var ans = AttributedString(m.footerAnswer)
        ans.font = S.inter(S.t12, S.wBoldN)
        var all = lead + ans
        all.foregroundColor = S.ink2
        return all
    }
}

/* ⚠ RuledLines IS GONE. The 25px ruled butter sheet went with the hand layer on
   25 Aug 2026 — a ruled ground under Inter reads as a texture with no reason.
   Both paper treatments are out of the deck; do not reintroduce either from an
   old sheet or a screenshot. */

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
        verb = "Sell"
        answer = "\(n) TLT puts"
        evidence = "Two red sessions back to back"
        sessions = days.map { Session(pct: String(format: "%.2f%%", $0.pct)) }
        footerLead = "Place it "
        footerAnswer = p.day ?? "today"
    }

    private static func stamp(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let o = DateFormatter(); o.dateFormat = "MMM d"
        return o.string(from: d)          // "Aug 25"; the view uppercases it
    }
}
