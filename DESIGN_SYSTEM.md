# Sunny Wealth Management — Design System
`version 1.0 · applies to Navi, Sunny Folio, Sunny Ops, Sunny Vault, Sunny HQ`

---

## 1. Foundations

### Brand personality
Dark, calm, precise. The UI should feel like a professional trading terminal that belongs to someone with taste. No gradients, no glow effects, no decorative noise. Data is the hero — the chrome should be invisible.

### Fonts
```
Primary:   Work Sans     — all UI text, labels, buttons, body
Monospace: DM Mono       — all numbers, tickers, prices, Greeks, dates, codes
```

Google Fonts import:
```html
<link href="https://fonts.googleapis.com/css2?family=Work+Sans:wght@300;400;500;600;700;800;900&family=DM+Mono:wght@400;500&display=swap" rel="stylesheet">
```

---

## 2. Color Tokens

### Backgrounds and surfaces
| Token | Value | Usage |
|---|---|---|
| Page | `#0a2828` | Main app background |
| Surface | `#0f3333` | Card header bars, nav bars |
| Dash Page | `#061a10` | Dashboard deep background, scrolling banners |
| Card | `transparent` | Card container fill — outline only, no fill |
| Elevated | `#1e5a50` | Surface-only, never use as text color |

### Text hierarchy
| Token | Value | Contrast on page | Usage |
|---|---|---|---|
| Primary | `#faf5f0` | 14.2:1 | Main values, symbols, headings |
| Secondary | `#a8c4c0` | 7.8:1 | Supporting text, descriptions |
| Muted | `#8abdb6` | 6.2:1 | Sub-labels, secondary data ✓ updated |
| Label | `#6a9e96` | 4.8:1 | Card labels, section headers ✓ updated |
| Disabled | `#325050` | 2.8:1 | Structural dividers only — never use for readable text |
| Invisible | `#1e5a50` | 2.1:1 | Surface use only — never as text |

> Note: `#6a9e96` replaces the old `#325050` for labels and `#8abdb6` replaces `#468278` for muted text. These two swaps solve the readability problem without changing the palette character.

### Semantic colors
| Token | Value | Usage |
|---|---|---|
| Neon | `#d2e632` | Primary accent, active states, CTAs |
| Neon Dark | `#c8d820` | Hover state for neon elements |
| Positive | `#a8d4a0` | Gains, bounces, safe signals |
| Negative | `#e87060` | Losses, risk, expiring, sold |
| Warning | `#e0c060` | Caution, watch, borderline |
| Border Bright | `#326e64` | Emphasized borders on highlighted cards |

### Semantic tints (backgrounds for chips/alerts)
```css
positive tint:  rgba(168, 212, 160, 0.10)
negative tint:  rgba(220,  80,  60, 0.10)
warning tint:   rgba(224, 192,  96, 0.08)
neon tint:      rgba(210, 230,  50, 0.08)
neutral tint:   rgba( 15,  51,  51, 0.50)
border default: rgba( 30,  90,  80, 0.20)
border bright:  rgba( 50, 110, 100, 0.35)
```

---

## 3. Typography Scale

| Name | Size | Weight | Letter-spacing | Usage |
|---|---|---|---|---|
| Display | 72–80px | 800 | -4px | Dashboard hero numbers only |
| Hero | 52px | 800 | -3px | Section hero figures |
| Title | 36px | 300 | -2px | Large dollar values, key metrics |
| Greek | 28px | 400 | -1px | Greek values (delta, gamma etc) |
| Metric | 22px | 500 | -0.5px | Standard metric chips |
| Body | 13px | 400 | 0 | All descriptive text, line-height 1.6 |
| Label | 9px | 500 | 1.2px | ALL CAPS card labels and section headers |
| Section | 8px | 600 | 2px | ALL CAPS section dividers with trailing line |
| Mono | 13px | 400 | 0 | All numbers, tickers, prices, DM Mono font |

All numbers, prices, Greeks, tickers, and dates must use `font-family: 'DM Mono', monospace`.

---

## 4. Buttons

Buttons have no background and no border. Text color and optional underline are the only indicators.

### Text buttons (primary pattern)
```css
background:   transparent
border:       none
font-family:  Work Sans
font-size:    13px
font-weight:  500
cursor:       pointer
padding:      0
transition:   opacity 0.15s
```

```css
/* On hover */
opacity: 0.75
```

### Color by intent
```
Primary action:    color: #d2e632   (neon)
Secondary action:  color: #8abdb6   (muted)
Destructive:       color: #e87060   (negative)
Disabled:          color: #325050   (disabled, cursor: default)
Positive confirm:  color: #a8d4a0   (positive)
```

### Active / selected state
For scenario pills, filter toggles, and mode selectors:
```css
/* Active */
color: #d2e632
text-decoration: underline
text-underline-offset: 3px

/* Inactive */
color: #6a9e96
text-decoration: none
```

### Pill buttons (filter rows, type selectors)
```css
.np {
  font-family: Work Sans;
  font-size: 12px;
  font-weight: 500;
  background: rgba(15, 51, 51, 0.5);
  color: #468278;
  border: none;
  padding: 5px 14px;
  border-radius: 100px;
  cursor: pointer;
}

.np.active {
  background: rgba(210, 230, 50, 0.1);
  color: #d2e632;
}
```

---

## 5. Cards

### Standard card (position detail, add form, Greek analysis etc)
```css
background:    transparent
border:        1px solid rgba(50, 110, 100, 0.25)
border-radius: 10px
overflow:      hidden
```

### Card header bar
```css
background:     #0f3333
padding:        9px 16px
border-bottom:  1px solid rgba(50, 110, 100, 0.20)
```

Header label text:
```css
font-size:       9px
font-weight:     500
letter-spacing:  1.5px
text-transform:  uppercase
color:           #8abdb6
```

### Metric chip (inside cards)
```css
background:    rgba(15, 51, 51, 0.40)
border-radius: 6px
padding:       8px 10px
```

Chip label: `9px · 500 · 1px letter-spacing · uppercase · color #4a7060`
Chip value: `15px · 500 · DM Mono · color #faf5f0 (or semantic color)`

### Semantic card variants
```css
/* Positive */
background: rgba(168, 212, 160, 0.08)
border:     1px solid rgba(168, 212, 160, 0.20)

/* Negative / expiring */
background: rgba(220, 80, 60, 0.04)
border:     1px solid rgba(220, 80, 60, 0.22)

/* Warning */
background: rgba(224, 192, 96, 0.05)
border:     1px solid rgba(224, 192, 96, 0.20)

/* Neon highlight */
background: rgba(210, 230, 50, 0.04)
border:     1.5px solid rgba(210, 230, 50, 0.30)

/* Selected */
border:     1px solid rgba(210, 230, 50, 0.35)
background: rgba(210, 230, 50, 0.03)
```

---

## 6. Tabs

```css
/* Tab bar */
display:       flex
gap:           20px
border-bottom: 1px solid rgba(30, 90, 80, 0.25)
overflow-x:    auto
scrollbar:     hidden

/* Individual tab */
font-size:   13px
font-weight: 400
background:  none
border:      none
color:       #325050
padding:     0 0 10px 0
cursor:      pointer
transition:  color 0.25s
position:    relative

/* Active tab */
color:       #faf5f0
font-weight: 500

/* Active underline */
::after {
  content:    ''
  position:   absolute
  bottom:     0
  left:       0
  right:      0
  height:     1.5px
  background: #d2e632
}
```

---

## 7. Signal Rows

Used in Greek Analysis, Risk Analysis, Impact Preview. The core data display pattern.

```css
/* Row container */
display:        flex
align-items:    center
gap:            12px
padding:        12px 0
border-bottom:  1px solid rgba(30, 90, 80, 0.12)

/* Left color bar */
width:          3px
border-radius:  0
align-self:     stretch
min-height:     30px
/* color = semantic color of the signal */

/* Center content */
flex:           1

/* Title */
font-size:      12px
font-weight:    500
color:          #faf5f0
margin-bottom:  2px

/* Sub-text */
font-size:      11px
color:          #468278
line-height:    1.5

/* Right value */
text-align:     right
font-size:      14px
font-weight:    500
letter-spacing: -0.3px
font-family:    DM Mono
```

Bar color by signal type:
```
Positive / safe:    #a8d4a0
Negative / risk:    #e87060
Warning / watch:    #e0c060
Neutral:            #468278
Unchanged:          #325050
```

---

## 8. Badges

```css
display:         inline-flex
align-items:     center
gap:             4px
font-size:       9px
font-weight:     500
letter-spacing:  0.6px
text-transform:  uppercase
padding:         3px 8px
border-radius:   4px
```

Common variants:
```css
/* Sold / negative */
background: rgba(220, 80, 60, 0.12)
color:      #e87060

/* Bought / positive */
background: rgba(168, 212, 160, 0.12)
color:      #a8d4a0

/* Warning */
background: rgba(224, 192, 96, 0.12)
color:      #e0c060

/* Neutral / live */
background: rgba(30, 90, 80, 0.20)
color:      #468278
```

DTE pill variants (smaller, used on position cards):
```css
/* 0-7 DTE */   color: #e87060  background: rgba(220, 80, 60, 0.08)
/* 8-21 DTE */  color: #e0c060  background: rgba(224, 192, 96, 0.07)
/* 22+ DTE */   color: #a8d4a0  background: rgba(168, 212, 160, 0.07)
```

---

## 9. Inputs

### Underline input (forms, add position)
```css
font-family:   Work Sans
font-size:     14px
padding:       5px 0
background:    none
border:        none
border-bottom: 1px solid rgba(30, 90, 80, 0.35)
color:         #faf5f0
outline:       none
width:         100%

/* Focus */
border-bottom-color: #8abdb6

/* Placeholder */
color: #1e5a50
```

For numeric fields, use `font-family: DM Mono` and `font-size: 13px`.

### Rounded input
```css
font-family:   Work Sans
font-size:     14px
padding:       11px 14px
background:    rgba(15, 51, 51, 0.60)
border:        none
color:         #faf5f0
outline:       none
border-radius: 8px
width:         100%
```

### Field label above input
```css
font-size:       9px
font-weight:     500
letter-spacing:  0.8px
text-transform:  uppercase
color:           #4a7060
margin-bottom:   3px
```

---

## 10. Progress Bars

```css
/* Track */
height:        4px
background:    rgba(15, 51, 51, 0.70)
border-radius: 2px
overflow:      hidden

/* Fill */
height:        100%
border-radius: 2px
/* color = semantic color */
```

---

## 11. Alerts

```css
border-radius: 8px
padding:       12px 14px
display:       flex
align-items:   flex-start
gap:           10px
margin-bottom: 8px

/* Left accent bar */
width:          2px
border-radius:  2px
align-self:     stretch
min-height:     24px

/* Title */
font-size:   12px
font-weight: 500

/* Body */
font-size:   11px
color:       #468278
line-height: 1.5
```

---

## 12. Scrolling Banner

```css
height:        32px
background:    #061a10
border-radius: 8px
overflow:      hidden
font-family:   DM Mono
font-size:     10px

/* animation */
animation: scroll 22s linear infinite
```

Banner text colors:
```
Alert text:    #e0c060
Separator:     #1e5a50
Label:         #325050
Value:         #468278
```

---

## 13. Toggle Switch

```css
/* Track */
width:         40px
height:        22px
border-radius: 11px
background:    rgba(30, 90, 80, 0.30)
cursor:        pointer

/* Track on */
background:    rgba(210, 230, 50, 0.25)

/* Thumb */
width:         16px
height:        16px
border-radius: 50%
background:    #325050
position:      absolute
top:           3px
left:          3px
transition:    transform 0.2s, background 0.2s

/* Thumb on */
transform:     translateX(18px)
background:    #d2e632
```

---

## 14. Skeleton Loaders

```css
background: linear-gradient(
  90deg,
  rgba(15, 51, 51, 0.50) 25%,
  rgba(30, 90, 80, 0.30) 50%,
  rgba(15, 51, 51, 0.50) 75%
)
background-size: 200% 100%
animation:       shimmer 1.5s infinite
border-radius:   4px
```

---

## 15. Animations

```css
@keyframes navi-pulse {
  0%, 100% { opacity: 1 }
  50%       { opacity: 0.3 }
}

@keyframes navi-fade-up {
  from { opacity: 0; transform: translateY(6px) }
  to   { opacity: 1; transform: translateY(0) }
}

@keyframes navi-shimmer {
  0%   { background-position: -200% 0 }
  100% { background-position:  200% 0 }
}

@keyframes navi-blink {
  0%, 49%   { opacity: 1 }
  50%, 100% { opacity: 0 }
}

@keyframes navi-scroll {
  from { transform: translateX(0) }
  to   { transform: translateX(-50%) }
}
```

Live dot (used on live data indicators):
```css
width:         5px
height:        5px
border-radius: 50%
background:    #468278
animation:     navi-pulse 2.5s ease-in-out infinite
```

---

## 16. Layout and Spacing

### Page padding
```
Desktop:  40px
Mobile:   24px 20px
```

### Card inner padding
```
Standard:  16px 18px
Compact:   12px 14px
Header bar: 9px 16px
```

### Grid gaps
```
Card grid:     8–10px
Field row:     8–10px
Section:       44–52px
```

### Border radius
```
Card:          10px
Metric chip:   6–8px
Badge:         4px
Pill button:   100px (full round)
Input rounded: 8px
Progress bar:  2px
```

---

## 17. Rules

**Never do these things:**
- Never use `#325050` or `#468278` as text on dark backgrounds -- they are below 4:1 contrast. Use `#6a9e96` and `#8abdb6` instead.
- Never use `#1e5a50` as text -- it is a surface color only.
- Never add background fills to buttons.
- Never use gradients, drop shadows, blur, or glow effects.
- Never use emoji in UI.
- Never put font sizes below 9px.
- Never use font weights 600 or 700 in body text -- use 500 for emphasis.
- Never use DM Mono for non-numeric text.
- Never use ALL CAPS for body text -- only for 9px labels and section headers.

**Always do these things:**
- Use DM Mono for all numbers, prices, tickers, dates, and codes.
- Use Work Sans for all UI text.
- Use the neon `#d2e632` for exactly one primary accent per screen.
- Keep card backgrounds transparent -- define structure through borders, not fills.
- Use the signal row pattern (`.nsig`) for any ranked or comparative data.
- Use semantic colors consistently: green = positive/safe, red = negative/risk, yellow = warning/watch.
- Pre-fill close price fields with the current market price as the default.

---

## 18. App-specific notes

### Navi (trading terminal)
- Live dot animation on all real-time data indicators.
- All option strikes, Greeks, and prices in DM Mono.
- Scenario buttons (+1%, +5%, live, -1%, -5%) use the active underline pattern.
- Position cards: symbol + expiry in DM Mono, badge (SOLD/BOUGHT), DTE pill, qty and avg price.
- Close form always requires a close price field.

### Sunny Folio (portfolio)
- Investment thesis text uses Body style (13px Work Sans, `#a8c4c0`, line-height 1.6).
- Cost basis, current value, gain/loss always in DM Mono.
- Positive P&L in `#a8d4a0`, negative in `#e87060`.

### Sunny Ops (task management)
- Task cards follow the standard card pattern.
- Priority uses badge variants: High = negative, Medium = warning, Low = neutral.

### Sunny Vault (research library)
- Document cards use the standard card with a `#0f3333` header bar.
- File metadata (date, size, type) in DM Mono muted text.

### Sunny HQ (homepage)
- App cards on the home screen use the neon-outlined card variant for apps with active alerts.
- User name greeting in Title scale (36px, 300 weight).
- Per-app summary data uses Metric scale (22px, 500 weight).
