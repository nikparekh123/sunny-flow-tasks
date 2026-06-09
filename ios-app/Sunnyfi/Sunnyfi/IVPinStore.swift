//
//  IVPinStore.swift
//  Sunnyfi
//
//  Local per-ticker IV pin set. Separate from TodayPinStore (which
//  holds event/portfolio/options pins) — IV pins live in their own
//  rail above the headline, not in the regular Pinned cards rail.
//
//  Stored as JSON array of ticker strings under
//  UserDefaults['sunny.ivPins.v1'] — matches the React prototype's
//  `sunny_iv_tracked` key conceptually, prefixed for namespacing.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class IVPinStore {
    static let shared = IVPinStore()
    private let key = "sunny.ivPins.v1"

    private(set) var pinnedTickers: [String] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            pinnedTickers = arr
        }
    }

    func isPinned(_ ticker: String) -> Bool {
        pinnedTickers.contains(ticker.uppercased())
    }

    func toggle(_ ticker: String) {
        let t = ticker.uppercased()
        if let idx = pinnedTickers.firstIndex(of: t) {
            pinnedTickers.remove(at: idx)
        } else {
            pinnedTickers.append(t)
        }
        persist()
    }

    func unpin(_ ticker: String) {
        pinnedTickers.removeAll { $0 == ticker.uppercased() }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pinnedTickers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
