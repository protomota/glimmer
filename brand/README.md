# Glimmer icon

The app icon is a gold sparkle inside an open blue ring on a dark honey-to-slate square. Inside the app,
`GlimmerLogo` (`native/Glimmer/Design.swift`) shows the `AppMark` image asset, the round mask of the icon PNG,
so the About panel, onboarding and Coach always show the real icon.
It replaced the penguin mascot on 2026-11-21.

- `glimmer-icon.svg` is the master artwork: a full-bleed 1024 px square. macOS and iOS round the corners themselves.
- `glimmer-icon-mac.svg` is the same art in Apple's macOS layout (824 px rounded square with a shadow on a
  1024 canvas), for screenshots, the installer mock-up and marketing.
- `glimmer-icon-1024.png` is a ready-made PNG of the master.
- `glimmer-mark-round-1024.png` is that PNG masked to a circle. It is the round logo for About, onboarding,
  Coach and docs (the app's `AppMark` asset). Never redraw the mark in code; regenerate it with the script below.

The sparkle is our own vector path, not the SF Symbol, because Apple does not allow SF Symbols in app icons.

To change the icon, edit `glimmer-icon.svg`, then run `node brand/render-icons.cjs` (needs Playwright and
ImageMagick). It writes the Xcode app icon set, the site favicon, Apple touch icon and header icon, and the Expo
icons. Re-render the share card from `site/og-card.html` afterwards (see that file).
