//
//  SunnyTokens.swift
//  Sunny — NORMATIVE. A faithful port of handoff/tokens.css.
//
//  ⚠ THIS FILE IS THE ONLY PLACE A LITERAL MAY APPEAR. SPEC 00: "No literal
//  values in component code. Every px, hex, shadow, and radius comes from a
//  token. If you need a value that isn't here, STOP and ask. Do not round,
//  interpolate, or eyeball."
//
//  The web handoff enforces that with handoff/lint-tokens.mjs, which only walks
//  .css/.ts/.tsx/.js/.jsx/.html/.svelte/.vue. Swift is outside its extension set,
//  so the lint cannot see this codebase. SunnyLint.swift ports the same checks.
//
//  Values are transcribed, not adapted. Where the CSS gives a fractional px
//  (--col: 174.5px, --hit-bleed: 14.25px) the fraction is kept: on a 3x screen
//  174.5pt is a whole number of pixels and rounding it would break the grid.
//

import SwiftUI

enum S {

    // MARK: grid (iPhone 393pt)
    static let screen:  CGFloat = 393
    static let margin:  CGFloat = 16
    /// ⚠ 11, NOT 12 — and this is what finally kills the half pixel.
    /// The old grid was margin 16 / gutter 12 / column 174.5, and 174.5 x 3 is
    /// 523.5 device pixels, so a column could never sit on a whole pixel and the
    /// first build measured 174.67 against a spec of 174.5. Handoff 10 moved the
    /// gutter to 11: 16 + 175 + 11 + 175 + 16 = 393 exactly. Two columns still
    /// make 361, so M and L never moved.
    static let gutter:  CGFloat = 11
    static let col:     CGFloat = 175
    static let content: CGFloat = 361

    // MARK: card sizes — column spans and ratios, NEVER a fixed height
    enum Size: String {
        case xs, s, m, l
        /// grid-column span
        var span: Int { self == .m || self == .l ? 2 : 1 }
        /// aspect-ratio
        var ratio: CGFloat {
            switch self {
            // ⚠ 175/64, not 2/1. The derived XS (half an S, 174.5 x 87.25) is
            // RETIRED — no card uses that shape. 64 not 56: a 32pt inner box left
            // the label touching the figure.
            case .xs: return 175.0 / 64.0         // 175 × 64
            case .s:  return 1.0                  // 175 × 175
            case .m:  return 361.0 / 174.0        // 361 × 174
            case .l:  return 361.0 / 361.0        // 361 × 361
            }
        }
        var padding: EdgeInsets {
            switch self {
            case .xs: return S.padCardXS          // 16 all round leaves nothing to fit
            case .s:  return S.padCard
            case .m, .l: return S.padCardM
            }
        }
        var shadow: [SunnyShadow] { self == .l ? S.shadowCardL : S.shadowCard }
    }

    // MARK: card shell
    static let radiusCard:  CGFloat = 22      // every card, every size. never 16, never 20
    static let radiusPanel: CGFloat = 16
    static let radiusPill:  CGFloat = 999
    static let radiusChip:  CGFloat = 6
    static let radiusBar:   CGFloat = 4
    static let radiusPip:   CGFloat = 2

    static let padCard  = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    /// --pad-card-m: 17px 19px 16px — an optical bottom trim, not a mistake.
    static let padCardM = EdgeInsets(top: 17, leading: 19, bottom: 16, trailing: 19)
    /// XS only. Inner box 147 x 40.
    static let padCardXS = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    static let padChip  = EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
    static let padPill  = EdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13)

    /// rgba(20, 23, 15, α) is the one raw colour the lint permits, because every
    /// shadow in the system is built from it.
    static func shadowInk(_ a: Double) -> Color { Color(red: 20/255, green: 23/255, blue: 15/255).opacity(a) }
    static let shadowCard  = [SunnyShadow(shadowInk(0.05), 2, 1), SunnyShadow(shadowInk(0.05), 16, 6)]
    static let shadowCardL = [SunnyShadow(shadowInk(0.07), 4, 2), SunnyShadow(shadowInk(0.08), 22, 9)]
    static let shadowFlat  = [SunnyShadow(shadowInk(0.05), 2, 1)]
    /// A saturated ground swallows the lighter pair. The breached put floor is
    /// the only M that takes it.
    static let shadowCardInk = [SunnyShadow(shadowInk(0.16), 4, 2), SunnyShadow(shadowInk(0.18), 22, 9)]

    // MARK: rules — ALWAYS a child view with a height, never a border (SPEC 04)
    static let rule:      CGFloat = 1
    static let ruleHeavy: CGFloat = 2
    static let ruleColor       = hex(0xE7E9E5)
    static let ruleColorStrong = hex(0xDEE0DB)
    static let ruleColorInk    = hex(0x14170F)

    // MARK: neutrals
    static let paper  = hex(0xFFFFFF)
    static let ground = hex(0xF7F8F6)
    static let wash   = hex(0xF0F1EE)
    static let band   = hex(0xEDEFEA)
    static let ink    = hex(0x14170F)
    static let ink2   = hex(0x3C423A)
    static let ink3   = hex(0x4A5046)
    static let mute   = hex(0x5D6359)
    static let mute2  = hex(0x6B7166)
    static let faint  = hex(0x8A9086)
    static let hair   = hex(0xC2C7BE)

    // MARK: gain / loss / attention
    static let gainBar = hex(0x00A945), gain = hex(0x00722F), gainText = hex(0x00631F)
    static let gainDeep = hex(0x00541F), gainQuiet = hex(0x1C5232)
    static let gainSpan = hex(0x8FBFA1), gainWash = hex(0xDFF3E6)
    static let lossBar = hex(0xC4001A), loss = hex(0xA80016), lossText = hex(0x8E0014)
    static let lossQuiet = hex(0x6E1A22), lossTick = hex(0x8A1F14), lossWash = hex(0xFBE4E6)
    static let warn = hex(0xE08600), warnText = hex(0x7A4700), warnDeep = hex(0x5C3300)
    static let warnWash = hex(0xFBEEDC), warnChip = hex(0xF4D9AE)
    static let doGround = hex(0xFBF5E4), doLabel = hex(0x55502F), doBody = hex(0x4C4835)


    // MARK: paper — THE DIGEST CARD ONLY
    //
    // ⚠ DO NOT SPREAD THESE. tokens.css: "The long position digest uses a paper
    // treatment. NOTHING else does — do not spread these onto feed cards,
    // chrome, or chart cards." It earns its difference by being the only one.
    //
    // ⚠ AND HANDWRITING IS NEVER A FIGURE. Labels, tags, the ticker and the
    // timestamp are hand. Every number stays Inter, semibold, tabular. A
    // handwritten price reads as decorative and the card stops being
    // trustworthy at a glance. That is the one rule that outranks the rest.
    static let paperButter    = hex(0xFFFBEA)
    static let paperDot       = Color(red: 160/255, green: 140/255, blue: 80/255).opacity(0.16)
    static let paperDotSize:  CGFloat = 16
    static let paperRing      = Color(red: 160/255, green: 140/255, blue: 80/255).opacity(0.14)
    static let paperRule      = hex(0xE3D9B8)
    static let paperBullet    = hex(0xC4B78C)
    static let paperInk       = hex(0x1F1B12)
    static let paperInkStrong = hex(0x1B1710)
    static let paperInkHead   = hex(0x5A5033)
    static let paperInkMeta   = hex(0x8A7B52)
    static let paperInkDo     = hex(0x453D26)
    static let paperRuleInk   = hex(0x3B3319)
    static let paperDoGround  = Color(red: 216/255, green: 190/255, blue: 110/255).opacity(0.16)

    // Washes are ALPHA OVER THE BUTTER GROUND, never opaque fills. That is what
    // makes them read as highlighter rather than as a chip.
    static let paperMarkNew  = Color(red: 217/255, green: 162/255, blue: 90/255).opacity(0.28)
    static let paperMarkBull = Color(red: 120/255, green: 190/255, blue: 140/255).opacity(0.30)
    static let paperMarkNote = Color(red: 120/255, green: 160/255, blue: 205/255).opacity(0.26)
    static let markNewInk    = hex(0x7C4A16)
    static let markBullInk   = hex(0x0F5A2C)
    static let markNoteInk   = hex(0x2A4A6E)

    // Not in tokens.css, but named there in the DIGEST-CARD colour table.
    static let paperInkTicker = hex(0x2A2413)
    static let paperChipInk   = hex(0x7C4A16)
    static let paperChipRing  = hex(0xD9A25A)

    /* ⚠ THE HAND SCALE MOVED WITH THE FAMILY. awareness-card.md §2 measures the
       card after the swap and supersedes DIGEST-CARD.md on type: heading and tag
       21 (were 22), chip and read 17 (chip was 18). Patrick Hand runs wider and
       squarer than Caveat at the same nominal size, so the old numbers read a
       step too large. The ticker stayed at 28 and the timestamp at 13.5. */
    static let tHandHead:  CGFloat = 21
    static let tHandTag:   CGFloat = 21
    static let tHandTitle: CGFloat = 28
    static let tHandMeta:  CGFloat = 13.5
    /// Every hand element, one value. In CSS this is what stops the capitals
    /// clipping; here the font's own metrics already clear them, and it is kept
    /// so a hand line's box matches the sheet when it is measured.
    static let lhHand: CGFloat = 1.25
    /// Paper body, spot and chip. Bumped from 14.5 / 23 / 17 on 2026-08-23 for
    /// readability. The 1.45 multiple is unchanged.
    static let tPaperBody: CGFloat = 16
    static let tPaperSpot: CGFloat = 25
    static let tPaperChip: CGFloat = 17
    static let lhPaperBody: CGFloat = 1.45

    static let paperBulletSize: CGFloat = 5
    /// ⚠ 9, not 8. It centres a 5px bullet on a 23.2px line box (16px / 1.45).
    /// It was 8 at the old 14.5px body and moved WITH the scale — a paper bullet
    /// at 8 is a defect, and so is a white bullet at 9.
    static let paperBulletOffset: CGFloat = 9

    static let radiusMark: CGFloat = 4
    static let padMark = EdgeInsets(top: 0, leading: 6, bottom: 1, trailing: 6)

    /// The hand. **Patrick Hand, one weight, 400.**
    ///
    /// ⚠ CAVEAT IS GONE, AND THE REASON IS THE BUG NIK FOUND. Caveat is a
    /// lowercase-first script whose capitals ride above the em box, so on
    /// Apple's text engine "LEN" came out with the N's right stem sheared off.
    /// He reported it, I first blamed the typeface's own shape, and the design
    /// had already reached the same conclusion from the other side: awareness-
    /// card.md §0.2 replaces the hand for exactly this. Patrick Hand is printed
    /// rather than joined and its capitals are built as capitals, which is what
    /// lets it set an all-caps ticker at 28.
    ///
    /// ⚠ ONE WEIGHT, SO THIS TAKES NO WEIGHT ARGUMENT. Patrick Hand ships 400
    /// only. A heading and a tag differ by SIZE AND COLOUR, never by weight —
    /// asking for 700 here would get a synthesised bold, which is the thing a
    /// hand layer must never look like. The old signature carried a wght because
    /// Caveat was variable; it is gone so no call site can ask for a weight that
    /// does not exist.
    static func hand(_ size: CGFloat) -> Font {
        handUI(size).map(Font.init) ?? .system(size: size)
    }
    /// Inter with an explicit numeric weight, so 450 survives the trip.
    static func interUI(_ size: CGFloat, _ wght: CGFloat) -> UIFont? {
        guard let b = UIFont(name: "Inter", size: size) else { return nil }
        return UIFont(descriptor: b.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"):
                [0x77676874: wght, 0x6F70737A: min(max(size, 14), 32)]]), size: size)
    }
    static func inter(_ size: CGFloat, _ wght: CGFloat) -> Font {
        interUI(size, wght).map(Font.init) ?? .system(size: size)
    }

    /// ⚠ CSS line-height is the TOTAL line advance; SwiftUI's .lineSpacing is
    /// the EXTRA space ON TOP of the font's own natural line height. Passing
    /// size x (multiple - 1) is the obvious move and it is wrong: at 14.5/1.45
    /// it hands SwiftUI 6.52 where the answer is 3.48, because Inter's natural
    /// advance at 14.5 is already 17.54. Measure the font, then subtract.
    static func leading(_ size: CGFloat, _ wght: CGFloat, _ multiple: CGFloat) -> CGFloat {
        guard let f = interUI(size, wght) else { return 0 }
        return max(0, size * multiple - f.lineHeight)
    }
    /// No variation attribute: Patrick Hand is a static face with a single
    /// master, so there is no axis to set.
    static func handUI(_ size: CGFloat) -> UIFont? {
        UIFont(name: "PatrickHand-Regular", size: size)
    }

    /// Kalam is STATIC, and exists so the timestamp does not read as another
    /// heading. Do not merge it with Caveat.
    static func handAlt(_ size: CGFloat) -> Font {
        Font(UIFont(name: "Kalam-Light", size: size) ?? .systemFont(ofSize: size))
    }

    // MARK: type ramp — pick a step, never interpolate
    static let t10: CGFloat = 10, t11: CGFloat = 11, t12: CGFloat = 12, t13: CGFloat = 13
    static let t14: CGFloat = 14, t15: CGFloat = 15, t17: CGFloat = 17, t19: CGFloat = 19
    static let t22: CGFloat = 22, t26: CGFloat = 26, t30: CGFloat = 30
    static let t34: CGFloat = 34, t39: CGFloat = 39

    /// ⚠ NOT a Font.Weight. SwiftUI's Font.Weight has no 450 step, and routing
    /// through it silently rounds to .regular = 400. DIGEST-CARD §2: "Body is
    /// 450, not 400 and not 500. On butter at 14.5px, 400 goes thin and 500
    /// goes heavy — 450 is the one that holds." Inter is variable, so 450 is
    /// reachable; it just has to be asked for as a number. Use S.inter().
    static let wBodyN: CGFloat = 450
    static let wMidN:  CGFloat = 500
    static let wSemiN: CGFloat = 600
    static let wBoldN: CGFloat = 700

    static let wBody: Font.Weight = .regular     // 400. Do NOT use for paper body.
    static let wMid:  Font.Weight = .medium      // 500
    static let wSemi: Font.Weight = .semibold    // 600 — all figures
    static let wBold: Font.Weight = .bold        // 700 — all uppercase labels

    /// letter-spacing, in em. SwiftUI wants points, so multiply by the size.
    static let lsLabel = 0.13, lsTag = 0.08, lsTight = -0.03, lsTighter = -0.04
    static func track(_ size: CGFloat, _ em: Double) -> CGFloat { size * em }

    static let lhFigure = 1.0, lhTight = 1.25, lhBody = 1.4, lhLoose = 1.5

    // MARK: inner spacing — flex/grid gap ONLY
    static let gap1: CGFloat = 2,  gap2: CGFloat = 4,  gap3: CGFloat = 6
    static let gap4: CGFloat = 8,  gap5: CGFloat = 11, gap6: CGFloat = 12
    static let gap7: CGFloat = 16

    // MARK: chrome
    static let statusbarH: CGFloat = 54
    /// ⚠ THE TICKER STRIP IS GONE. Handoff 10 deleted row 2 outright — the
    /// market-state dot and the SPY/QQQ/IWM cluster with it. Neither earned
    /// permanent space: the open/closed dot repeats the clock, and those three
    /// are not positions Nik holds. The always-on rail replaced it and docks at
    /// the BOTTOM. Left here as a gravestone so nobody re-adds it from memory.
    // static let tickerH: CGFloat = 34
    static let zonebarH: CGFloat = 56
    static let searchH: CGFloat = 56          // open; 0 closed
    static let filterrowH: CGFloat = 44
    static let homeIndicatorH: CGFloat = 24
    static let frameRadius: CGFloat = 52
    static let hitMin: CGFloat = 44
    static let hitBleed: CGFloat = 14.25
    static let hitGrow: CGFloat = 20
    static let zoneLine: CGFloat = 130
    static let zoneJumpOffset: CGFloat = 46
    static let scrollDeadband: CGFloat = 4
    static let scrollReveal: CGFloat = 24

    // MARK: the shell — SHELL.md
    //
    // ⚠ THE ZONE BAR IS GONE, AND WITH IT Now / New / Next. SHELL.md replaces
    // the three zones with Featured, then one section per name, then Misc. A
    // card is in ONE of those places at a time — never two — and an `order`
    // decides which. Zones sorted by recency and could not answer "where is my
    // TLT card"; a name section always can.
    //
    // Row stack is 54 / 44 / 0 / pane / 48 / 24 = 860. Rows 1 and 6 are the
    // OS's here (see SunnyChrome.swift), so this app renders 44 / 0 / pane and
    // lets the safe area supply the rest.

    /// Pane padding: 16 all round, 40 at the base (SHELL.md §6). The 40 is
    /// breathing room only.
    ///
    /// ⚠ AND THE RAIL'S 48 IS ADDED TO IT HERE. SHELL.md derives a 690 pane by
    /// putting the rail IN FLOW below it. Nik's instruction is that the rail
    /// stays as it is, which means the overlay of cards/text-rail.md — so the
    /// pane runs under the dock and has to clear it itself. Same picture at
    /// rest; the difference only shows when the dock slides away, and in flow
    /// that would open a 48pt white gap instead of showing the feed.
    static let panePadTop: CGFloat = 16
    static let panePadBottom: CGFloat = 40

    /// Section heading, measured 361 × 34 = 10 + 18 (a 15px Inter line box) + 6.
    static let headingPadTop: CGFloat = 10
    static let headingPadBottom: CGFloat = 6
    static let headingGap: CGFloat = 9

    /// The read control on a Featured card: 44 tall, ground --ink, label
    /// 13/600 --on-ink. The negative insets let the 44pt hit bleed past the
    /// card's 17/16 padding so the button does not inflate the row it sits in.
    static let readPillPadX: CGFloat = 20
    static let readBleedTop: CGFloat = -14
    static let readBleedBottom: CGFloat = -13

    /* ⚠ THE PAPER READ CONTROL PAYS FOR ITS OWN BAND — no negative bleed.
       The first build borrowed the white pill's −14 / −13 so the 44pt hit would
       not inflate the row. awareness-card.md §1 measures the real thing: the
       read band is its own 62pt row (44 hit + 18 padding-bottom) and the card is
       641 with it. A filed card drops the whole band rather than collapsing it,
       which is why "measured height is identical before and after" holds. */
    static let readBandPadBottom: CGFloat = 18
    /// Pencil circle, not the white card's filled pill: an ink pill on butter
    /// reads as a foreign element pasted onto a note.
    static let readRing = hex(0xC4B78C)          // = --paper-bullet
    static let padRead = EdgeInsets(top: 1, leading: 15, bottom: 2, trailing: 15)
    /// The card's second and last rotation. The chip owns −1.4.
    static let readTilt: Double = -1.1
    static let chipTilt: Double = -1.4

    /// The search disc in the filter strip. −9 lands the 30pt disc on the 16pt
    /// margin while the 44pt hit box keeps its size.
    static let searchDisc: CGFloat = 30
    static let searchLead: CGFloat = -9
    /// Gap between pills in the strip's scroller, and between the scroller and
    /// its two neighbours.
    static let pillGap: CGFloat = 20
    static let stripGap: CGFloat = 16

    // MARK: always-on rail (bottom dock) — CHROME.md §2, cards/text-rail.md
    //
    // ⚠ TEXT, NEVER CARDS. A card in a 48pt strip is a geometry argument with
    // itself: radius over half the height, a figure fighting a 32pt inner box,
    // a hit target per slot. Card mode was built and rejected.
    //
    // ⚠ AND EVERY INK IS JUDGED AGAINST THE COMPOSITE, never against --ink. The
    // ground is translucent: rgba(20,23,15,.92) over --ground resolves to
    // rgb(38,41,34), which costs a solid-ink palette ~40% of its contrast. The
    // first pass shipped #9BA196 words (6.84:1 solid, 3.98:1 composited) and a
    // #363A31 rule at 1.10:1, invisible. Paper inks die outright here.
    /// How far the filter strip's trailing fade runs.
    ///
    /// ⚠ 40, AND THE TWO EARLIER VALUES WERE BOTH RIGHT FOR THEIR OWN STRIP.
    /// It began at 32, which greyed two letters of a long label and still read
    /// as a clipped word, so it went to 72. That was correct while the strip
    /// showed "NFLX Awareness" — dissolving a 90pt label needs a long ramp.
    ///
    /// The new shell shows tickers first, and a ticker is ~22pt. Measured on a
    /// 402pt phone the pill port is 319 and the six tickers use 270, so they
    /// fit with 49 to spare — but a 72pt fade starts at 314 and CEG starts at
    /// 315, so the whole label sat inside the ramp and read as cut. That is the
    /// bug Nik reported, and it was never a width problem.
    ///
    /// The rule the number comes from: THE FADE MUST BE NARROWER THAN THE SLACK
    /// AFTER THE LAST TICKER, or it eats a whole label. 40 clears CEG by 9pt and
    /// is still long enough to dissolve rather than cut. If a seventh name is
    /// added the tickers themselves will overflow, and no fade width saves that
    /// — the strip would have to drop the per-card tags to the search field.
    static let railFadeW: CGFloat = 40
    static let railH: CGFloat = 48
    static let tRail: CGFloat = 13          // THE size. one, no exceptions
    static let railGap: CGFloat = 14        // fact, rule, fact
    static let railGround = Color(red: 20/255, green: 23/255, blue: 15/255).opacity(0.92)
    static let railWord   = hex(0xC2C7BE)   // the name of a fact.        8.66:1
    static let railFigure = hex(0xF4F6F2)   // any figure with no direction. 13:1
    static let railMinor  = hex(0x9BA196)   // joining words, 2d, 4d.     5.54:1
    static let railDivider = Color(red: 244/255, green: 246/255, blue: 242/255).opacity(0.22)
    static let gainOnInk  = hex(0x55C98C)   // 7.17:1
    static let lossOnInk  = hex(0xF0837F)   // 5.8:1
    /// padding-bottom on a fact: rides 2.5pt high so the line optically centres
    /// in the space ABOVE the home indicator, not in its own 48pt box.
    static let railLift: CGFloat = 5
    static let durRail = 0.58, durRailFade = 0.44
    /// ⚠ 12, not the filter row's 4. At 4 one thumb flick toggles the dock twice
    /// and the 580ms transform never lands. A dock that snaps looks like a bug.
    static let scrollDeadbandRail: CGFloat = 12
    /// 28 + the dock's 48, so the last card clears the overlay.
    static let tailSpacer: CGFloat = 76

    // MARK: planner card (M) — cards/planner-card.md
    //
    // ⚠ RULED, not the digest's dot grid, and never both on one card.
    static let plannerGround   = hex(0xFBF5E4)   // ruled sheet, AND the disc glyph
    static let plannerRuleInk  = Color(red: 20/255, green: 23/255, blue: 15/255).opacity(0.07)
    static let plannerRulePitch: CGFloat = 25
    static let plannerDot      = hex(0x00A945)   // 7px, filled, never a ring
    static let plannerLabel    = hex(0x55502F)
    static let plannerBody     = hex(0x4C4835)
    /// NOT --pad-card-m. The ruled ground reads as a sheet and needs the base
    /// tighter than the crown.
    static let padPlannerM = EdgeInsets(top: 16, leading: 19, bottom: 15, trailing: 19)
    static let tHandInstruction: CGFloat = 31
    /// ⚠ 1.02, NOT .95 — and the design changed it for the reason I hit.
    /// planner-card.md in handoff 11: "it was .95 under Caveat, which clipped
    /// Patrick Hand's capitals. Patrick Hand sits taller in its box, so 1.02
    /// keeps the two lines reading as one written gesture without shaving the
    /// tops." Still below the font's natural advance, so it is still a NEGATIVE
    /// VStack spacing; .lineSpacing cannot express either number. Never on Inter.
    static let lhHandInstruction: CGFloat = 1.02
    static let stampInk    = hex(0x8A1F14)
    static let stampBorder = hex(0xC86A5E)
    static let stampRadius: CGFloat = 5
    static let padStamp = EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
    /// The only rotation on this card, and deliberately not the digest chip's
    /// −1.4°. Different objects; do not unify them.
    static let stampTilt: Double = -2.5
    static let streakDiscM: CGFloat = 34
    static let streakGlyphM: CGFloat = 16
    static let streakPct: CGFloat = 10
    static let gapDisc: CGFloat = 8

    /// The hand's own line height, for the planner's sub-1 instruction leading.
    static func leadingHand(_ size: CGFloat, _ multiple: CGFloat) -> CGFloat {
        guard let f = handUI(size) else { return 0 }
        return size * multiple - f.lineHeight
    }

    // MARK: 5-day price card (L) — cards/five-day-price.md
    //
    // ⚠ BARS ARE DAILY CHANGE, NEVER PRICE LEVEL. Five price levels at this size
    // are five identical bars; the shape of the week is the whole point, and
    // only change has a shape. A down day hangs below the zero line.
    //
    // ⚠ TWO GREENS AND TWO REDS, NOT INTERCHANGEABLE. --gain-text is the 11px
    // day value, --gain the 19px footer figure, --gain-bar the fill and nothing
    // else. Same split on the loss side.
    static let fiveDayCols: CGFloat = 5
    static let fiveDayColGap: CGFloat = 12     // 323 − 4×12 = 275, /5 = 55 exactly
    /* ⚠ THE DAY VALUE AND THE CARD TITLE ARE BUMPED OFF THE SHEET, ON NIK'S
       CALL (25 Aug): "can we increase the % font a bit and also the title TLT 5
       days". five-day-price.md §2 gives 11 for the day value and 10 for the card
       label; both are one ramp step too quiet on a real phone, where the value
       is the thing the card is read for.

       Both land on real ramp steps — --t-13 and --t-12 — rather than between
       them. The value keeps line-height 1: at the default a 13px value makes a
       16pt box and eats the 8px column gap, which is the same trap the sheet
       warns about at 11. And it keeps its minimumScaleFactor, because a −12% day
       at 13px would otherwise run past a 55pt column.

       The FOOTER labels take the same 12. They share a style with the card label
       in the sheet, and the sheet is right about that even where it is wrong
       about the size: bumping one and leaving the other put two weights of the
       same label on one card. Nik's call, in the same breath. */
    static let fiveDayValue: CGFloat = 13      // sheet says 11
    static let fiveDayLabel: CGFloat = 12      // sheet says 10
    static let fiveDayValueH: CGFloat = 13     // the value's own box, line-height 1
    static let fiveDayNameH: CGFloat = 12
    static let fiveDayBarRadius: CGFloat = 5   // the corner AWAY from zero
    static let fiveDayBarRadiusFlat: CGFloat = 1
    /// The tallest bar clears its end of the area by this much, both ends.
    ///
    /// ⚠ THE ZERO LINE IS DERIVED, NEVER AUTHORED. §0.3: "It sits where the
    /// week's largest move needs it, and it is re-derived whenever the data
    /// changes." The sheet's `top: 116` is one solution for the week it was
    /// measured on (best +0.94, worst −0.43); it is not a constant, and pinning
    /// it would put a bar outside its box the first week the extremes move.
    /// The constraint the sheet states is what is implemented: the space above
    /// zero clears the largest up move and the space below clears the largest
    /// down move, each with this headroom.
    static let fiveDayHeadroom: CGFloat = 6
    /// Footer cell: label 12 + gap 5 + figure 19 = 36. The 5 is from §5 and is
    /// not on the --gap ramp; it exists only here.
    static let fiveDayCellGap: CGFloat = 5
    static let fiveDayCellPad: CGFloat = 16    // every cell but the first

    // MARK: position legs widget — cards/position-legs.md
    //
    // ⚠ EVERY CARD HERE IS ABSOLUTELY POSITIONED AND FIXED-SIZE, which CARDS.md
    // forbids on a feed card. The widget breaks that rule knowingly: the cards
    // are a REGION with three layouts chosen by leg count, and a grid cannot
    // express that without leaving holes. §8 records the trade.
    //
    // ⚠ AND IT OWNS opacity/transform/clip. The feed's reveal writes those three
    // inline on [data-card]; inside the region they belong to the zoom, so the
    // region must be excluded from the reveal or the two fight.
    static let totalInk = hex(0xA3202C)   // the position total, and only that

    static let sharesMH: CGFloat = 174    // shares as an M
    static let regionRow: CGFloat = 186   // 175 + 11, one S row pitch
    static let regionMOffset: CGFloat = 185 // 174 + 11, the row under the M
    static let legCard: CGFloat = 175
    static let detailSide: CGFloat = 361

    /* The figure is the ONE element that travels, and it is rendered at 34 and
       scaled DOWN so the resting state in the detail card is native-crisp.
       .88235 is 30/34 exactly. The label does not travel: a tab's x depends on
       the width of every tab before it, which is unmeasurable at author time,
       so the strip fades in as a unit with the tapped leg already inked. */
    static let figS: CGFloat = 16, figSY: CGFloat = 52
    static let figL: CGFloat = 19, figLY: CGFloat = 93
    static let zoomFigScale: CGFloat = 30.0 / 34.0
    static let subSY: CGFloat = 89, subLY: CGFloat = 134

    static let durZoom = 0.42        // travel, and the input lock
    static let durZoomFade = 0.20    // the grid cards leaving
    static let durZoomIn = 0.34      // the detail content arriving
    static let zoomContentDelay = 0.14
    static let zoomBackDelay = 0.22  // grid cards land as the card does
    static let durZoomOut = 0.14     // content leaving is quicker than arriving
    static let zoomScale: CGFloat = 0.97
    static let zoomLock = 0.42

    /// The shadow is its own leaf, because a clip-path clips a shadow away.
    /// Lighter when small: scaling tightens the blur, which is physically what
    /// a smaller card does.
    static let zoomShadowSmall = 0.62

    /// Four columns in 323: (323 − 36) / 4 = 71.75. FOUR is the limit — six fit
    /// at 44 but the 13px values start colliding. A longer history is a second
    /// card, not more columns.
    static let legColGap: CGFloat = 12
    static let hatchStripe: CGFloat = 6
    static let hatchGap: CGFloat = 3

    static let bandH: CGFloat = 133  // was 147; the week labels sat on the footer
    static let weekCell: CGFloat = 74
    static let weekGap: CGFloat = 9
    static let weekBar: CGFloat = 40

    // MARK: the white-card pass — CARD-SYSTEM.md, 25 Aug 2026
    //
    // ⚠ THERE IS NO HAND LAYER. Patrick Hand and Kalam are retired along with
    // BOTH paper treatments — the digest's butter + dot grid and the planner's
    // ruled sheet. Inter is the only family in the shipped deck. The reasoning,
    // from CLAUDE.md: on a butter ground with a dot grid the handwriting read as
    // a note someone left you; on white it reads as a typeface choice, and the
    // tags read as UI highlighting rather than a pen. Once the paper went, the
    // hand had nothing to sit on.
    //
    // ⚠ WEIGHT IS THE HIERARCHY NOW. 300 is context, 700 is the answer, ONE bold
    // per line and it is the figure the line is about. The test: read only the
    // bold and you should get a fair summary of the card. A line whose subject is
    // a RELATIONSHIP gets no bold at all.
    //
    // ⚠ AND 300 IS ONLY LEGAL AT 14 AND ABOVE. Below that it reads as a printing
    // fault however good the contrast is; 12px body words take 400. The same
    // floor applies at ANY size on a saturated ground — contrast does not rescue
    // a thin weight.
    static let wLightN: CGFloat = 300      // context. >= 14px only
    static let wMidSmN: CGFloat = 400      // 12px body words, contract lines

    static let tDigestBody: CGFloat = 15
    static let lhDigest: CGFloat = 1.6     // a 24px line box at 15px
    /// (24 − 4) / 2. NOT the white-card 8 and NOT the retired paper 9 — it is
    /// derived from the line box, so it moves whenever the body does.
    static let digestBulletOffset: CGFloat = 10
    static let tTagBracket: CGFloat = 11
    static let lsTagBracket = 0.1          // looser than a label's .13 at this size
    static let padMarkHi = EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4)
    static let radiusMarkHi: CGFloat = 3
    static let tStar: CGFloat = 14

    // MARK: the red ground — a STATE, not a voice (breached put floor only)
    //
    // ⚠ --ink IS 2.31:1 ON THIS GROUND, so nothing from the white card survives
    // the flip and the card carries its own light-on-dark ladder. The grey ink
    // ladder cannot be reused either: --on-ink-label is 2.96:1 here.
    //
    // ⚠ TWO TEXT STEPS, NOT THREE. A dimmer pink for the 10px bound labels
    // measured 4.62:1 — over the AA line but not by enough for uppercase at that
    // size — so they use --on-loss-body. On a saturated ground there is not
    // enough range below the figure ink to spend on a label tier.
    static let lossGround = hex(0xA80016)     // = --loss, in a GROUND role
    static let onLoss     = hex(0xFFFFFF)     // figures, ticker, strike. 7.84:1
    static let onLossBody = hex(0xF3C7CC)     // body, contract, labels. 5.17:1
    static let onLossTrack = Color.white.opacity(0.20)   // composites to #B93345

    // MARK: put floor (M) — cards/put-floor.md
    //
    // The axis spans 1.5x the band each way, which is what keeps the two bound
    // marks at 16.667% / 83.333% at EVERY band value so only the needle moves.
    static let floorSpanFactor: Double = 1.5
    static let floorRailH: CGFloat = 18
    static let floorTrackH: CGFloat = 10
    static let floorTrackRadius: CGFloat = 5
    static let floorMarkW: CGFloat = 2
    static let floorNeedleW: CGFloat = 3
    static let floorNeedleRadius: CGFloat = 2
    /// Matches the TRACK on white and the GROUND on red — never the card ground
    /// on white, and never white on red, where it would vanish into the needle.
    static let floorNeedleRing: CGFloat = 1.5
    /// The needle pins here and at 100 minus this, i.e. ±14.4% of price at band
    /// 10. Past that the rail stops reporting distance and the sentence carries
    /// it — a needle at the very edge is unreadable as a position anyway.
    static let floorNeedleClamp: CGFloat = 2

    // MARK: chrome colour
    static let dim = hex(0xD3D6D0)
    static let openDot = hex(0x34C759)
    static let tickUp = hex(0x00893A), tickDown = hex(0xC4001A)
    static let onInk = hex(0xF4F6F2)
    static let skeleton = hex(0xEDEFEB), skeletonLabel = hex(0xE4E6E1)

    // MARK: motion — nothing animates that CHROME.md §9 does not list
    static let easeOut    = UnitCurve.easeOut      // cubic-bezier(.2,0,.1,1)
    static let durRevealOpacity = 0.34, durRevealTransform = 0.42
    static let stagger = 0.034, staggerCap = 0.300
    static let revealRise: CGFloat = 7, revealScale: CGFloat = 0.994
    static let durOverlayIn = 0.26, durOverlayOut = 0.38
    static let overlayLift: CGFloat = -4
    static let durSwap = 0.34, swapMidpoint = 0.130
    static let durFilterrow = 0.3, durZone = 0.22, durDrawer = 0.22
    static let pulse = 1.05
    static let debounceQuery = 0.420, debounceFilter = 0.320, debounceClear = 0.260
    static let dot: CGFloat = 7, bullet: CGFloat = 4, barH: CGFloat = 7
    static let transition = 0.18

    // MARK: cubic-bezier, since SwiftUI has no direct equivalent for these
    //
    // ⚠ PASS THE DURATION. DO NOT USE .speed(1 / duration).
    // `.speed(x)` multiplies the RATE, so .speed(1/0.58) is speed 1.72 — nearly
    // twice as FAST as the 0.35s default, landing at 0.203s. Every animation in
    // the redesign was built that way and every one ran 2.9x too quick: the
    // dock snapped away in 0.2s where the sheet asks for 0.58 and says in
    // as many words that a dock which snaps looks like a bug. Nik spotted it on
    // the rail; it was in the filter row and the card reveal too.
    static func easeOut(_ d: Double) -> Animation { .timingCurve(0.2, 0, 0.1, 1, duration: d) }
    static func easeSettle(_ d: Double) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: d) }
    static let cEaseOut   = easeOut(0.35)
    static let cEaseSettle = easeSettle(0.35)
    static let cEaseSwap  = Animation.timingCurve(0.4, 0, 0.2, 1)

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255)
    }
}

/// A CSS box-shadow layer. SwiftUI has no multi-shadow modifier, so the system's
/// two-layer shadows are applied as stacked `.shadow` calls in order.
struct SunnyShadow {
    let color: Color, radius: CGFloat, y: CGFloat
    init(_ c: Color, _ r: CGFloat, _ y: CGFloat) { color = c; radius = r; self.y = y }
}

extension View {
    func sunnyShadow(_ layers: [SunnyShadow]) -> some View {
        layers.reduce(AnyView(self)) { acc, l in
            AnyView(acc.shadow(color: l.color, radius: l.radius / 2, x: 0, y: l.y))
        }
    }
    /// CSS letter-spacing is per-em; SwiftUI tracking is absolute points.
    func sunnyType(_ size: CGFloat, _ weight: Font.Weight, _ em: Double = 0) -> some View {
        font(InkFont.display(size, weight)).tracking(S.track(size, em))
    }
}
