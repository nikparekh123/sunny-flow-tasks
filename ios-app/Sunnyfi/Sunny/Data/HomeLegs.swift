//
//  HomeLegs.swift
//  Sunny
//
//  The open legs in the Home payload (`legs`), one row per strike, side and
//  expiry, marked by mp-refresh every minute.
//

import Foundation

struct Leg: Decodable, Identifiable, Hashable {
    var id: String { "\(ticker)|\(type)|\(side)|\(strike)|\(expiry)" }
    let ticker: String
    let type: String          // call | put
    let side: String          // sold | bought
    let strike: Double
    let expiry: String        // yyyy-MM-dd
    let n: Int
    let avg: Double           // premium per share, opened or paid
    let mark: Double?
    let iv: Double?
    let delta: Double?
    let theta: Double?
    let underlying: Double?
    let opened: String?
    /// The mark at the close before the Chart cards' first session (the week shown).
    let markWk: Double?
    /// A hedge call: the quarterly calls bought under the call rule, apart from the LEAPs (handoff 30).
    let up: Bool?
}
