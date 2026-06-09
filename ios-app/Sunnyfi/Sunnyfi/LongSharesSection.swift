//
//  LongSharesSection.swift
//  Sunnyfi
//
//  Section that lists every ticker with a long-share position as a
//  SharesCardView. Sits above "Current positions" on the Trades tab —
//  same cards also appear inside the per-ticker modal's Shares tab so
//  there's one consistent representation across the app.
//

import SwiftUI

struct LongSharesSection: View {
    let store: PortfolioStore
    let onBuy: (String) -> Void          // ticker
    let onSell: (String) -> Void
    let onShowLots: (String) -> Void     // ticker
    /// Single planner focus binding from the parent — needed so all
    /// SharesCardView TextFields share one keyboard toolbar (otherwise
    /// each card stacks its own Done button).
    @FocusState.Binding var sharedFocus: String?

    /// Tickers we hold shares in, sorted by current market value descending.
    private var tickers: [String] {
        store.companies
            .compactMap { c -> (String, Double)? in
                guard let stock = c.legs.first(where: { $0.kind == .stock }), stock.qty > 0 else { return nil }
                return (c.ticker, stock.qty * c.spot)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        if tickers.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Long shares")
                        .font(.ui(size: 18, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Spacer()
                    Text("\(tickers.count) ticker\(tickers.count == 1 ? "" : "s")")
                        .font(.numeric(size: 12))
                        .foregroundStyle(Color.theme.fg3)
                }
                VStack(spacing: 12) {
                    ForEach(tickers, id: \.self) { tk in
                        SharesCardView(
                            ticker: tk,
                            store: store,
                            onBuy:  { onBuy(tk) },
                            onSell: { onSell(tk) },
                            onShowLots: { onShowLots(tk) },
                            sharedFocus: $sharedFocus
                        )
                    }
                }
            }
        }
    }
}
