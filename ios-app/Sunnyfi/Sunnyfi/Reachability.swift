//
//  Reachability.swift
//  Sunnyfi
//
//  Network reachability via NWPathMonitor. Drives the offline
//  banner — clear "you're offline, last data Xm ago" state so the
//  user never sees ambiguously-stale numbers.
//

import Foundation
import Network
import SwiftUI

@MainActor
@Observable
final class Reachability {
    var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Reachability")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }
}
