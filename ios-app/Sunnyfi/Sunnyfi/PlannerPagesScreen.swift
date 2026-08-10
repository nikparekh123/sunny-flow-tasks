//
//  PlannerPagesScreen.swift
//  The container: fetches once, holds the commit, hosts the six pages.
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
    @State private var decodeError: String?
    /// The week being planned. Nil = the nearest live one, which is the default
    /// and what the planner has always done. Setting it re-plans: the strikes,
    /// the sizing and the whole rail are per-expiry, so this cannot be a filter
    /// applied to a plan already computed.
    @State private var expiry: String?
    @State private var replanning = false
    @State private var commit: PPCommit? = PPCommitStore.load()
    @State private var index = 0
    @State private var grade = PlannerDials.shared.grade ?? 5

    private var spot: Double { store.position?.spot ?? 0 }

    /// Page 05 exists only when there is a position to run, and only when that
    /// position belongs to the expiry being planned. A commit left over from a
    /// closed week is history, not something to monitor.
    private var liveCommit: PPCommit? {
        // Match against ANY chain being planned, not just the first. A sale written
        // on the second expiry is every bit as live as one on the nearest, and
        // checking only plan.expiry would have hidden the monitoring page for it.
        guard let c = commit,
              (parsed?.plan?.chains ?? []).contains(where: { $0.expiry == c.expiry })
        else { return nil }
        return c
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let r = parsed {
                PPStack(count: liveCommit == nil ? 5 : 6, index: $index) {
                    PPConvictionPage(r: r,
                        toGrade: { withAnimation { index = liveCommit == nil ? 4 : 5 } }).pp_page(0)
                    PPWeekPage(r: r).pp_page(1)
                    PPFloorPage(r: r).pp_page(2)
                    PPSellPage(r: r, spot: spot, commit: commit) { c in
                        commit = c; PPCommitStore.save(c)
                        // Straight to the position it just created — the confirm is
                        // not finished until you can see what is running.
                        withAnimation { index = 4 }
                        // And to the server, so the nightly scorer resolves it when
                        // the expiry passes. All three picks are archived, not just
                        // this one: scoring only the taken pick measures which way
                        // NVDA went, which the tool does not control. Storing all
                        // three measures whether the RANKING was any good.
                        Task {
                            // BOTH indices. The edge is 1-based within a chain, and
                            // without the chain the record would name the same tier
                            // in the wrong week — the identical class of error as
                            // committing by rail position.
                            await plan.commit(c.engineIndex.map { $0 + 1 },
                                              chainIndex: c.chainIndex ?? 0,
                                              store: store, ticker: ticker)
                        }
                    }.pp_page(3)
                    if let c = liveCommit {
                        PPMonitorPage(r: r, spot: spot, commit: c) {
                            commit = nil; PPCommitStore.save(nil)
                            withAnimation { index = 3 }
                        }.pp_page(4)
                    }
                    PPGradePage(r: r, grade: $grade).pp_page(liveCommit == nil ? 4 : 5)
                }
            } else {
                PP.background(.ink).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 10) {
                    PPKicker(text: (plan.lastError ?? decodeError) == nil
                             ? "reading the week" : "planner unavailable", ground: .ink)
                    if let e = plan.lastError ?? decodeError {
                        Text(e).font(PP.disp(13)).foregroundStyle(PP.dim(.ink))
                    }
                }
                .padding(PP.pagePadX).padding(.top, PP.pagePadTop)
            }

            if let e = plan.commitError {
                Text("not recorded — \(e)")
                    .font(PP.mono(10)).tracking(10 * 0.1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(PP.lossHue.opacity(0.9), in: Capsule())
                    .padding(.leading, PP.pagePadX)
                    .padding(.top, 46)
                    .safeAreaPadding(.top)
            }

        }
        // Swipe horizontally to leave. The deck pages VERTICALLY, so the
        // horizontal axis is free and costs no chrome — which is the point:
        // the close button sat in the same corner every page puts its kicker,
        // and a control that fights the content is worse than a gesture.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { g in
                    guard abs(g.translation.width) > 80,
                          abs(g.translation.width) > abs(g.translation.height) * 1.5
                    else { return }
                    onBack()
                }
        )
        .task {
            await plan.load(from: store, ticker: ticker, expiry: expiry)
            decode()
        }
        .onChange(of: expiry) { _, new in
            Task {
                replanning = true
                await plan.load(from: store, ticker: ticker, expiry: new)
                decode()
                replanning = false
            }
        }
        .onChange(of: grade) { _, new in PlannerDials.shared.grade = new }
    }

    /// Every week that can actually be written, newest request's answer first.
    /// Empty until the first response — the picker has nothing real to offer
    /// before then and should not invent dates from a calendar.
    var expiryOptions: [String] { parsed?.plan?.expiryOptions ?? [] }

    /// True when a chosen week was rejected and the nearest priced instead. The
    /// UI must surface this rather than showing the requested date: the whole
    /// rail belongs to the expiry the ENGINE used.
    var expiryFellBack: Bool { parsed?.plan?.expiryHonoured == false }

    /// Decoding is deliberately non-fatal. A response the app cannot parse leaves
    /// the loading state up with the error visible — never a half-drawn deck of
    /// pages showing zeroes for everything it failed to read.
    private func decode() {
        guard let raw = plan.lastRaw else { decodeError = "no response body"; return }
        do { parsed = try JSONDecoder().decode(PPResponse.self, from: raw); decodeError = nil }
        // Named, not swallowed. A silent `try?` here is what turned one wrong
        // field type into a screen that read "reading the week" forever, with
        // nothing anywhere saying why.
        catch { decodeError = String(describing: error).prefix(400).description }
    }
}
