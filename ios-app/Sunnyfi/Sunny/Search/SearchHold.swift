//
//  SearchHold.swift
//  Sunny
//
//  Press and hold the search button 0.45 s: Search opens already listening
//  (block 27). The system tab bar draws the button; this adds the hold to it
//  without touching the tap. It also keeps the bar, which slides away while
//  Search is open (SXTabBar).
//

import SwiftUI
import UIKit

struct SXHoldToTalk: UIViewRepresentable {
    let go: () -> Void

    func makeUIView(context: Context) -> Hook { let v = Hook(); v.go = go; v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ v: Hook, context: Context) { v.go = go }

    final class Hook: UIView, UIGestureRecognizerDelegate {
        var go: (() -> Void)?
        private weak var bar: UITabBar?
        private var tries = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { self.attach() }
        }

        /// The tab bar appears a moment after the TabView: look again for a few seconds.
        private func attach() {
            guard bar == nil, let w = window else { return }
            guard let tb = Self.find(in: w) else {
                tries += 1
                if tries < 20 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.attach() } }
                return
            }
            let g = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:)))
            g.minimumPressDuration = 0.45
            g.delegate = self
            tb.addGestureRecognizer(g)
            bar = tb
            SXTabBar.bar = tb
        }

        private static func find(in v: UIView) -> UITabBar? {
            if let t = v as? UITabBar { return t }
            for s in v.subviews { if let t = find(in: s) { return t } }
            return nil
        }

        @objc private func hold(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            go?()
        }

        /// Only on the search button, the round one right of the four tabs.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive t: UITouch) -> Bool {
            guard let bar else { return false }
            return t.location(in: bar).x > bar.bounds.maxX - 90
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    }
}

/// While Search is open the tab bar and the search button slide down 120 pt out of view (0.45 s,
/// cubic-bezier(.32,.72,0,1)) and fade (0.3 s); closing plays it back from 0.05 s. Reduce Motion cross-fades.
@MainActor
enum SXTabBar {
    static weak var bar: UITabBar?

    static func slide(away: Bool, reduce: Bool) {
        guard let bar else { return }
        if reduce {
            bar.transform = .identity
            UIView.animate(withDuration: 0.25) { bar.alpha = away ? 0 : 1 }
            return
        }
        let delay = away ? 0 : 0.05
        let move = UIViewPropertyAnimator(duration: 0.45, controlPoint1: CGPoint(x: 0.32, y: 0.72), controlPoint2: CGPoint(x: 0, y: 1)) {
            bar.transform = away ? CGAffineTransform(translationX: 0, y: 120) : .identity
        }
        let fade = UIViewPropertyAnimator(duration: 0.3, curve: away ? .easeOut : .easeIn) { bar.alpha = away ? 0 : 1 }
        move.startAnimation(afterDelay: delay)
        fade.startAnimation(afterDelay: delay)
    }
}
