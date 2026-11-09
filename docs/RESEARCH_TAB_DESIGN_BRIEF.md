# Research tab · design brief

Give this whole file to Claude Design. Reuse Sunny's existing parts wherever they fit: the card glass,
the economy cards (value, last four points, trend, read), the To do rows, the Search answer cards.
If nothing fits, say so and propose a new part. This brief says what to build, what data each part
gets and how often it changes. It says nothing about look; that stays with the UI Kit.

## What it is

A third tab for long-term ideas Nik is researching. The first idea is **SpaceX (SPCX) and Tesla
(TSLA)**, which his cousin is buying big. It is one page for both names, because the merger, Musk and
his promises tie them together. Each company still gets its own scorecard. More ideas come later,
each with its own page built the same way.

It answers three questions, in this order:
1. Is anything wrong? (a thesis-breaker tripped)
2. What changed this week, and does it help or hurt?
3. What is the price assuming, and is the story on track?

## Where it lives

- **Tab bar:** Home | Positions | Research, plus the Search circle. The bar has to fit three tabs at
  393 wide.
- **Research opens on a list of ideas.** There's one today. Each row shows the idea's name, both
  tickers with price and day move, how many things changed this week, and a flag when a
  thesis-breaker tripped. With only one idea, the tab may open straight into it: your call.
- **Home:** one line, only when a thesis-breaker trips or something big lands. Tapping it opens the
  idea. Otherwise nothing on Home.
- **Push:** a notification the moment a thesis-breaker trips.
- **Search:** "what changed on SpaceX this week" answers with this tab's cards.
- **Logins:** the research is the same for every login. Only the "your holding" line follows the book
  on screen. Nik will decide later whether his cousin's login sees this tab, so design it to work
  either way.

## The idea page, top to bottom

The top half is about now. The bottom is a shelf of reference pages. Each shelf row shows a one-line
summary and opens its own page.

**Top half**

1. **Header.**
   - The idea's name.
   - Both tickers: price, day move and company value.
   - The book's holding in each, in one line (for example "1,200 shares · 20 Jan 2028 calls").
   - When it was last updated.
2. **Alerts.** Thesis-breakers.
   - When none has tripped, it's one line: "All clear · 13 checked". Tapping it opens the list.
   - A tripped breaker goes to the top of the page with what tripped it, when, and the source.
   - A "watching" breaker (getting close) shows its check line.
3. **This week.** The change feed, newest first and grouped by day. Each item shows:
   - the company (SpaceX, Tesla or both)
   - one plain line
   - helps, hurts or neutral
   - a tag: fact, claim, forecast, opinion or promise
   - its source, which opens the filing, video moment or post

   Big items are marked. A quiet week says so.
4. **Merger watch.**
   - **The ratio:** "SpaceX is worth 1.42 Teslas", with its 90-day line and range. It's flagged when it
     moves more than 8% in a week with no news, which is often someone positioning early.
   - **The swap with no premium:** "0.47 Tesla shares per SpaceX share".
   - **Who would own the combined company:** at no premium, and at a 25% premium to each side.
   - **Where it stands:** a stage with dates (no talks, talks, committees, terms, vote, closed).
   - When terms are announced, the card shows them next to the ratio.
5. **Valuation.** One block per company:
   - its value against its sales
   - **what the price assumes:** today's businesses valued at normal peer multiples, and the rest,
     which is the bet (robotaxi, FSD and Optimus for Tesla; the SI build-out for SpaceX)
   - the weekly move the options market expects, and whether real moves have run bigger or smaller
     lately

**The shelf (each row opens a page)**

6. **Scorecard · SpaceX** and 7. **Scorecard · Tesla.**
   - The numbers are grouped by segment: SpaceX is SI, Connectivity, Space and Money; Tesla is
     Robotaxi and FSD, Optimus, Auto, Energy and Money.
   - **Core** numbers come first, **context** numbers after.
   - Each number is built like an economy card: the value, its last four points, the trend ("Down 3
     quarters in a row"), Nik's line (the level that breaks the story) and a good-or-bad read.
   - Some items are a status, not a number: Customer B, the Starship milestones, factory status. These
     show stages with dates.
   - Tesla's scorecard opens with its **weekly reads** (China and Europe registrations, US
     inventory). They show the quarter so far against last quarter and against consensus, weeks
     before Tesla reports.
8. **Rules and regulators.**
   - Only the rules that can move the thesis. Each shows who decides, where, its stage (proposed,
     applied, passed, in force, struck down, denied), helps or hurts, and the next date.
   - The robotaxi states (California, Texas, Arizona, Florida, Nevada) may work best as a small grid:
     Tesla's status and Waymo's status in each.
9. **Rivals and partners.**
   - Head-to-head pairs, each with one number on both sides and one read:
     - Waymo against Tesla robotaxi
     - Kuiper against Starlink
     - AST SpaceMobile against Starlink Mobile
     - Rocket Lab, Blue Origin, ULA and China against Falcon
     - Chinese EVs against Tesla
   - Carriers are shown as partners: T-Mobile with Starlink; Verizon and AT&T with AST.
10. **Musk promise ledger.**
    - **The score per company:** how many promises were kept on time, and how late the rest
      typically run.
    - **Open promises:** soonest due first.
    - **Past promises:** kept, late or dropped, with days late.
    - Each promise shows the date said, where it was said, what was promised, the due date and the
      source.
    - Second-hand promises (someone quoting Musk) are marked.
11. **Owners and insiders.**
    - Insider sales and buys, with a one-line summary ("3 insiders sold $41M in 30 days, none
      bought").
    - Top-holder changes each quarter.
    - Short interest and days to cover.
12. **Links and notes.**
    - **Shared links:** Nik shares a YouTube, X or article link. It becomes a dated card: who, when and
      how long, plus a "talks their book" note when it applies. Under that comes each claim, with its
      tag and timestamp. A timestamp opens the video at that moment.
    - Claims that feed another section say where they went (Merger watch, the promise ledger).
    - Things we couldn't confirm are listed as unconfirmed.
    - **Notes:** dated notes from Nik or Claude, for the items no feed covers (Customer B, Cursor,
      Grok, lawsuits).
    - Design where **Add a link** and **Add a note** live. That could be on this page, the iOS share
      sheet into Sunny, or both.
13. **Size of the prize.** Once a year, one row per market:
    - the size
    - whose estimate it is (Musk's own, or an independent one)
    - what today's price assumes ("SpaceX needs about 9% of it")

## The data

The server sends **one JSON document per idea**, `sunny-research?idea=musk`, built like Home's. Every
number arrives twice: as a raw value, and as a `display` string the design shows as-is. Every section
carries `updated` (when it last changed) and `next` (when the next update is due), so a late feed
shows its last good value with a date and is never blank.

Shared shapes:
- `tone`: `helps` | `hurts` | `neutral` | `watch`
- `tag`: `fact` | `claim` | `forecast` | `opinion` | `promise`
- `company`: `SPCX` | `TSLA` | `both`
- `source`: `{ "kind": "filing|launch|regulator|company|news|video|post|note|data", "name": "SEC 8-K", "url": "...", "at": "2026-11-06T08:41:00-05:00" }`

The values below show the shape. Most are placeholders. The real ones are the Baron video, Starlink
ARPU falling from $83 to $69, the 2019 robotaxi promise and the carrier partners.

```json
{
  "idea": "musk",
  "title": "SpaceX and Tesla",
  "asOf": "2026-11-09T16:05:00-05:00",
  "names": [
    { "ticker": "SPCX", "name": "SpaceX", "price": 212.4, "priceDisplay": "$212.40",
      "move": 0.031, "moveDisplay": "3.1%", "valueDisplay": "$1.9T",
      "holding": { "book": "N", "line": "1,200 shares · 20 Jan 2028 calls" } }
  ],

  "breakers": [
    { "id": "deliveries_miss", "company": "TSLA",
      "text": "Deliveries miss consensus by more than 15%",
      "status": "watching",
      "check": "Q4 so far runs 9% under consensus on China and Europe registrations",
      "how": "auto", "checked": "2026-11-09", "trippedAt": null, "source": {} }
  ],

  "changes": [
    { "id": "c_1029", "date": "2026-11-06", "company": "both", "section": "merger",
      "line": "Independent committees at both companies are now weighing a merger",
      "tone": "neutral", "tag": "fact", "big": true,
      "source": { "kind": "video", "name": "Ron Baron on CNBC",
                  "url": "https://www.youtube.com/watch?v=kvlEa0RpSmA&t=83" } }
  ],

  "merger": {
    "ratio": { "value": 1.42, "display": "1.42", "line": "SpaceX is worth 1.42 Teslas",
               "low90": 1.18, "high90": 1.51, "weekMove": 0.06, "flag": null,
               "history": [ { "d": "2026-08-11", "v": 1.21 } ] },
    "swap": { "value": 0.47, "display": "0.47 Tesla shares per SpaceX share" },
    "split": [
      { "premium": 0,    "to": null,     "spacex": 0.587, "tesla": 0.413 },
      { "premium": 0.25, "to": "SPCX",   "spacex": 0.640, "tesla": 0.360 },
      { "premium": 0.25, "to": "TSLA",   "spacex": 0.532, "tesla": 0.468 }
    ],
    "stage": "committees",
    "timeline": [ { "date": "2026-11-06", "line": "Committees at both companies weighing it", "source": {} } ],
    "terms": null
  },

  "valuation": [
    { "ticker": "TSLA", "valueDisplay": "$1.3T", "salesDisplay": "$98B a year", "multiple": "13.3x sales",
      "pieces": [
        { "label": "Cars at carmaker multiples", "display": "$90B" },
        { "label": "Energy at peer multiples", "display": "$60B" },
        { "label": "The bet: robotaxi, FSD, Optimus", "display": "$1.15T", "share": 0.88 } ],
      "implied": { "week": "5.8%", "read": "Real moves ran smaller than this 6 of the last 8 weeks" } }
  ],

  "scorecard": [
    { "id": "starlink_arpu", "company": "SPCX", "group": "Connectivity", "tier": "core",
      "title": "Starlink revenue per user", "plain": "Average monthly revenue per home subscriber",
      "kind": "number", "freq": "quarterly",
      "value": 69, "display": "$69", "period": "Q3 2026",
      "points": [ { "p": "Q4 2025", "d": "$83" }, { "p": "Q1 2026", "d": "$77" },
                  { "p": "Q2 2026", "d": "$72" }, { "p": "Q3 2026", "d": "$69" } ],
      "trend": "Down 3 quarters in a row",
      "line": { "value": 65, "display": "$65", "bad": "below", "setBy": "Nik" },
      "read": "Falling as cheaper plans and new countries grow; still above the line",
      "tone": "watch", "updated": "2026-10-29", "next": "2027-01-28", "source": {} },
    { "id": "starship", "company": "SPCX", "group": "Space", "tier": "core",
      "title": "Starship", "kind": "status",
      "stages": [ { "label": "V3 first flight", "status": "done", "date": "2026-09-14" },
                  { "label": "Ship caught", "status": "next", "due": "2026-12" } ] }
  ],

  "rules": [
    { "id": "ca_driverless", "company": "TSLA", "where": "California", "who": "DMV and CPUC",
      "title": "Driverless permit for paid rides", "stage": "applied", "tone": "helps",
      "read": "Would open the biggest US robotaxi market",
      "next": { "date": "2026-12-15", "what": "CPUC vote" }, "updated": "2026-11-04", "source": {} }
  ],
  "robotaxiStates": [ { "state": "TX", "tesla": "no driver, paid", "waymo": "no driver, paid" } ],

  "rivals": [
    { "id": "robotaxi", "title": "Robotaxi", "metric": "Paid rides a week",
      "ours": { "name": "Tesla", "display": "40K" },
      "theirs": [ { "name": "Waymo", "display": "400K" } ],
      "read": "Waymo is about 10 times bigger and growing faster", "updated": "2026-11-02" }
  ],
  "partners": [
    { "carrier": "T-Mobile", "with": "Starlink", "what": "Phone service from satellites" },
    { "carrier": "Verizon", "with": "AST SpaceMobile", "what": "Investor and partner" },
    { "carrier": "AT&T", "with": "AST SpaceMobile", "what": "Investor and partner" }
  ],

  "promises": {
    "score": { "TSLA": { "display": "3 of 21 on time", "late": "the rest run about 2 years late" } },
    "items": [
      { "id": "p_robotaxi_2020", "company": "TSLA", "said": "2019-04-22", "where": "Autonomy Day",
        "what": "Over a million robotaxis on the road", "due": "2020-12-31",
        "status": "late", "daysLate": 2139, "secondHand": false, "source": {} },
      { "id": "p_space_dc", "company": "SPCX", "said": "2026-11-06", "where": "Ron Baron on CNBC",
        "what": "Space data centres begin launching", "due": "2028-12-31",
        "status": "open", "secondHand": true, "source": {} }
    ]
  },

  "owners": {
    "insiderLine": "3 insiders sold $41M in 30 days, none bought",
    "insiders": [ { "date": "2026-11-03", "company": "SPCX", "who": "Director", "action": "sold",
                    "display": "$12M", "plan": true, "source": {} } ],
    "holders": [ { "company": "TSLA", "name": "Vanguard", "change": "+1.2%", "quarter": "Q3 2026" } ],
    "short": [ { "company": "SPCX", "pct": "2.4% of float", "days": "1.1 days to cover", "asOf": "2026-10-31" } ]
  },

  "links": [
    { "id": "l_baron", "kind": "video", "site": "YouTube",
      "title": "Ron Baron on CNBC Squawk Box", "who": "Ron Baron",
      "whoNote": "Top holder in both; says he talks his book",
      "published": "2026-11-06", "shared": "2026-11-08", "length": "6:40",
      "url": "https://www.youtube.com/watch?v=kvlEa0RpSmA", "status": "ready",
      "claims": [
        { "at": "1:23", "tag": "fact", "text": "Independent committees at both companies are weighing a merger", "goesTo": "merger" },
        { "at": "3:20", "tag": "promise", "text": "Musk says space data centres launch from 2027 to 2028", "goesTo": "promises" },
        { "at": "4:08", "tag": "claim", "text": "Some Cybertruck production ending to make room for robotaxis", "note": "Not yet confirmed" },
        { "at": "5:41", "tag": "opinion", "text": "Expects Tesla to rise five times in ten years" } ],
      "unconfirmed": [ "Power figures for China and the US" ] }
  ],
  "notes": [ { "id": "n_1", "date": "2026-11-08", "by": "Nik", "company": "SPCX", "section": "SI", "text": "..." } ],

  "tam": [
    { "market": "Space data centres", "company": "SPCX", "display": "$1T by 2035", "whose": "Musk",
      "independent": "$200B", "priced": "Today's value needs about 9% of it", "updated": "2026-11" }
  ],

  "shelf": [
    { "id": "scorecard_spcx", "title": "Scorecard · SpaceX", "summary": "1 of 9 core numbers past its line" }
  ]
}
```

A link's `status` is one of these:
- `reading`: about a minute
- `ready`
- `no_transcript`: the video has no captions
- `needs_text`: X posts can't be read without the paid X API, so Nik pastes the text or a screenshot

## How often it updates

The app reads the document when the tab opens and on pull to refresh. Prices and the ratio refresh
every 15 seconds in market hours, like Home. The server rebuilds the document every 15 minutes on
weekdays from 6 AM to 10 PM ET, and right away whenever a feed brings something new.

| Part | Source | How often |
|---|---|---|
| Prices, day move, company values, the ratio | the app's quote feed | every 15 s, 9:30 to 4:00 ET |
| Ratio history (90 days) | daily closes | once a day after the close |
| Filings: 8-K, 10-Q, Form 4, 13D/G, S-3 | SEC EDGAR (free) | checked every 15 min |
| Launches, Starship tests, anomalies | public launch data (free) | hourly, every 15 min on launch days |
| NHTSA recalls and investigations | NHTSA open data (free) | daily |
| FCC and FAA decisions | FCC and FAA sites (free) | daily |
| State robotaxi permits | state DMV and utility commission pages | weekly |
| China registrations | weekly insurance data (posted on X, weak source) | weekly |
| Europe registrations | ACEA, some countries weekly | monthly |
| US inventory and prices | tesla.com (breaks often) | daily |
| Implied weekly move | option chains Sunny already pulls | daily after the close |
| Scorecard numbers | earnings, 10-Q, shareholder letter | quarterly, on report day |
| Valuation | price live, sales quarterly, peer multiples weekly | as listed |
| News lines in This week | a reading pass after the close (news source to decide) | daily |
| Rivals | company posts, launch data, registrations | weekly |
| Musk posts and promises | a weekly pass, plus any shared link | weekly (Saturday); open turns late on its due date |
| Short interest | FINRA | twice a month |
| Top holders | 13F filings | quarterly, 45 days after quarter end |
| Shared links | Nik shares a link | ready about a minute later |
| Notes | Nik or Claude | when written |
| Size of the prize | research pass | once a year |
| Thesis-breakers | re-checked whenever any input above updates | push the moment one trips |

## States to design

- **Alerts:**
  - All clear.
  - One breaker watching.
  - One tripped, which also shows the Home line and the push text.
- **A quiet week:** nothing changed.
- **Report day:** scorecard numbers marked as new today.
- **A late or broken feed:** the last good value with its date and a "late" mark.
- **No line set yet:** the number and trend with no good-or-bad read, until Nik sets the line.
- **Merger stages:**
  - no talks
  - committees
  - terms announced (terms next to the ratio)
  - vote date
  - closed
- **A promise turning late on its due date.**
- **A claim confirmed or proven wrong later:** the tag changes, with the date.
- **Shared links:** reading, ready, no transcript, needs text.
- **The book holds neither name:** no holding line.
- **Privacy on:** money and holdings hidden, as elsewhere in the app.
- **Screen and accessibility:**
  - 393 and 430 wide
  - large Dynamic Type
  - VoiceOver says helps or hurts in words

## Words and numbers

- No em dashes or en dashes; use · or -.
- Money is in K and M as everywhere in Sunny, and B and T for company values. Prices and strikes are
  exact. Percentages take one decimal.
- Helps or hurts is always written as a word, never shown only by a mark.
- Tags read Fact, Claim, Forecast, Opinion, Promise.

## Open for design

- Three tabs plus Search in the bar.
- The top half and the shelf, against one long page.
- How the ownership split reads at each premium.
- Whether the ideas list shows when there is only one idea.
- Where Add a link and Add a note live.

## Not in scope

- **Options positioning:** walls, flow, and implied against real for the ladder. These stay on
  Positions and Walls.
- **Orders:** the app never trades.
- A full news reader.
- Reading X automatically, which needs the paid X API (decide later).
