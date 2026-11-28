//
//  SundialHow.swift
//  The i next to "Sundial" (Nik, 27 Nov 2026: "a page on how it works so I can reference it, shown as an i next to
//  Sundial"), on the Sundial tab and the Home card. It opens sunnyfi.co/sundial/how.html in a sheet: one page for
//  the app and the web (public/sundial/how.html in the repo), so an edit there reaches the app without a TestFlight
//  build. The page follows the phone's light or dark (?theme=), and the sheet wears the page's own background.
//

import SwiftUI
import WebKit

struct SundialInfoButton: View {
    var size: CGFloat = 22
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Text("i")
                .font(.system(size: size * 0.6, weight: .medium, design: .serif)).italic()
                .foregroundStyle(SDC.ink)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(SDC.ink.opacity(0.42), lineWidth: 1.5))
                .contentShape(Rectangle().inset(by: -11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How Sundial works")
        .accessibilityHint("Opens the rules Sundial follows")
        .sheet(isPresented: $open) {
            SundialHowSheet { open = false }
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .presentationDragIndicator(.visible)
                .presentationBackground(SundialHowSheet.fill)
        }
    }
}

struct SundialHowSheet: View {
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var failed = false
    /// The page's own background (how.html: #FFFFFF light, #171717 dark), so the sheet and the page are one surface.
    static let fill = S.dyn(0xFFFFFF, 0x171717)
    static let base = "https://sunnyfi.co/sundial/how.html"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if failed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How Sundial works").sType(IncT.t(30, 36, 700, tr: -0.01), tabular: false).foregroundStyle(SDC.ink)
                    Text("This page needs a connection. Try again in a moment.").sType(IncT.t(15, 22)).foregroundStyle(SDC.mu)
                }
                .padding(.horizontal, 16).padding(.top, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                SundialWebView(url: URL(string: "\(Self.base)?theme=\(scheme == .dark ? "dark" : "light")")!, failed: $failed)
                    .padding(.top, 8)
                    .ignoresSafeArea(edges: .bottom)
            }
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SDC.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(SDC.l12))
                    .contentShape(Circle().inset(by: -6))
            }
            .buttonStyle(.plain)
            .padding(.top, 16).padding(.trailing, 16)
            .accessibilityLabel("Close")
        }
    }
}

/// A plain WKWebView: clear, so the sheet's fill shows until the page paints; it reloads when light or dark changes.
struct SundialWebView: UIViewRepresentable {
    let url: URL
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.scrollView.backgroundColor = .clear
        w.scrollView.contentInsetAdjustmentBehavior = .automatic
        w.navigationDelegate = context.coordinator
        w.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        if let now = w.url, now != url, !w.isLoading { w.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let failed: Binding<Bool>
        init(failed: Binding<Bool>) { self.failed = failed }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed.wrappedValue = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed.wrappedValue = true }
    }
}
