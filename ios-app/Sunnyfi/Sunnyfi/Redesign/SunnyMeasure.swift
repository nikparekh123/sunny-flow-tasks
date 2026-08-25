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
    /* ⚠ AND A STATIC FONT NEEDS ITS FAMILY CHECKED, NOT ITS AXIS. The weight test
       reads NSCTFontVariationAttribute, which a static face does not carry — so
       for Patrick Hand it passes unconditionally, and the row could report OK
       while UIFont(name:) returned nil and the card silently rendered in the
       system face. The expected family is the fourth column for exactly that. */
    private static func rows() -> [(String, CGFloat, CGFloat, String, UIFont?)] {
        [
            // Wants come from awareness-card.md §2, measured after the hand
            // moved to Patrick Hand. Every hand row wants 400 — the family ships
            // one weight, so a row reporting anything else means a synthesised
            // bold slipped in, which is the failure this table exists to catch.
            ("timestamp Kalam", 13.5, 300, "Kalam", UIFont(name: "Kalam-Light", size: S.tHandMeta)),
            ("ticker hand", 28, 400, "Patrick Hand", S.handUI(S.tHandTitle)),
            ("spot Inter", 25, 600, "Inter", S.interUI(S.tPaperSpot, S.wSemiN)),
            ("chip hand", 17, 400, "Patrick Hand", S.handUI(S.tPaperChip)),
            ("read hand", 17, 400, "Patrick Hand", S.handUI(S.tPaperChip)),
            ("heading hand", 21, 400, "Patrick Hand", S.handUI(S.tHandHead)),
            ("body Inter", 16, 450, "Inter", S.interUI(S.tPaperBody, S.wBodyN)),
            ("tag hand", 21, 400, "Patrick Hand", S.handUI(S.tHandTag)),
            ("do instr Inter", 18, 600, "Inter", S.interUI(18, S.wSemiN)),
            ("do reason Inter", 14, 450, "Inter", S.interUI(14, S.wBodyN)),
        ]
    }

    static func dump() {
        guard SunnyMeasure.on else { return }
        print("FONTAUDIT ---- element | want | got size | got wght | family")
        for (label, wantSize, wantW, wantFamily, f) in rows() {
            guard let f else { print("FONTAUDIT \(label) | MISSING FONT"); continue }
            let vars = f.fontDescriptor.object(forKey:
                UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute")) as? [Int: CGFloat]
            let gotW = vars?[0x77676874]
            let sizeOK = abs(f.pointSize - wantSize) < 0.01
            let wOK = gotW == nil ? true : abs((gotW ?? 0) - wantW) < 0.01
            let famOK = f.familyName == wantFamily
            print(String(format: "FONTAUDIT %-16@ | %5.1f/%3.0f | %6.2f | %@ | %@ | %@",
                         label as NSString, wantSize, wantW, f.pointSize,
                         gotW.map { String(format: "%.0f", $0) } ?? "static",
                         f.familyName,
                         (sizeOK && wOK && famOK) ? "OK" : "MISMATCH"))
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
