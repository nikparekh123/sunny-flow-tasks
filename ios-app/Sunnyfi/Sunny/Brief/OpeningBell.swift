//
//  OpeningBell.swift
//  Sunny
//
//  The opening bell (block 29, handoff 6 Nov 2026, Pass 5): at 9:30:00 New York on a trading day, if the app is
//  open and the setting is on, one electric bell of about 4 s that follows the silent switch (an ambient session,
//  mixed with whatever is playing). The sound is Sounds/OpeningBell.caf, rendered by tools/make_bell.py from the
//  design's own recipe: a clapper 18 times a second on four inharmonic partials of 840 Hz for 2.4 s, then the ring
//  dies away over 1.8 s. Pinning The bell in the debug menu rings it too, as the prototype does on that moment.
//

import AVFoundation
import SwiftUI

@MainActor
enum OpeningBell {
    /// On unless turned off (the design's bellSound defaults to true).
    static let key = "sunny.openingBell"
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    private static var player: AVAudioPlayer?
    private static var rang: Date?

    /// Rings now (the setting permitting). Never over a voice question in Search, which holds the microphone.
    static func ring() {
        guard isOn, let url = Bundle.main.url(forResource: "OpeningBell", withExtension: "caf") else { return }
        let s = AVAudioSession.sharedInstance()
        guard s.category != .playAndRecord else { return }
        try? s.setCategory(.ambient, options: [.mixWithOthers])
        try? s.setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    /// Rings for this open once, and only within 5 s of it (a scene that wakes at 9:31 stays quiet).
    static func ring(for open: Date) {
        guard rang != open, abs(open.timeIntervalSinceNow) < 5 else { return }
        rang = open
        ring()
    }

    /// The next 9:30:00 New York open after `date` on a trading day of the saved exchange calendar.
    nonisolated static func nextOpen(after date: Date, calendar cal: [CalendarDay]) -> Date? {
        var c = Calendar(identifier: .gregorian); c.timeZone = MarketClock.ny
        for k in 0..<10 {
            guard let day = c.date(byAdding: .day, value: k, to: date),
                  let open = c.date(bySettingHour: 9, minute: 30, second: 0, of: day), open > date else { continue }
            let t = MarketClock.ny(open)
            if MarketClock.isTradingDay(t.date, weekday: t.weekday, cal) { return open }
        }
        return nil
    }
}

/// Waits for the next open while the app is in front, rings, then waits for the one after. Leaving the app cancels
/// the wait; coming back works it out again from the clock.
struct OpeningBellClock: ViewModifier {
    @Environment(\.scenePhase) private var phase
    let calendar: [CalendarDay]

    func body(content: Content) -> some View {
        content.task(id: "\(phase == .active)·\(calendar.count)") {
            guard phase == .active else { return }
            while !Task.isCancelled {
                guard let open = OpeningBell.nextOpen(after: Date().addingTimeInterval(-5), calendar: calendar) else { return }
                let wait = open.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                OpeningBell.ring(for: open)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}

extension View {
    func openingBell(calendar: [CalendarDay]) -> some View { modifier(OpeningBellClock(calendar: calendar)) }
}
