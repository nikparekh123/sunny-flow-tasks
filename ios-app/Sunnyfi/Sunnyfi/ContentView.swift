//
//  ContentView.swift
//  Sunnyfi
//
//  Hello Portfolio — Phase 3 smoke test. Pulls real positions + Greeks
//  from Supabase via PortfolioStore and renders the 6 portfolio-level
//  Greeks + one row per ticker. This is NOT the final design — the
//  Home + Company screens land in Phase 4 against the design handoff.
//

import SwiftUI

struct ContentView: View {
    @State private var store = PortfolioStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: []) {
                    if store.isLoading && store.companies.isEmpty {
                        ProgressView()
                            .tint(.theme.neon)
                            .padding(.top, 80)
                    } else {
                        GreeksHero(p: store.portfolio)
                        SubHeader(store: store)
                        ForEach(store.companies) { c in
                            CompanyRow(company: c)
                        }
                        if let err = store.error {
                            Text(err)
                                .font(.ui(size: 12))
                                .foregroundStyle(Color.theme.neg)
                                .padding(.top, 12)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Color.theme.page)
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.theme.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .refreshable { await store.refresh() }
        }
        .preferredColorScheme(.dark)
        .task { await store.load() }
    }
}

// MARK: - Greeks hero (6-cell grid)

private struct GreeksHero: View {
    let p: PortfolioRollup

    private var cells: [(label: String, value: String, tone: Color)] {
        [
            ("Net Δ",   fmtGreek(p.delta),             .theme.fg1),
            ("β·Δ",    fmtGreek(p.betaWeightedDelta), .theme.fg1),
            ("Θ",      fmtGreek(p.theta),              p.theta >= 0 ? .theme.pos : .theme.neg),
            ("V",      fmtGreek(p.vega),               .theme.fg1),
            ("Γ",      fmtGreek(p.gamma),              .theme.fg1),
            ("Open P&L", fmtK(p.unreal),               p.unreal >= 0 ? .theme.pos : .theme.neg),
        ]
    }

    var body: some View {
        let cols = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(cells, id: \.label) { cell in
                VStack(alignment: .leading, spacing: 4) {
                    Text(cell.label.uppercased())
                        .font(.ui(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color.theme.fg3)
                    Text(cell.value)
                        .font(.numeric(size: 18, weight: .semibold))
                        .foregroundStyle(cell.tone)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
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
    }
}

private struct SubHeader: View {
    let store: PortfolioStore

    var body: some View {
        HStack {
            Text("\(store.companies.count) open · \(store.closedCompanies.count) closed")
                .font(.ui(size: 12))
                .foregroundStyle(Color.theme.fg3)
            Spacer()
            if let f = store.freshness {
                Text("updated \(timeString(f))")
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompanyRow: View {
    let company: Company

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(company.ticker)
                    .font(.ui(size: 16, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
                Text("\(company.strategy.rawValue) · β \(String(format: "%.2f", company.beta))")
                    .font(.ui(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(fmtK(company.agg.net))
                    .font(.numeric(size: 15))
                    .foregroundStyle(Color.signed(company.agg.net))
                Text("Δ \(fmtGreek(company.agg.delta))")
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(Color.theme.hair)
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
    }
}

// MARK: - Formatters
// Ports of fmtGreek / fmtK from src/portfolio/data.ts.

private func fmtGreek(_ v: Double) -> String {
    let sign = v > 0 ? "+" : v < 0 ? "−" : ""
    return sign + abs(v).rounded().formatted(.number.grouping(.automatic))
}

private func fmtK(_ v: Double) -> String {
    let sign = v < 0 ? "−" : "+"
    let a = abs(v)
    if a >= 1000 {
        let scaled = a / 1000
        let digits = a >= 10_000 ? 0 : 1
        return "\(sign)$\(String(format: "%.\(digits)f", scaled))k"
    }
    return "\(sign)$\(Int(a.rounded()).formatted(.number.grouping(.automatic)))"
}

private func timeString(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f.string(from: d)
}

#Preview {
    ContentView()
}
