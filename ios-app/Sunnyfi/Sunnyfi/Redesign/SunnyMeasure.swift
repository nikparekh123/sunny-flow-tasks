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

// MARK: - font audit
//
// SPEC 08 and DIGEST-CARD §2 give an exact size and weight per element. Asserting
// they look right is not evidence, so this resolves each font the way the card
// builds it and prints what UIKit actually produced, including the weight axis a
// variable font ended up on.

import UIKit

enum SunnyFontAudit {
    /// ⚠ THE AUDIT MUST CALL THE CARD'S OWN FUNCTIONS. The first version of
    /// this built each font by hand with the right numbers and then checked its
    /// own arithmetic, so it reported OK while the card was rendering body text
    /// at 400: S.wBody is .regular, and InkFont maps .regular to 400, not 450.
    /// A test that cannot fail is not a test.
    private static func rows() -> [(String, CGFloat, CGFloat, UIFont?)] {
        [
            ("timestamp Kalam", 13.5, 300, UIFont(name: "Kalam-Light", size: S.tHandMeta)),
            ("ticker Caveat",   28,   700, S.handUI(S.tHandTitle, 700)),
            ("spot Inter",      25,   600, S.interUI(S.tPaperSpot, S.wSemiN)),
            ("chip Caveat",     18,   600, S.handUI(S.tPaperChip, 600)),
            ("heading Caveat",  22,   700, S.handUI(S.tHandHead, 700)),
            ("body Inter",      16,   450, S.interUI(S.tPaperBody, S.wBodyN)),
            ("tag Caveat",      22,   700, S.handUI(S.tHandTag, 700)),
            ("do instr Inter",  18,   600, S.interUI(18, S.wSemiN)),
            ("do reason Inter", 14,   450, S.interUI(14, S.wBodyN)),
        ]
    }

    static func dump() {
        guard SunnyMeasure.on else { return }
        print("FONTAUDIT ---- element | want | got size | got wght | family")
        for (label, wantSize, wantW, f) in rows() {
            guard let f else { print("FONTAUDIT \(label) | MISSING FONT"); continue }
            let vars = f.fontDescriptor.object(forKey:
                UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute")) as? [Int: CGFloat]
            let gotW = vars?[0x77676874]
            let sizeOK = abs(f.pointSize - wantSize) < 0.01
            let wOK = gotW == nil ? true : abs((gotW ?? 0) - wantW) < 0.01
            print(String(format: "FONTAUDIT %-16@ | %5.1f/%3.0f | %6.2f | %@ | %@ | %@",
                         label as NSString, wantSize, wantW, f.pointSize,
                         gotW.map { String(format: "%.0f", $0) } ?? "static",
                         f.familyName,
                         (sizeOK && wOK) ? "OK" : "MISMATCH"))
        }
    }

    /// ⚠ CSS line-height is the TOTAL line advance. SwiftUI's .lineSpacing is
    /// the EXTRA space added between lines, on top of the font's own natural
    /// line height. Passing (size x multiple) straight in overshoots by the
    /// whole natural height, which is what the card is currently doing.
    static func leading() {
        guard SunnyMeasure.on else { return }
        for (label, size, mult) in [("body", S.tPaperBody, S.lhPaperBody),
                                    ("do reason", CGFloat(14), 1.45),
                                    ("do instr", CGFloat(18), 1.25)] {
            guard let f = S.interUI(size, label == "do instr" ? S.wSemiN : S.wBodyN) else { continue }
            let want = size * mult
            print(String(format: "LEADING %-10@ size %.1f  want %.2f  natural %.2f  correct lineSpacing %.2f  card passes %.2f",
                         label as NSString, size, want, f.lineHeight,
                         want - f.lineHeight, size * (mult - 1)))
        }
    }
}
