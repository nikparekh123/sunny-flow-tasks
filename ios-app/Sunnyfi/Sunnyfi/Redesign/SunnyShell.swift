//
//  SunnyShell.swift
//  Sunny — the phone, assembled. SHELL-PAGED.md is normative.
//
//  Rows, top to bottom, and their sum is the acceptance test:
//
//      54  status bar     the OS's here — a real app inherits it
//     665  pane           the only flexible row
//     117  strip          the whole navigation, DOCKED AT THE BOTTOM
//      24  home indicator the OS's
//     ---
//     860
//
//  ⚠ THE FILTER STRIP, THE SEARCH FIELD, FEATURED / MISC AND THE BOTTOM RAIL ARE
//  ALL RETIRED (26 Aug 2026). SHELL.md is history and SunnyChrome.swift is
//  deleted. Do not rebuild any part of either from that file or a screenshot.
//
//  ⚠ AND THE RAIL WENT WITH THEM, WHICH REVERSES AN EARLIER INSTRUCTION. Nik's
//  line on the previous shell was "the text rail at the bottom will stay as is",
//  and it did. SHELL-PAGED.md §9 drops it: two navigations for one app, and the
//  strip already names every destination. RailStore stays — it is where the book
//  comes from — but nothing renders SunnyRail any more. If the facts are wanted
//  back they need a home in the new shell, not the old dock.
//
//  ⚠ THE STRIP IS THE WHOLE NAVIGATION. Tapping a circle REPLACES the pane; it
//  does not scroll to a section. A card exists in exactly one place at a time.
//
//  ⚠ AND IT SITS AT THE BOTTOM (26 Aug 2026), as a flex sibling AFTER the pane
//  rather than an absolute overlay. It is the only control on screen and the one
//  pressed most; at the top of a 393 × 860 phone it was outside thumb reach. The
//  circles went 44 → 60 in the same change — --hit-min is a floor, not a target.
//

import SwiftUI

/* ⚠ THE STRIP IS RETIRED, 14 Sep 2026, from the `glass-nav` handoff. The app's
   navigation is one Liquid Glass tab bar with TWO destinations, New and
   Options, and no names.

   ⚠ WHICH MEANS THE NAME PAGES ARE NO LONGER REACHABLE. The strip was the only
   way into them. The sheet's own argument is that the feed carries the names
   now — Prices, Long legs and Yield progress all list every one — and that if a
   third destination is ever argued for it belongs in a page, not on the bar.
   `SunnyPane` still renders `.name` and `nav.pages` still builds the list, so
   nothing is deleted; there is simply no door. Flagged to Nik with the build.

   ⚠ AND THE PAGER IS RETIRED WITH IT. Swiping between pages existed because the
   strip had many destinations in a row. With two, the tab bar is the switch and
   the horizontal scroller would only fight the vertical one. That takes
   `PaneModel`'s reason for existing away too, but it stays: the tab bar keeps
   both pages alive, so the stores still have to be shared rather than held as
   each pane's own state.

   ⚠ DO NOT DRAW THE GLASS. The reference's rgba(28,30,26,.8) over a 22px blur
   is the WEB stand-in so the mock reads like the device. On device the system
   renders the real material, its refraction and its light/dark adaptation, and
   `.tabBarMinimizeBehavior(.onScrollDown)` gives the compact-on-down rule, the
   spring and the thresholds. The sheet's --gn-threshold, --gn-top-zone and .55s
   spring are that behaviour's approximation; re-implementing them here would
   replace the real thing with a copy of its description. */
struct SunnyShell: View {
    @State private var page: SunnyPage = .options
    /// ⚠ THE STORES LIVE HERE, not inside the pane: both tabs are alive at once,
    /// and stores held as a pane's own `@State` would be fetched twice and
    /// mutate independently — a Read on one copy would leave the other still
    /// showing the card as unread.
    @State private var model = PaneModel()
    private var nav: SunnyNav { model.nav }
    /* Bumped when the ALREADY ACTIVE tab is tapped. The pane watches it and
       returns to the top; a plain selection binding cannot see that tap,
       because the value it writes is the value already there. */
    @State private var toTop = 0
    /* ⚠ COMING BACK TO THE APP IS A REFRESH. Nik, 2026-09-10. The `.task` below
       runs once per launch, so returning to a backgrounded app showed figures
       from whenever it was last opened. */
    @Environment(\.scenePhase) private var phase
    @State private var loadedOnce = false
    /* ⚠ DARK AT NIGHT, ON ITS OWN. `export 20/DARK-MODE.md`, 18 Sep 2026: "the
       white cards are too bright to read after dark". One setting for the app,
       `auto | light | dark`, default auto, and the tokens do the rest. The
       clock is re-read every minute, so a page left open goes dark at 19:00
       and comes back at 07:00 without a reload. */
    @AppStorage("sunnyfi.theme") private var themePref = "auto"
    @State private var themeClock = Date()

    /// Deterministic states for verification, so a screenshot does not depend on
    /// a simulated gesture landing on the right pixel.
    ///   -page NEW|OPTIONS   open that destination
    ///   -scrollTo 900       start the pane at that offset
    ///   -navTint white      the bar's tint, for comparing the two readings
    private static var argPage: SunnyPage? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-page"), i + 1 < a.count else { return nil }
        return a[i + 1].uppercased() == "NEW" ? .new : .options
    }
    private static var argScroll: CGFloat? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-scrollTo"), i + 1 < a.count,
              let v = Double(a[i + 1]) else { return nil }
        return CGFloat(v)
    }
    private static var argTintWhite: Bool {
        ProcessInfo.processInfo.arguments.contains("-navTintWhite")
    }

    /// Writing the value that is already there is the re-tap.
    private var selection: Binding<SunnyPage> {
        Binding(get: { page }, set: { p in
            if p == page { toTop += 1 } else { page = p }
        })
    }

    var body: some View {
        TabView(selection: selection) {
            Tab(value: SunnyPage.new) {
                SunnyPane(page: .new, m: model, startAt: Self.argScroll, toTop: toTop)
            } label: {
                /* ⚠ NO CAPTION. The reference bar is two monotone icons and
                   nothing else; with two destinations the bar does not need to
                   say where you are. The title is empty rather than absent so
                   the item still exists, and the name moves to the
                   accessibility label where a screen reader still reads it. */
                Label("", systemImage: "bookmark")
                    .accessibilityLabel("New")
            }
            Tab(value: SunnyPage.options) {
                SunnyPane(page: .options, m: model, startAt: Self.argScroll, toTop: toTop)
            } label: {
                /* The deck's own mark for a position: a short leg written
                   against a long one. No SF Symbol says that, so it ships as a
                   custom symbol and takes the system's weight change with every
                   other tab item. */
                Label("", image: "sunny.options")
                    .accessibilityLabel("Options")
            }
        }
        /* The system's rule, not ours: compacts on scroll down, reopens on
           scroll up, with its own thresholds and spring. */
        .tabBarMinimizeBehavior(.onScrollDown)
        /* ⚠ THE TWO SIGNAL DOTS ARE NOT ON THE BAR, and this was measured, not
           assumed. The sheet asks for a 5px amber dot over New when something is
           waiting to be read and a violet one over Options when a leg needs
           rolling, and says "never a red or green, never a number".

           `.badge(1)` draws the system's red pill WITH the count. `.badge(" ")`
           drops the count and leaves a red dot, which is the right shape. But
           the colour cannot be moved: `UITabBarItem.appearance().badgeColor`
           set in the app's `init`, before any item exists, is ignored by the
           Liquid Glass bar — it stayed red in both places. There is no per-tab
           badge tint in SwiftUI, and the appearance proxy is global anyway, so
           even if it worked both dots would share one colour.

           That leaves red dots, which the sheet forbids, or a hand-drawn bar,
           which it also forbids. So neither: `nav.pending` and `nav.rolling`
           still carry both facts and the pages state them — Roll check
           headlines the count, the New page prints its own. Flagged to Nik. */
        .tint(Self.argTintWhite ? .white : S.ink)
        .background(S.ground)
        .task { await model.loadAll(); loadedOnce = true }
        .onChange(of: phase) { _, now in
            guard now == .active, loadedOnce else { return }
            Task { await model.loadAll(force: true) }
        }
        .onAppear { if let p = Self.argPage { page = p } }
        .preferredColorScheme(Self.resolveTheme(Self.argTheme ?? themePref, now: themeClock))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                themeClock = Date()
            }
        }
    }

    /* ⚠ AUTO IS THE NIGHT WINDOW, OR THE PHONE'S OWN DARK MODE. The sheet: "on
       device, auto follows the system appearance first and the 19:00 to 07:00
       local window when there is none". An iPhone always has an appearance, so
       taken literally the clock would never run, and a phone left in light mode
       would stay bright at midnight, which is the complaint. Either one turns
       it dark. Local time, not ET: the market decides what the cards say, the
       reader's clock decides how bright they are. The screen's trait is read,
       not the window's, because the window's is the override set here. */
    static func resolveTheme(_ pref: String, now: Date) -> ColorScheme {
        if pref == "dark" { return .dark }
        if pref == "light" { return .light }
        let h = Calendar.current.component(.hour, from: now)
        if h >= 19 || h < 7 { return .dark }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
    /// `-theme dark` / `-theme light`: verification only.
    private static let argTheme: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-theme"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }()
}
