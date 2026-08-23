//
//  SunnyMeasure.swift
//  Sunny — SPEC 11 says measure, do not eyeball. This is how.
//
//  The web handoff measures with getBoundingClientRect(). The equivalent here is
//  onGeometryChange, printed to stdout and read back with
//  `xcrun simctl launch --console`. Enabled only by a launch argument, so it
//  costs nothing in a normal run.
//

import SwiftUI

enum SunnyMeasure {
    static let on = ProcessInfo.processInfo.arguments.contains("-measure")
    static func log(_ label: String, _ size: CGSize) {
        guard on else { return }
        print(String(format: "MEASURE %-22@ %8.2f x %8.2f", label as NSString, size.width, size.height))
    }
    static func log(_ label: String, _ rect: CGRect) {
        guard on else { return }
        print(String(format: "MEASURE %-22@ %8.2f x %8.2f   at x=%.2f y=%.2f",
                     label as NSString, rect.width, rect.height, rect.minX, rect.minY))
    }
}

extension View {
    func measure(_ label: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
            SunnyMeasure.log(label, r)
        }
    }
}
