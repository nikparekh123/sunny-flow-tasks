//
//  PortfolioSnapshot.swift
//  Sunnyfi
//
//  Cold-launch cache. After every successful fetchAll(), the store
//  writes a JSON snapshot of the raw rows to Application Support;
//  on the next launch we load it synchronously *before* the 13-query
//  Supabase fan-out resolves and run the same buildCompanies +
//  buildPortfolio join to populate the UI immediately.
//
//  Why raw rows instead of Company/PortfolioRollup:
//    Leg uses `let id = UUID()` which doesn't round-trip cleanly
//    through Codable. Caching raws + re-running the (16 ms) CPU
//    join is simpler than custom Codable on the joined shapes.
//
//  Failure mode:
//    A corrupt or schema-mismatched snapshot is silently ignored
//    (try? throws). The app behaves exactly as it did before the
//    cache — staring at empty state until fetchAll lands.
//
//  Disk path:
//    Application Support/Sunnyfi/portfolio-snapshot.v1.json
//    Application Support is excluded from iCloud backups for
//    transient cache files — fine, regenerated on every fetch.
//

import Foundation

struct PortfolioSnapshot: Codable {
    /// Bump when the field shape changes. Older snapshots are
    /// rejected on decode rather than crashing.
    static let currentVersion: Int = 1

    var version: Int = Self.currentVersion
    var savedAt: Date
    var freshness: Date?

    // Raw rows — same shapes the live store keeps.
    var positions: [PositionRow]
    var trades: [OptionTradeRow]
    var greeks: [OptionGreeksRow]
    var quotes: [TickerQuoteRow]
    var sells: [ShareSellRow]
    var overlay: [StrategyOverlayRow]
    var closes: [DailyCloseRow]
    var lots: [ShareLotRow]
    var theta: [DailyThetaSnapshotRow]
    var macroEvents: [MacroEventRow]
    var earningsEvents: [EarningsEventRow]
    var ivSummaries: [TickerIVRow]
}

enum PortfolioSnapshotStore {

    private static let filename = "portfolio-snapshot.v1.json"

    /// Disk URL under Application Support/Sunnyfi/.
    /// Created on demand on first save.
    private static var fileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("Sunnyfi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    /// Synchronously read the snapshot from disk. Called once on
    /// PortfolioStore init — small file (<1 MB typical), JSON decode
    /// is fast enough to do inline on the main thread.
    static func read() -> PortfolioSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(PortfolioSnapshot.self, from: data),
              snap.version == PortfolioSnapshot.currentVersion
        else { return nil }
        return snap
    }

    /// Write asynchronously off the main actor. Fire-and-forget;
    /// failure to persist isn't worth surfacing — next fetchAll will
    /// try again.
    static func write(_ snapshot: PortfolioSnapshot) {
        // Detached task — encoding + disk write off main.
        Task.detached(priority: .utility) {
            guard let url = fileURL else { return }
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic])
            } catch {
                // Silent. The cache is best-effort.
            }
        }
    }

    /// Remove the snapshot. Used on sign-out so a different user's
    /// data isn't sitting on disk at the next launch.
    static func clear() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }
}
