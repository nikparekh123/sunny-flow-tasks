//
//  SunnyGlass.swift
//  Sunny
//
//  The glass every Home card sits on, built once (Nik's spec from the design files, 8 Nov 2026). Layers, bottom to
//  top: .ultraThinMaterial (the blur of the page behind), a white LinearGradient topLeading → bottomTrailing, a soft
//  inner glow across the top 18 pt, a 1 pt inner stroke, a 1.5 pt top-left highlight, a light-only hairline, then two
//  shadows. Not .glassEffect(): that is for native controls only (tab bar, Search button, account capsule, segmented
//  controls). With Reduce Transparency on, the card is solid (white .96, #1C1C1E in dark) and keeps its shadows.
//  It needs SBackground behind the page and nothing opaque in between.
//

import SwiftUI

struct SunnyGlass: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var solid
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark
        content
            .background {
                if solid {
                    shape.fill(dark ? Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255) : Color.white.opacity(0.96))
                } else {
                    ZStack {
                        // The blur of the page behind. Not .ultraThinMaterial: measured 8 Nov against the design's
                        // screens 01/02 it read grey (card 234-242 where the design is 255 white; dark 43-58 where the
                        // design is 8), because the design's backdrop also has saturate 220% brightness 1.06 contrast
                        // 1.05, which no material can do. SunnyGlassBackdrop is that result, drawn once.
                        if !SunnyGlassDebug.noBackdrop {
                            Color.clear
                                .overlay(alignment: .topLeading) { SunnyGlassBackdrop(dark: dark) }
                                .clipShape(shape)
                        }
                        shape.fill(LinearGradient(stops: [
                            .init(color: .white.opacity(dark ? 0.10 : 0.62), location: 0),
                            .init(color: .white.opacity(dark ? 0.03 : 0.22), location: 0.38),
                            .init(color: .white.opacity(dark ? 0.02 : 0.14), location: 0.62),
                            .init(color: .white.opacity(dark ? 0.07 : 0.40), location: 1),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                        // The soft inner glow: white .9 (dark .12) across the top 18 pt, fading down.
                        LinearGradient(colors: [.white.opacity(dark ? 0.12 : 0.9), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .clipShape(shape)
                        shape.strokeBorder(Color.white.opacity(dark ? 0.16 : 0.7), lineWidth: 1)
                        shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.28 : 1), .white.opacity(0)],
                                                          startPoint: .topLeading, endPoint: .center), lineWidth: 1.5)
                        if !dark { shape.stroke(Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255).opacity(0.06), lineWidth: 0.5) }
                    }
                }
            }
            // ⚠ SCROLLING (8 Nov 2026, 3.0 (2) was jerky): the shadows sit on a still shape behind the card, never on the
            // card itself, so they are drawn once and not again on every frame the card's backdrop slides.
            .background {
                if !SunnyGlassDebug.noShadow {
                    shape.fill(dark ? Color.black : Color.white)
                        .shadow(color: .black.opacity(dark ? 0.2 : 0.04), radius: 1.5, y: 1)
                        .shadow(color: .black.opacity(dark ? 0.4 : 0.10), radius: 12, y: 10)
                }
            }
    }
}

/// Simulator-only switches to measure scrolling: `-glassNoBackdrop`, `-glassNoShadow`.
enum SunnyGlassDebug {
    #if DEBUG && targetEnvironment(simulator)
    static let noBackdrop = ProcessInfo.processInfo.arguments.contains("-glassNoBackdrop")
    static let noShadow = ProcessInfo.processInfo.arguments.contains("-glassNoShadow")
    #else
    static let noBackdrop = false
    static let noShadow = false
    #endif
}

extension View {
    func sunnyGlass(radius: CGFloat = 20) -> some View { modifier(SunnyGlass(radius: radius)) }
}

/// The page as the design's backdrop-filter shows it through a card (SunnyBriefs --cbf: blur 14, saturate 220%,
/// brightness 1.06, contrast 1.05; dark saturate 180%), worked out in sRGB as the browser does: in light the page's
/// grey clips to white and each blob turns vivid at its centre (green 154,255,158; blue 181,242,255; yellow
/// 255,249,138); in dark the page stays near black and the blobs read green 18,80,20, blue 22,58,96, yellow 72,53,0.
/// ⚠ DRAWN ONCE (8 Nov 2026): a picture of the whole screen, made the first time it is needed for each theme, then
/// slid under each card by the card's place in the window (visualEffect: no redraw while scrolling). Drawing it
/// per card per frame stalled scrolling 105 times in four swipes on the simulator.
struct SunnyGlassBackdrop: View {
    let dark: Bool
    var body: some View {
        if let img = SunnyGlassPicture.image(dark: dark) {
            Image(uiImage: img)
                .resizable()
                .frame(width: img.size.width, height: img.size.height)
                .visualEffect { c, g in
                    let f = g.frame(in: .global)
                    return c.offset(x: -f.minX, y: -f.minY)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

@MainActor
enum SunnyGlassPicture {
    private static var cache: [Bool: UIImage] = [:]

    static func image(dark: Bool) -> UIImage? {
        let size = screen
        if let i = cache[dark], i.size == size { return i }
        let r = ImageRenderer(content: Page(dark: dark).frame(width: size.width, height: size.height))
        r.scale = 2   // smooth gradients and soft blobs: 2x is sharp enough and half the memory of 3x
        guard let img = r.uiImage else { return nil }
        cache[dark] = img
        return img
    }

    private static var screen: CGSize {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.bounds.size }.first ?? CGSize(width: 393, height: 852)
    }

    private struct Page: View {
        let dark: Bool
        var body: some View {
            Canvas { ctx, size in
                let W = size.width, H = size.height
                let page = Path(CGRect(origin: .zero, size: size))
                if dark {
                    ctx.fill(page, with: .linearGradient(Gradient(stops: [
                        .init(color: rgb(10, 15, 12), location: 0),
                        .init(color: rgb(0, 0, 0), location: 0.38),
                        .init(color: rgb(12, 10, 8), location: 1),
                    ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
                } else {
                    ctx.fill(page, with: .color(.white))
                }
                let blobs: [(Color, CGPoint, CGFloat)] = [
                    (dark ? rgb(18, 80, 20) : rgb(154, 255, 158), CGPoint(x: 70, y: 270), 200),
                    (dark ? rgb(22, 58, 96) : rgb(181, 242, 255), CGPoint(x: W - 70, y: 630), 227),
                    (dark ? rgb(72, 53, 0) : rgb(255, 249, 138), CGPoint(x: 220, y: H - 40), 240),
                ]
                for (c, p, r) in blobs {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                             with: .radialGradient(Gradient(colors: [c, c.opacity(0)]), center: p, startRadius: 0, endRadius: r))
                }
            }
        }
        private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    }
}
