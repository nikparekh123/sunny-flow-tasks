//
//  PlannerPagesScreen.swift
//  The container: fetches once, holds the commit, hosts the seven pages.
//
//  It decodes the SAME bytes PlanV2Store keeps for the commit echo, rather than
//  issuing its own request. Two calls would mean the pages could show one plan
//  while the committed record archived another — and the record has to be what
//  the engine actually said on screen.
//

import SwiftUI

/// The sale is the only thing in the planner the user CREATES, so it is the only
/// thing that survives a relaunch. Local for now, keyed by expiry so a new week
/// does not inherit last week's position; planner_commits is the server record.
private enum PPCommitStore {
    private static let key = "nvda-planner-pages-commit-v1"
    static func load() -> PPCommit? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PPCommit.self, from: d)
    }
    static func save(_ c: PPCommit?) {
        guard let c, let d = try? JSONEncoder().encode(c) else {
            UserDefaults.standard.removeObject(forKey: key); return
        }
        UserDefaults.standard.set(d, forKey: key)
    }
}

struct PlannerPagesScreen: View {
    let store: NvdaStore
    var ticker: String = "NVDA"
    var onBack: () -> Void

    @State private var plan = PlanV2Store()
    @State private var parsed: PPResponse?
    @State private var commit: PPCommit? = PPCommitStore.load()
    @State private var index = 0
    @State private var grade = PlannerDials.shared.grade ?? 5

    private var spot: Double { store.position?.spot ?? 0 }

    /// Page 05 exists only when there is a position to run, and only when that
    /// position belongs to the expiry being planned. A commit left over from a
    /// closed week is history, not something to monitor.
    private var liveCommit: PPCommit? {
        guard let c = commit, let e = parsed?.plan?.expiry, c.expiry == e else { return nil }
        return c
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let r = parsed {
                PPStack(count: liveCommit == nil ? 6 : 7, index: $index) {
                    PPConvictionPage(r: r).tag(0)
                    PPDecisionPage(r: r, toGrade: { withAnimation { index = liveCommit == nil ? 5 : 6 } }).tag(1)
                    PPWeekPage(r: r).tag(2)
                    PPFloorPage(r: r).tag(3)
                    PPSellPage(r: r, spot: spot, commit: commit) { c in
                        commit = c; PPCommitStore.save(c)
                        // Straight to the position it just created — the confirm is
                        // not finished until you can see what is running.
                        withAnimation { index = 5 }
                    }.tag(4)
                    if let c = liveCommit {
                        PPMonitorPage(r: r, spot: spot, commit: c) {
                            commit = nil; PPCommitStore.save(nil)
                            withAnimation { index = 4 }
                        }.tag(5)
                    }
                    PPGradePage(r: r, grade: $grade).tag(liveCommit == nil ? 5 : 6)
                }
            } else {
                PP.background(.ink).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 10) {
                    PPKicker(text: plan.lastError == nil ? "reading the week" : "planner unavailable",
                             ground: .ink)
                    if let e = plan.lastError {
                        Text(e).font(PP.disp(13)).foregroundStyle(PP.dim(.ink))
                    }
                }
                .padding(PP.pagePadX).padding(.top, PP.pagePadTop)
            }

            Button(action: onBack) {
                Text("close".uppercased())
                    .font(PP.mono(11)).tracking(11 * 0.14)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .foregroundStyle(.white)
            .blendMode(.difference)          // one control, both grounds
            .padding(.leading, PP.pagePadX - 14)
            .padding(.top, 14)
        }
        .task {
            await plan.load(from: store, ticker: ticker)
            decode()
        }
        .onChange(of: grade) { _, new in PlannerDials.shared.grade = new }
    }

    /// Decoding is deliberately non-fatal. A response the app cannot parse leaves
    /// the loading state up with the error visible — never a half-drawn deck of
    /// pages showing zeroes for everything it failed to read.
    private func decode() {
        guard let raw = plan.lastRaw else { return }
        parsed = try? JSONDecoder().decode(PPResponse.self, from: raw)
    }
}
