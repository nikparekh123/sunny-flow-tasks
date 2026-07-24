//
//  NVDAHomeScreen.swift
//  Sunnyfi
//
//  The Home tab, rebuilt as a single-ticker NVDA command center. Cards,
//  top to bottom: pulse (price + today's P&L), effective basis, premium
//  pace, IV signal, next earnings/event, latest news. Data comes from
//  NVDAHome.build(store:).
//

import SwiftUI

struct NVDAHomeScreen: View {
    var store: PortfolioStore
    @State private var news: [NewsHeadline] = []
    @State private var newsLoaded = false

    private let lime = Color.theme.neon

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brandRow.padding(.horizontal, 4).padding(.top, 6)

                if let d = NVDAHome.build(store: store) {
                    pulseCard(d)
                    basisCard(d)
                    premiumCard(d)
                    ivCard(d)
                    eventsCard(d)
                    newsCard(d)
                } else {
                    emptyState
                }

                Color.clear.frame(height: 120) // clear floating tab bar
            }
            .padding(.horizontal, 18)
        }
        .background(Color.theme.page)
        .task {
            guard !newsLoaded else { return }
            newsLoaded = true
            news = await store.fetchNews(tickers: ["NVDA"])
        }
    }

    // ── Brand row ──
    private var brandRow: some View {
        HStack(spacing: 8) {
            Text("SUNNYFI")
                .font(.system(size: 13, weight: .black)).tracking(2.2)
                .foregroundStyle(Color.theme.fg1)
            Circle().fill(lime).frame(width: 5, height: 5)
            Text("NVDA").font(.system(size: 11, weight: .heavy)).tracking(1.4)
                .foregroundStyle(Color.theme.fg3)
            Spacer()
        }
    }

    private var emptyState: some View {
        card {
            Text("No NVDA position yet").font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.theme.fg1)
            Text("Once your NVDA shares and calls sync from IBKR, this page fills in.")
                .font(.system(size: 13)).foregroundStyle(Color.theme.fg3).padding(.top, 4)
        }
    }

    // ── 1. PULSE ──
    private func pulseCard(_ d: NVDAHome) -> some View {
        let up = d.dayPct >= 0
        let dayColor = up ? Color(hex: 0xB9E36A) : Color(hex: 0xF0664F)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(d.ticker).font(.system(size: 15, weight: .black)).tracking(0.4)
                    .foregroundStyle(.white)
                // Only show the long name when it actually differs from the
                // ticker — the DB stores NVDA's name as "NVDA", which read as
                // a redundant "NVDA · NVDA".
                if d.name.uppercased() != d.ticker.uppercased() {
                    Text("· \(d.name)").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(lime).frame(width: 6, height: 6)
                    Text("LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(fmtMoney(d.spot, decimals: 2))
                    .font(.system(size: 44, weight: .heavy)).tracking(-1.6).monospacedDigit()
                    .foregroundStyle(.white)
                Text(fmtPct(d.dayPct))
                    .font(.numeric(size: 16, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(dayColor)
            }
            .padding(.top, 12)

            Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.top, 18)

            HStack(alignment: .top, spacing: 12) {
                heroStat("TODAY", fmtMoney(d.todayPL, sign: true),
                         d.todayPL >= 0 ? dayColor : Color(hex: 0xF0664F),
                         "on \(sharesStr(d.shares)) shares")
                Spacer(minLength: 0)
                heroStat("UNREALIZED", fmtMoney(d.unrealizedShares, sign: true),
                         d.unrealizedShares >= 0 ? dayColor : Color(hex: 0xF0664F),
                         "shares vs your basis", trailing: true)
            }
            .padding(.top, 16)

            Text("Position \(compactUSD(d.positionValue)) · \(sharesStr(d.shares)) sh")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                .padding(.top, 16)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26).fill(
                RadialGradient(colors: [Color(hex: 0x25392C), Color(hex: 0x16241B), Color(hex: 0x101A13)],
                               center: .init(x: 0.85, y: -0.1), startRadius: 10, endRadius: 420))
        )
    }

    private func heroStat(_ label: String, _ value: String, _ color: Color, _ sub: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 5) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.1)
                .foregroundStyle(.white.opacity(0.45))
            Text(value).font(.numeric(size: 22, weight: .heavy)).tracking(-0.4).monospacedDigit()
                .foregroundStyle(color)
            Text(sub).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.4))
        }
    }

    // ── 2. EFFECTIVE BASIS ──
    private func basisCard(_ d: NVDAHome) -> some View {
        let above = d.aboveBasisPct >= 0
        return card {
            sectionLabel("EFFECTIVE COST BASIS")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(fmtMoney(d.effectiveAvg, decimals: 2))
                    .font(.system(size: 34, weight: .heavy)).tracking(-1.2).monospacedDigit()
                    .foregroundStyle(Color.theme.fg1)
                Text("was \(fmtMoney(d.rawAvg, decimals: 2))")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.theme.fg4)
                    .strikethrough()
            }
            .padding(.top, 8)
            Text("Premium has pulled your cost down \(fmtMoney(d.premiumPerShare, decimals: 2))/share.")
                .font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3).padding(.top, 6)

            // Price vs basis strip.
            HStack {
                Text("NVDA \(fmtMoney(d.spot, decimals: 2))")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.theme.fg2)
                Spacer()
                Text("\(above ? "+" : "")\(String(format: "%.1f", d.aboveBasisPct))% \(above ? "above" : "below") basis")
                    .font(.numeric(size: 13, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(above ? Color.theme.pos : Color.theme.neg)
            }
            .padding(.top, 16)
        }
    }

    // ── 3. PREMIUM PACE ──
    private func premiumCard(_ d: NVDAHome) -> some View {
        card {
            sectionLabel("PREMIUM COLLECTED")
            HStack(alignment: .top, spacing: 10) {
                paceStat("This week", d.premWeek)
                Spacer(minLength: 0)
                paceStat("This month", d.premMonth, center: true)
                Spacer(minLength: 0)
                paceStat("Lifetime", d.premLifetime, trailing: true, muted: true)
            }
            .padding(.top, 12)
        }
    }

    private func paceStat(_ label: String, _ v: Double, center: Bool = false, trailing: Bool = false, muted: Bool = false) -> some View {
        let align: HorizontalAlignment = trailing ? .trailing : center ? .center : .leading
        return VStack(alignment: align, spacing: 5) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(Color.theme.fg4)
            Text(fmtMoney(v, sign: true))
                .font(.numeric(size: 20, weight: .heavy)).tracking(-0.4).monospacedDigit()
                .foregroundStyle(muted ? Color.theme.fg2 : (v >= 0 ? Color.theme.pos : Color.theme.neg))
        }
        .frame(maxWidth: .infinity, alignment: center ? .center : trailing ? .trailing : .leading)
    }

    // ── 4. IV SIGNAL ──
    private func ivCard(_ d: NVDAHome) -> some View {
        card {
            sectionLabel("IV — TIME TO SELL CALLS?")
            if let iv = d.ivCurrent {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%.1f%%", iv * 100))
                        .font(.system(size: 34, weight: .heavy)).tracking(-1.0).monospacedDigit()
                        .foregroundStyle(Color.theme.fg1)
                    if let verdict = d.ivVerdict {
                        Text(verdict.label)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(verdict.rich ? Color.theme.pos : Color.theme.warn)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill((verdict.rich ? Color.theme.pos : Color.theme.warn).opacity(0.14)))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)

                ivGauge(d).padding(.top, 16)

                Text("Higher IV = fatter premiums when you write calls.")
                    .font(.system(size: 12)).foregroundStyle(Color.theme.fg3).padding(.top, 12)
            } else {
                Text("No IV reading yet — the daily snapshot hasn't run.")
                    .font(.system(size: 13)).foregroundStyle(Color.theme.fg3).padding(.top, 8)
            }
        }
    }

    private func ivGauge(_ d: NVDAHome) -> some View {
        let p = CGFloat(d.ivPercentile ?? 0.5)
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.hair).frame(height: 8)
                    Capsule().fill(
                        LinearGradient(colors: [Color.theme.warn.opacity(0.5), Color.theme.pos],
                                       startPoint: .leading, endPoint: .trailing)
                    ).frame(width: max(8, w * p), height: 8)
                    Circle().fill(Color.theme.fg1).frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(Color.theme.surface, lineWidth: 2))
                        .offset(x: min(max(0, w * p - 7.5), w - 15))
                }
            }
            .frame(height: 16)
            HStack {
                Text("low \(String(format: "%.0f%%", (d.ivLow ?? 0) * 100))")
                Spacer()
                Text("30-day range")
                Spacer()
                Text("high \(String(format: "%.0f%%", (d.ivHigh ?? 0) * 100))")
            }
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.theme.fg4)
        }
    }

    // ── 5. EARNINGS + EVENTS ──
    private func eventsCard(_ d: NVDAHome) -> some View {
        card {
            sectionLabel("NEXT UP")
            VStack(spacing: 0) {
                if let days = d.earningsDays, let date = d.earningsDate {
                    eventRow(icon: "calendar",
                             title: "NVDA earnings",
                             when: countdown(days),
                             detail: "\(AppDates.shortMonthDay(date))\(earningsTimeSuffix(d.earningsTime))",
                             tint: Color.theme.warn,
                             urgent: days <= 7)
                } else {
                    eventRow(icon: "calendar", title: "NVDA earnings",
                             when: "not scheduled", detail: "", tint: Color.theme.fg4, urgent: false)
                }
                if let name = d.eventName, let days = d.eventDays, let date = d.eventDate {
                    Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.vertical, 12)
                    eventRow(icon: "building.columns",
                             title: name,
                             when: countdown(days),
                             detail: "\(AppDates.shortMonthDay(date))\(stars(d.eventStars))",
                             tint: Color.theme.fg2,
                             urgent: days <= 2)
                }
            }
            .padding(.top, 12)
        }
    }

    private func eventRow(icon: String, title: String, when: String, detail: String, tint: Color, urgent: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .heavy)).foregroundStyle(Color.theme.fg1)
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.theme.fg4)
                }
            }
            Spacer()
            Text(when).font(.system(size: 13, weight: .heavy))
                .foregroundStyle(urgent ? Color.theme.neg : Color.theme.fg2)
        }
    }

    // ── 6. NEWS ──
    private func newsCard(_ d: NVDAHome) -> some View {
        card {
            sectionLabel("NVDA NEWS")
            if news.isEmpty {
                Text(newsLoaded ? "No fresh headlines right now." : "Loading headlines…")
                    .font(.system(size: 13)).foregroundStyle(Color.theme.fg3).padding(.top, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(news.prefix(3).enumerated()), id: \.element.id) { idx, n in
                        if idx > 0 { Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.vertical, 11) }
                        newsRow(n)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private func newsRow(_ n: NewsHeadline) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(n.headline).font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.theme.fg1).fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                if let p = n.publisher, !p.isEmpty {
                    Text(p).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(Color.theme.fg3)
                }
                if let ago = relativeAge(n.ts) {
                    Text("· \(ago)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.theme.fg4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        return Group {
            if let urlStr = n.url, let url = URL(string: urlStr) {
                Link(destination: url) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    // ── shared bits ──
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.theme.surface))
            .shadow(color: Color(hex: 0x121E16, alpha: 0.06), radius: 14, x: 0, y: 5)
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .heavy)).tracking(1.3)
            .foregroundStyle(Color.theme.fg3)
    }

    private func sharesStr(_ v: Double) -> String {
        Int(v.rounded()).formatted(.number.grouping(.automatic))
    }
    private func compactUSD(_ v: Double) -> String {
        if abs(v) >= 1_000_000 { return String(format: "$%.2fM", v / 1_000_000) }
        if abs(v) >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return fmtMoney(v)
    }
    private func countdown(_ days: Int) -> String {
        days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days"
    }
    private func earningsTimeSuffix(_ t: String?) -> String {
        switch t {
        case "bmo": return " · before open"
        case "amc": return " · after close"
        default:    return ""
        }
    }
    private func stars(_ n: Int?) -> String {
        guard let n, n > 0 else { return "" }
        return " · " + String(repeating: "★", count: min(3, n))
    }
    private func relativeAge(_ iso: String?) -> String? {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return nil }
        let secs = Date().timeIntervalSince(d)
        if secs < 3600 { return "\(max(1, Int(secs / 60)))m ago" }
        if secs < 86_400 { return "\(Int(secs / 3600))h ago" }
        return "\(Int(secs / 86_400))d ago"
    }
}
