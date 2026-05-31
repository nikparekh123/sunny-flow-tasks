//
//  CompanyScreen.swift
//  Sunnyfi
//
//  Per-ticker detail screen, pushed from a holdings tap. Phase 4a:
//  basic layout with header + Net Delta + position grid + options legs
//  + history-derived realized P&L. Price chart, swipe-deck Net Δ/Γ
//  visualization, IV/OI sparklines, news rows — those come next.
//

import SwiftUI

struct CompanyScreen: View {
    let ticker: String
    let store: PortfolioStore

    @State private var range: ChartRange = .oneDay

    private var company: Company? {
        store.companies.first(where: { $0.ticker == ticker })
            ?? store.closedCompanies.first(where: { $0.ticker == ticker })
    }

    var body: some View {
        ScrollView {
            if let c = company {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Header(company: c)
                    RangeBarLite(active: $range)

                    // Placeholder where the price chart will live.
                    Rectangle()
                        .fill(Color.theme.cardSolid)
                        .frame(height: 132)
                        .overlay(
                            Text("Price chart — coming next")
                                .font(.ui(size: 12))
                                .foregroundStyle(Color.theme.fg3)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                    Divider().background(Color.theme.hair)

                    NetDeltaBlock(company: c)

                    Divider().background(Color.theme.hair)

                    SectionTitle("Your position")
                    PositionGrid(company: c)

                    if !c.legs.filter({ $0.kind != .stock }).isEmpty {
                        Divider().background(Color.theme.hair)
                        SectionTitle("Options")
                        OptionsLegs(legs: c.legs.filter { $0.kind != .stock })
                    }

                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else {
                ProgressView()
                    .tint(.theme.neon)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            }
        }
        .background(Color.theme.page.ignoresSafeArea())
        .navigationTitle(ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.theme.page, for: .navigationBar)
    }
}

// MARK: - Header (name + price + day change)

private struct Header: View {
    let company: Company

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(company.name)
                .font(.ui(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.theme.fg3)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                tagPill(company.sector, neon: false)
                tagPill(company.strategy.rawValue, neon: true)
                Spacer()
            }
            .padding(.top, 2)

            Text(fmtMoney(company.spot))
                .font(.numeric(size: 30, weight: .medium))
                .tracking(-1.0)
                .foregroundStyle(Color.theme.fg1)
                .padding(.top, 4)

            let absDollar = company.spot * (company.dayPct / 100)
            HStack(spacing: 6) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 9))
                    .rotationEffect(.degrees(company.dayPct >= 0 ? 0 : 180))
                    .foregroundStyle(Color.signed(company.dayPct))
                Text("\(fmtMoney(absDollar, sign: true)) (\(fmtPct(company.dayPct)))")
                    .font(.numeric(size: 13))
                    .foregroundStyle(Color.signed(company.dayPct))
                Text("Today")
                    .font(.ui(size: 12))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
    }

    @ViewBuilder
    private func tagPill(_ text: String, neon: Bool) -> some View {
        Text(text)
            .font(.ui(size: 10, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(neon ? Color.theme.neon : Color.theme.fg2)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(neon ? Color.theme.tintNeon : Color.clear)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                neon ? Color.theme.neon.opacity(0.3) : Color.theme.soft,
                                lineWidth: 1
                            )
                    )
            )
    }
}

// MARK: - Slim range bar

private struct RangeBarLite: View {
    @Binding var active: ChartRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartRange.allCases) { r in
                let isActive = active == r
                Button {
                    active = r
                } label: {
                    Text(r.rawValue)
                        .font(.numeric(size: 12))
                        .foregroundStyle(isActive ? Color.theme.neon : Color.theme.fg3)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            if isActive {
                                Capsule().fill(Color.theme.tintNeon)
                                    .overlay(Capsule().strokeBorder(Color.theme.neon.opacity(0.22), lineWidth: 1))
                            }
                        }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Boxed Net Delta metric card

private struct NetDeltaBlock: View {
    let company: Company

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NET DELTA")
                .font(.ui(size: 9.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.theme.fg2)
                .padding(.bottom, 6)
                .overlay(
                    Rectangle().fill(Color.theme.hair).frame(height: 0.5)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                )
            Text("Aggregate exposure")
                .font(.ui(size: 11.5))
                .foregroundStyle(Color.theme.fg3)
                .padding(.top, 4)
            Text(fmtGreek(company.agg.delta))
                .font(.numeric(size: 28, weight: .medium))
                .tracking(-1.0)
                .foregroundStyle(Color.theme.neon)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(Color.theme.cardSolid)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .strokeBorder(Color.theme.hair, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Section title

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.ui(size: 18, weight: .bold))
            .foregroundStyle(Color.theme.fg1)
            .padding(.top, 4)
    }
}

// MARK: - Position 2-col grid

private struct PositionGrid: View {
    let company: Company

    private var stock: Leg? { company.legs.first(where: { $0.kind == .stock }) }

    var body: some View {
        let s = stock
        let shares = s?.qty ?? 0
        let mv = company.agg.mv
        let avg = s?.avg ?? 0

        let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        LazyVGrid(columns: cols, spacing: 16) {
            cell("Shares", "\(Int(shares))")
            cell("Market value", fmtMoney(mv))
            cell("Average cost", fmtMoney(avg))
            cell("β", String(format: "%.2f", company.beta))
            cell("Today's return",
                 fmtMoney((s?.last ?? 0) * (company.dayPct / 100) * shares, sign: true),
                 tone: Color.signed(company.dayPct))
            cell("Open P&L",
                 fmtMoney(company.agg.unreal, sign: true),
                 tone: Color.signed(company.agg.unreal))
        }
    }

    @ViewBuilder
    private func cell(_ label: String, _ value: String, tone: Color = .theme.fg1) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.ui(size: 11))
                .foregroundStyle(Color.theme.fg3)
            Text(value)
                .font(.numeric(size: 16, weight: .medium))
                .foregroundStyle(tone)
        }
    }
}

// MARK: - Options legs list

private struct OptionsLegs: View {
    let legs: [Leg]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(legs) { leg in
                HStack(alignment: .center, spacing: 12) {
                    glyph(for: leg)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strikeLabel(leg))
                            .font(.numeric(size: 13.5))
                            .foregroundStyle(Color.theme.fg1)
                        Text(subline(leg))
                            .font(.numeric(size: 10.5))
                            .foregroundStyle(Color.theme.fg3)
                        Text(greekLine(leg))
                            .font(.numeric(size: 10.5))
                            .foregroundStyle(Color.theme.fg3)
                    }
                    Spacer()
                    Text(fmtMoney(leg.unreal, sign: true))
                        .font(.numeric(size: 13.5))
                        .foregroundStyle(Color.signed(leg.unreal))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                Rectangle().fill(Color.theme.hair).frame(height: 0.5)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(Color.theme.hair, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private func glyph(for leg: Leg) -> some View {
        let isPut = leg.kind == .put
        return Text(isPut ? "P" : "C")
            .font(.numeric(size: 12, weight: .bold))
            .foregroundStyle(isPut ? Color.theme.neg : Color.theme.pos)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isPut ? Color.theme.tintNeg : Color.theme.tintPos)
            )
    }

    private func strikeLabel(_ leg: Leg) -> String {
        let strike = leg.strike.map { "$\(Int($0))" } ?? "—"
        return "\(strike) \(leg.kind == .call ? "call" : "put")"
    }

    private func subline(_ leg: Leg) -> String {
        let side = leg.side == .short ? "short" : "long"
        let qty = Int(abs(leg.qty))
        let exp = leg.expiry ?? "—"
        return "\(side) · ×\(qty) · exp \(exp)"
    }

    private func greekLine(_ leg: Leg) -> String {
        "Δ \(fmtGreek(leg.delta)) · Θ \(fmtGreek(leg.theta))"
    }
}
