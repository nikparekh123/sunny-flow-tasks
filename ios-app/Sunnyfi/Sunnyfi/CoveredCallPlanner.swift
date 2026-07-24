//
//  CoveredCallPlanner.swift
//  Sunnyfi
//
//  "Plan premium" — a PREVIEW-ONLY covered-call planner (Position Detail
//  v3). Pick upcoming Mon/Wed/Fri expiries, pick strikes off a live
//  ladder, stack legs, and see what you'd collect + the keep-vs-assigned
//  outcomes against your current average.
//
//  Nothing is ever submitted — this is a calculator. Premiums come from
//  Polygon via the option-ladder edge function (~15-min delayed).
//

import Combine
import SwiftUI

// MARK: - Wire models (decode option-ladder)

struct OptionLadder: Decodable, Sendable {
    let spot: Double?
    let strikes: [LadderStrike]
}
struct LadderStrike: Decodable, Sendable, Identifiable {
    let strike: Double
    let premium: Double
    let delta: Double?
    var id: Double { strike }
}

// MARK: - Planner state

struct PlannedLeg: Identifiable, Sendable {
    let id = UUID()
    let expiry: String
    let strike: Double
    let premiumPerShare: Double
    var contracts: Int
    var premiumTotal: Double { premiumPerShare * Double(contracts) * 100 }
}

@MainActor
final class PlannerModel: ObservableObject {
    let store: PortfolioStore
    let ticker: String
    let shares: Double
    let average: Double         // current average (adjusted) to score against
    let spot: Double
    let existingOpenContracts: Int   // calls already written against the book

    @Published var legs: [PlannedLeg] = []
    @Published var selectedExpiry: String?
    @Published var ladder: [LadderStrike] = []
    @Published var loading = false
    @Published var loadError: String?

    init(store: PortfolioStore, data: CoveredCallTicker) {
        self.store = store
        self.ticker = data.ticker
        self.shares = data.shares
        self.average = data.currentAverage
        self.spot = data.currentPrice
        self.existingOpenContracts = Int(data.openCallContracts)
    }

    /// Upcoming Mon/Wed/Fri expiries (next ~2 weeks), as ISO days.
    var expiries: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = cal.timeZone
        let start = cal.startOfDay(for: Date())
        var out: [String] = []
        for i in 0..<16 {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let wd = cal.component(.weekday, from: d)   // Mon 2, Wed 4, Fri 6
            if wd == 2 || wd == 4 || wd == 6 { out.append(df.string(from: d)) }
        }
        return out
    }

    /// Contracts already committed to existing open calls + planned legs.
    var committedContracts: Int {
        existingOpenContracts + legs.reduce(0) { $0 + $1.contracts }
    }
    /// Contracts you could still write against uncovered shares.
    var uncoveredContracts: Int {
        max(0, Int(shares / 100) - committedContracts)
    }

    var totalPremium: Double { legs.reduce(0) { $0 + $1.premiumTotal } }

    /// If every planned call expires worthless: keep the shares, average
    /// drops by the premium collected per share.
    var keepGain: Double { totalPremium }
    var newAverage: Double { shares > 0 ? average - totalPremium / shares : average }

    /// If every planned call is assigned: keep the premium AND realize the
    /// share gain to each strike on the called-away shares.
    var assignGain: Double {
        totalPremium + legs.reduce(0) { $0 + ($1.strike - average) * Double($1.contracts) * 100 }
    }
    var assignedShares: Int { min(Int(shares / 100), legs.reduce(0) { $0 + $1.contracts }) * 100 }

    func selectExpiry(_ e: String) {
        selectedExpiry = e
        Task { await loadLadder(e) }
    }

    func loadLadder(_ expiry: String) async {
        loading = true; loadError = nil; ladder = []
        do {
            let res = try await store.fetchOptionLadder(ticker: ticker, expiry: expiry, center: spot)
            ladder = res.strikes
        } catch {
            loadError = "Couldn't load the chain. Pull again in a moment."
        }
        loading = false
    }

    func addLeg(_ s: LadderStrike) {
        guard let e = selectedExpiry else { return }
        // Default each leg to cover the FULL position (shares ÷ 100),
        // editable via the stepper.
        let qty = max(1, Int(shares / 100))
        legs.append(PlannedLeg(expiry: e, strike: s.strike, premiumPerShare: s.premium, contracts: qty))
    }
    func setContracts(_ leg: PlannedLeg, _ n: Int) {
        guard let i = legs.firstIndex(where: { $0.id == leg.id }) else { return }
        legs[i].contracts = max(1, n)
    }
    func remove(_ leg: PlannedLeg) { legs.removeAll { $0.id == leg.id } }
}

// MARK: - Drawer

struct CoveredCallPlanner: View {
    @StateObject var model: PlannerModel
    let onClose: () -> Void

    private let lime = Color(hex: 0xD7EE53)
    private let limeInk = Color(hex: 0x1C260A)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    contextStrip
                    if !model.legs.isEmpty { planList }
                    builder
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            dock
        }
        .background(Color.theme.page)
    }

    // ── Header ──
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Plan premium").font(.system(size: 19, weight: .heavy)).tracking(-0.4)
                        .foregroundStyle(Color.theme.fg1)
                    Circle().fill(lime).frame(width: 7, height: 7)
                }
                Text("\(model.ticker) · \(fmtMoney(model.spot, decimals: 2)) · ~15-min delayed")
                    .font(.numeric(size: 11.5, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.theme.fg2)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.theme.page2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
    }

    // ── Context ──
    private var contextStrip: some View {
        HStack(spacing: 0) {
            ctxCell("SHARES", "\(Int(model.shares).formatted())", sub: "covers \(Int(model.shares / 100)) contracts")
            Rectangle().fill(Color.theme.hair).frame(width: 0.5, height: 38)
            ctxCell("AVERAGE", fmtMoney(model.average, decimals: 2), sub: "score against this")
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.theme.surface))
    }
    private func ctxCell(_ k: String, _ v: String, sub: String) -> some View {
        VStack(spacing: 6) {
            Text(k).font(.system(size: 9.5, weight: .heavy)).tracking(0.6).foregroundStyle(Color.theme.fg4)
            Text(v).font(.numeric(size: 20, weight: .heavy)).monospacedDigit().foregroundStyle(Color.theme.fg1)
            Text(sub).font(.numeric(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Color.theme.fg4)
        }
        .frame(maxWidth: .infinity)
    }

    // ── Planned legs ──
    private var planList: some View {
        VStack(spacing: 10) {
            ForEach(model.legs) { leg in
                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(weekday(leg.expiry)).font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(limeInk.opacity(0.7))
                        Text(dayNum(leg.expiry)).font(.numeric(size: 15, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(limeInk)
                    }
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12).fill(lime.opacity(0.35)))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("$\(fmtStrike(leg.strike)) call").font(.system(size: 14.5, weight: .heavy))
                            .tracking(-0.2).foregroundStyle(Color.theme.fg1)
                        Text("\(fmtMoney(leg.premiumPerShare, decimals: 2)) / sh · \(cushionLabel(leg.strike))")
                            .font(.numeric(size: 11, weight: .bold)).monospacedDigit()
                            .foregroundStyle(Color.theme.fg4)
                    }
                    Spacer(minLength: 0)

                    // contracts stepper
                    HStack(spacing: 8) {
                        stepBtn("minus") { model.setContracts(leg, leg.contracts - 1) }
                        Text("\(leg.contracts)").font(.numeric(size: 14, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Color.theme.fg1).frame(minWidth: 22)
                        stepBtn("plus") { model.setContracts(leg, leg.contracts + 1) }
                    }
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(fmtMoney(leg.premiumTotal, sign: true))
                            .font(.numeric(size: 15, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Color.theme.pos)
                        Button { model.remove(leg) } label: {
                            Image(systemName: "trash").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.theme.fg4)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.theme.surface))
            }
        }
    }
    private func stepBtn(_ icon: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: icon).font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.theme.fg2)
                .frame(width: 26, height: 26).background(Circle().fill(Color.theme.page2))
        }.buttonStyle(.plain)
    }

    // ── Builder ──
    private var builder: some View {
        VStack(alignment: .leading, spacing: 0) {
            step(1, "Pick an expiry", active: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.expiries, id: \.self) { e in
                        let on = model.selectedExpiry == e
                        Button { model.selectExpiry(e) } label: {
                            VStack(spacing: 6) {
                                Text(weekday(e)).font(.system(size: 10, weight: .heavy)).tracking(0.5)
                                    .foregroundStyle(on ? lime : Color.theme.fg4)
                                Text(dayNum(e)).font(.numeric(size: 14, weight: .heavy)).monospacedDigit()
                                    .foregroundStyle(on ? .white : Color.theme.fg1)
                                Text(monthShort(e)).font(.numeric(size: 9.5, weight: .bold)).monospacedDigit()
                                    .foregroundStyle(on ? .white.opacity(0.55) : Color.theme.fg4)
                            }
                            .frame(minWidth: 62).padding(.vertical, 11).padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 16)
                                .fill(on ? Color.theme.fg1 : Color.theme.page2))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.top, 14)

            if model.selectedExpiry != nil {
                step(2, "Pick a strike", active: true).padding(.top, 20)
                if model.loading {
                    HStack { Spacer(); ProgressView().tint(Color.theme.fg3); Spacer() }.padding(.vertical, 22)
                } else if let err = model.loadError {
                    Text(err).font(.system(size: 12.5)).foregroundStyle(Color.theme.neg).padding(.vertical, 16)
                } else {
                    strikeLadder
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.theme.surface))
    }

    private func step(_ n: Int, _ label: String, active: Bool) -> some View {
        HStack(spacing: 9) {
            Text("\(n)").font(.system(size: 11, weight: .heavy)).monospacedDigit()
                .foregroundStyle(active ? .white : Color.theme.fg4)
                .frame(width: 20, height: 20)
                .background(Circle().fill(active ? Color.theme.fg1 : Color.theme.page2))
            Text(label).font(.system(size: 13, weight: .heavy)).tracking(-0.1)
                .foregroundStyle(active ? Color.theme.fg1 : Color.theme.fg4)
        }
    }

    private var strikeLadder: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(model.ladder) { s in
                    let mny = cushionKind(s.strike)
                    Button { model.addLeg(s) } label: {
                        VStack(spacing: 5) {
                            Text(fmtStrike(s.strike)).font(.numeric(size: 15, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(Color.theme.fg1)
                            Text(fmtMoney(s.premium, decimals: 2)).font(.numeric(size: 11, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(Color.theme.pos)
                            Text(mny.0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                                .foregroundStyle(mny.1)
                        }
                        .frame(width: 58, height: 74)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(Color.theme.page2))
                        .overlay(alignment: .top) {
                            if abs(s.strike - model.spot) < 2.5 {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.theme.fg4, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.top, 12)
    }

    // ── Dock ──
    private var dock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PREMIUM YOU'D COLLECT")
                .font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(lime)
            Text(fmtMoney(model.totalPremium))
                .font(.numeric(size: 42, weight: .heavy)).tracking(-1.6).monospacedDigit()
                .foregroundStyle(.white).padding(.top, 8)

            if model.legs.isEmpty {
                Text("Pick an expiry and strike to see your outcome")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 8)
            } else {
                Text("\(model.legs.count) leg\(model.legs.count == 1 ? "" : "s") · \(model.legs.reduce(0){ $0 + $1.contracts }) contracts")
                    .font(.numeric(size: 11.5, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5)).padding(.top, 8)

                scenario("If it expires", "You keep \(Int(model.shares).formatted()) shares",
                         value: model.keepGain, valueColor: lime,
                         sub: "new avg \(fmtMoney(model.newAverage, decimals: 2))")
                    .padding(.top, 16)
                scenario("If assigned", "\(model.assignedShares.formatted()) shares called away",
                         value: model.assignGain, valueColor: Color(hex: 0xA9CBFF),
                         sub: "premium + gain to strike")

                Text("Planning only · nothing is submitted")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.3)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity).padding(.top, 14)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.theme.fg1))
        .padding(.horizontal, 14).padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func scenario(_ title: String, _ desc: String, value: Double, valueColor: Color, sub: String) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 11) {
                Circle().fill(valueColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14.5, weight: .heavy)).tracking(-0.2).foregroundStyle(.white)
                    Text(desc).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(fmtMoney(value, sign: true))
                    .font(.numeric(size: 22, weight: .heavy)).tracking(-0.4).monospacedDigit()
                    .foregroundStyle(valueColor)
                Text(sub).font(.numeric(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
    }

    // ── helpers ──
    private func cushionKind(_ strike: Double) -> (String, Color) {
        let m = model.spot > 0 ? (strike - model.spot) / model.spot * 100 : 0
        if m >= 0.8 { return ("OTM", Color.theme.pos) }
        if m <= -0.2 { return ("ITM", Color.theme.neg) }
        return ("ATM", Color.theme.warn)
    }
    private func cushionLabel(_ strike: Double) -> String {
        let m = model.spot > 0 ? (strike - model.spot) / model.spot * 100 : 0
        return "\(cushionKind(strike).0) \(m >= 0 ? "+" : "−")\(String(format: "%.1f", abs(m)))%"
    }
    private func weekday(_ iso: String) -> String { AppDates.weekdayShort(iso).uppercased() }
    private func dayNum(_ iso: String) -> String {
        guard let d = AppDates.parseISODay(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "d"; f.timeZone = TimeZone(identifier: "America/New_York")
        return f.string(from: d)
    }
    private func monthShort(_ iso: String) -> String {
        guard let d = AppDates.parseISODay(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM"; f.timeZone = TimeZone(identifier: "America/New_York")
        return f.string(from: d)
    }
}
