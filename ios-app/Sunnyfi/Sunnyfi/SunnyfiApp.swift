//
//  SunnyfiApp.swift
//  Sunnyfi
//

import SwiftUI

@main
struct SunnyfiApp: App {
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
                .task { auth.start() }
        }
    }
}

private struct RootView: View {
    let auth: AuthStore

    var body: some View {
        switch auth.state {
        case .loading:
            ZStack {
                Color.theme.page.ignoresSafeArea()
                ProgressView().tint(.theme.neon)
            }
            .preferredColorScheme(.dark)

        case .signedOut:
            SignInView(auth: auth)

        case .signedIn:
            TabRootView(auth: auth)
        }
    }
}
