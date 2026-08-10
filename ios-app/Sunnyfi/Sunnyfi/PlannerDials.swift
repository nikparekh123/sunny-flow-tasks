//
//  PlannerDials.swift
//  The two inputs no data feed can supply.
//
//  Everything else the planner reads is fetched. These two are judgements, and the
//  model is meaningfully wrong without them: with the macro dial unset the tool reads
//  82 on a day Nik calls a 72, because "no reading" defaults to no drag rather than to
//  the drag he actually sees. An unset dial is not neutral, it is optimistic.
//
//  Stored locally rather than in Postgres on purpose — one user, one phone, and a round
//  trip to set a number you change twice a quarter is friction for no benefit. If this
//  ever needs to follow the account, it moves to a table without the call sites changing.
//

import SwiftUI

@MainActor
@Observable
final class PlannerDials {
    static let shared = PlannerDials()

    /// 0 to 10, how the last quarter actually read. Only meaningful in the weeks after a
    /// print — the edge decays it to nothing over sixty sessions on its own.
    var grade: Int? {
        didSet { d.set(grade ?? -1, forKey: kGrade); if grade != nil { gradeSetOn = Date() } }
    }
    private(set) var gradeSetOn: Date? {
        didSet { d.set(gradeSetOn?.timeIntervalSince1970 ?? 0, forKey: kGradeOn) }
    }

    /// −12 to +12. The conditions no calendar carries: sticky inflation, a live conflict,
    /// a rates regime. Slow moving, set by hand, worth up to twelve points of conviction.
    var macro: Int {
        didSet { d.set(macro, forKey: kMacro); macroSetOn = Date() }
    }
    private(set) var macroSetOn: Date? {
        didSet { d.set(macroSetOn?.timeIntervalSince1970 ?? 0, forKey: kMacroOn) }
    }

    /// A dial nobody has touched in two months is not a current read of the world.
    var macroIsStale: Bool {
        guard let on = macroSetOn else { return true }
        return Date().timeIntervalSince(on) > 60 * 86_400
    }

    var macroLabel: String {
        switch macro {
        case ..<(-7):  return "Heavy"
        case -7 ..< -2: return "A drag"
        case -2 ... 2:  return "Neutral"
        case 3 ... 7:   return "Helpful"
        default:        return "Strong"
        }
    }

    private let d = UserDefaults.standard
    private let kGrade = "planner.grade", kGradeOn = "planner.gradeOn"
    private let kMacro = "planner.macro", kMacroOn = "planner.macroOn"

    private init() {
        let g = d.object(forKey: kGrade) as? Int ?? -1
        grade = g >= 0 ? g : nil
        macro = d.object(forKey: kMacro) as? Int ?? 0
        let go = d.double(forKey: kGradeOn), mo = d.double(forKey: kMacroOn)
        gradeSetOn = go > 0 ? Date(timeIntervalSince1970: go) : nil
        macroSetOn = mo > 0 ? Date(timeIntervalSince1970: mo) : nil
    }
}

// MARK: - Controls

/// 0 to 10. Shown only in the post-print window, because outside it the question has no
/// answer worth giving and a permanently visible input reads as a setting rather than a
/// judgement.
struct GradeDial: View {
    @Bindable var dials = PlannerDials.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How was the quarter?").font(.system(size: 14.5))
                Spacer()
                Text(dials.grade.map { "\($0) / 10" } ?? "not set")
                    .font(InkFont.mono(13))
                    .foregroundStyle(dials.grade == nil ? Ink.delayed : Ink.text)
            }
            HStack(spacing: 5) {
                ForEach(0...10, id: \.self) { n in
                    Button { dials.grade = n } label: {
                        Text("\(n)")
                            .font(InkFont.mono(11, dials.grade == n ? .medium : .regular))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(dials.grade == n ? Ink.text : Color.clear)
                            .foregroundStyle(dials.grade == n ? Ink.invertText : Ink.text)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.hair, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(Ink.text)
    }
}

/// Five steps rather than a slider: this is a judgement with a handful of honest
/// positions, and a continuous control invites false precision about the world.
struct MacroDial: View {
    @Bindable var dials = PlannerDials.shared
    private let steps = [-10, -5, 0, 5, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The wider backdrop").font(.system(size: 14.5))
                Spacer()
                Text(dials.macroIsStale ? "not set recently" : dials.macroLabel)
                    .font(InkFont.mono(13))
                    .foregroundStyle(dials.macroIsStale ? Ink.delayed : Ink.text)
            }
            HStack(spacing: 6) {
                ForEach(steps, id: \.self) { n in
                    Button { dials.macro = n } label: {
                        Text(n == 0 ? "Neutral" : n < 0 ? String(repeating: "−", count: n == -10 ? 2 : 1)
                                                        : String(repeating: "+", count: n == 10 ? 2 : 1))
                            .font(InkFont.mono(11, dials.macro == n ? .medium : .regular))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(dials.macro == n ? Ink.text : Color.clear)
                            .foregroundStyle(dials.macro == n ? Ink.invertText : Ink.text)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.hair, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
            }
            Text("Inflation, rates, anything geopolitical. Worth up to 12 points of conviction.")
                .font(InkFont.mono(9.5)).tracking(9.5 * 0.1).foregroundStyle(Ink.dim)
        }
        .foregroundStyle(Ink.text)
    }
}
