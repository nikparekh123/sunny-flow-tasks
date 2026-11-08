//
//  AXDump.swift
//  Sunny
//
//  DEBUG simulator audits only (Audit 6): `-axdump <file> [-axdelay 8]` writes what VoiceOver would read on the
//  screen after the delay: one JSON line per element, in reading order, with its label, value, hint, traits and
//  frame. Lets the audit check every control has a label and a value without a phone. Cannot reach a device build.
//

import SwiftUI
import UIKit

enum AXDump {
    @MainActor
    static func runIfAsked() async {
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-axdump"), i + 1 < a.count else { return }
        let path = a[i + 1]
        let delay = a.firstIndex(of: "-axdelay").flatMap { $0 + 1 < a.count ? Double(a[$0 + 1]) : nil } ?? 8
        // SwiftUI builds its accessibility tree only for an assistive client: switch on automation as KIF does.
        if let h = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), let f = dlsym(h, "_AXSSetAutomationEnabled") {
            typealias Set = @convention(c) (Int32) -> Void
            unsafeBitCast(f, to: Set.self)(1)
        }
        try? await Task.sleep(for: .seconds(delay))
        guard let win = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        var lines: [String] = []
        var seen = Set<ObjectIdentifier>()
        // VoiceOver reads a presented sheet, not the page under it: start from the top-most presented controller.
        var top = win.rootViewController
        while let p = top?.presentedViewController { top = p }
        if let v = top?.view, top !== win.rootViewController { visit(v, depth: 0, into: &lines, seen: &seen) }
        else { visit(win, depth: 0, into: &lines, seen: &seen) }
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    @MainActor
    private static func visit(_ o: NSObject, depth: Int, into lines: inout [String], seen: inout Set<ObjectIdentifier>) {
        guard depth < 60, seen.insert(ObjectIdentifier(o)).inserted else { return }
        if let v = o as? UIView, v.isHidden || v.alpha < 0.01 { return }
        if o.accessibilityElementsHidden { return }
        if o.isAccessibilityElement {
            let f = o.accessibilityFrame
            let row: [String: Any] = [
                "label": o.accessibilityLabel ?? "", "value": o.accessibilityValue ?? "", "hint": o.accessibilityHint ?? "",
                "traits": traitNames(o.accessibilityTraits), "frame": [Int(f.minX), Int(f.minY), Int(f.width), Int(f.height)],
                "actions": (o.accessibilityCustomActions ?? []).map(\.name),
            ]
            if let d = try? JSONSerialization.data(withJSONObject: row), let s = String(data: d, encoding: .utf8) { lines.append(s) }
            return
        }
        if let els = o.accessibilityElements as? [NSObject], !els.isEmpty {
            for e in els { visit(e, depth: depth + 1, into: &lines, seen: &seen) }
            return
        }
        let n = o.accessibilityElementCount()
        if n != NSNotFound && n > 0 {
            for k in 0..<n { if let e = o.accessibilityElement(at: k) as? NSObject { visit(e, depth: depth + 1, into: &lines, seen: &seen) } }
            return
        }
        if let v = o as? UIView { for s in v.subviews { visit(s, depth: depth + 1, into: &lines, seen: &seen) } }
    }

    private static func traitNames(_ t: UIAccessibilityTraits) -> [String] {
        let all: [(UIAccessibilityTraits, String)] = [(.button, "button"), (.link, "link"), (.header, "header"), (.selected, "selected"),
            (.adjustable, "adjustable"), (.image, "image"), (.staticText, "text"), (.tabBar, "tabBar"), (.notEnabled, "disabled"),
            (.updatesFrequently, "updates"), (.searchField, "search"), (.summaryElement, "summary"), (.allowsDirectInteraction, "direct"),
            (.toggleButton, "toggle"), (.causesPageTurn, "pageTurn"), (.keyboardKey, "key"), (.playsSound, "sound"), (.startsMediaSession, "media")]
        return all.filter { t.contains($0.0) }.map(\.1)
    }
    #endif
}
