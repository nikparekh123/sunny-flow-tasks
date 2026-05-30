# Navi Design System — Claude Code handoff

A self-contained, framework-agnostic package of the **Navi design system** (Sunnyfi's dark, data-dense options/positions UI). Drop it into a repo and build.

## Contents

```
claude-code-handoff/
├── CLAUDE.md          ← READ FIRST. Build rules + voice for any agent/dev.
├── COMPONENTS.md      ← copy-paste HTML for every component
├── README.md          ← you are here
├── example.html       ← a working page wired from the tokens + CSS
├── tokens.css         ← the source of truth (colors, type, space, radii, motion)
├── components.css     ← umbrella @import of the four modules
├── css/
│   ├── dashboard.css  ← atoms + dashboard blocks
│   ├── positions.css  ← greeks bar · table · cards · cockpit · large-type · treemap · ledger
│   ├── strategy.css   ← scanner: triage cards · pipeline · universe table · tape
│   └── band.css       ← Position Lens: band · scrubber · what-if · annotations
└── assets/
    └── glyphs.txt     ← the only sanctioned icon vocabulary (Unicode glyphs)
```

## Quick start

```html
<!doctype html>
<html>
<head>
  <link rel="stylesheet" href="tokens.css">
  <link rel="stylesheet" href="components.css">
</head>
<body class="navi">
  <div class="dash"><div class="dash-inner">
    <!-- compose with classes from COMPONENTS.md -->
  </div></div>
</body>
</html>
```

Open `example.html` to see it assembled. Fonts (Work Sans + DM Mono) load automatically from Google Fonts via `tokens.css`.

## The non-negotiables (full list in CLAUDE.md)

1. Never hardcode a color — always `var(--token)`.
2. DM Mono for every number/ticker/greek; Work Sans for everything else.
3. `--neon` is the only loud accent. Color carries meaning, not decoration.
4. No drop shadows for elevation (only on floating overlays). No gradients except documented tints. No frosted glass.
5. Real minus `−`, Unicode glyphs only, **no emoji, no icon font.**
6. Voice = seasoned desk analyst: concise, numerate, sentence case, never marketing.

## Framework notes

The package is plain CSS + HTML so it works anywhere. To consume in **React/Vue/Svelte**, keep `tokens.css` + `components.css` as global stylesheets and translate the snippets in `COMPONENTS.md` into components 1:1 — the class names are the API. Don't fork the CSS into CSS-modules per component; the system relies on shared tokens and a few overloaded class names (notably `.pcard`, which is scoped under `.lens` for the Position Lens).

## Production

In-browser Babel/JSX is fine for prototypes but not production. Pre-compile any JSX and self-host the two fonts (drop `.woff2` into `assets/fonts/` and replace the `@import` at the top of `tokens.css`) to remove the Google Fonts request.
