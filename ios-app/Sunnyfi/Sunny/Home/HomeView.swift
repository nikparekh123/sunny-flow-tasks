//
//  HomeView.swift
//  Sunny
//
//  The one Home page, in Home order: status, account and its chart, the
//  deck, then Book · Risk · Income · Results. 20 pt margins, the screen
//  gradient under everything, live every 30 s while a session runs.
//

import SwiftUI

struct HomeView: View {
    let store: HomeStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            S.screen.ignoresSafeArea()
            if let home = store.home {
                page(home)
            } else if store.loadError != nil {
                HomeUnavailable(store: store)
            } else {
                SunriseLoading()
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.live()
        }
    }

    private func page(_ home: HomePayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusLine(store: store)
                    .padding(.horizontal, S.margin)
                    .padding(.top, 4)
                AccountChart(home: home)
                    .padding(.top, 14)
                    .sEnter(0)
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
    }
}

/// No good update yet and the fetch failed: say so plainly, offer a retry.
struct HomeUnavailable: View {
    let store: HomeStore
    var body: some View {
        VStack(spacing: 14) {
            Text("Can't reach Sunny").sType(.headline, tabular: false).foregroundStyle(S.ink)
            Text("Check the connection and try again.").sType(.body, tabular: false).foregroundStyle(S.muted)
            Button { Task { await store.refresh() } } label: {
                Text("Try again").sType(.label, tabular: false).foregroundStyle(S.ink)
                    .padding(.horizontal, 18).frame(height: 36)
                    .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(SPressStyle())
        }
        .padding(S.margin)
    }
}
