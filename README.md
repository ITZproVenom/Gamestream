<p align="center">
  <img src="docs/icon-preview.png" alt="GameStream" width="120" height="120" />
</p>

<h1 align="center">GameStream</h1>

<p align="center">
  <strong>Native iOS 26 Xbox Cloud Gaming client</strong><br>
  Liquid Glass UI · Better xCloud · Built for performance
</p>

<p align="center">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-26%2B-black?style=flat-square" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-orange?style=flat-square" />
  <img alt="License" src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" />
  <img alt="Better xCloud" src="https://img.shields.io/badge/Better%20xCloud-Integrated-purple?style=flat-square" />
</p>

---

## Overview

**GameStream** is a native iOS app for [Xbox Cloud Gaming](https://www.xbox.com/play).  
It wraps the official web experience in a modern **Liquid Glass** interface and automatically injects **[Better xCloud](https://github.com/redphx/better-xcloud)** so you get higher quality streams, touch controls, stats, and more — without a separate browser extension.

## Features

### Native experience
- **iOS 26 Liquid Glass** UI (real `.glassEffect`, `GlassEffectContainer`)
- Floating glass navigation that **auto-hides while you play**
- Persistent sign-in (cookies + local session)
- Search that opens Xbox Cloud results in-app
- Polished Settings (quality chips, region, account)

### Better xCloud (always on)
- 1080p / high-quality streaming options
- Stream stats HUD (modern glass style)
- Touch controller layouts
- Remote Play support
- Server / region selection
- Visual clarity filters, volume boost, screenshots, and more

### Streaming
- Optimised `WKWebView` (persistent data store, shared process pool)
- Inline media + Picture in Picture ready
- Clean error / loading states

## Requirements

| Requirement | Version |
|-------------|---------|
| iOS | 26.0+ |
| Xcode | 26+ |
| XcodeGen | Latest |
| Apple Silicon / arm64 device or simulator | Required |

An **Xbox account** with Cloud Gaming access (e.g. Game Pass Ultimate, where available) is required to play.

## Build

```bash
# 1. Generate the Xcode project
xcodegen generate

# 2. Open in Xcode
open GameStream.xcodeproj

# 3. Select your team / signing (or keep unsigned for local IPA workflow)
# 4. Run on device or simulator
```

### Unsigned IPA (CI)

This repo includes `.github/workflows/build-ipa.yml` for building an unsigned IPA.

## Project structure

```
Gamestream/
├── GameStream/
│   ├── GameStreamApp.swift
│   ├── Info.plist
│   ├── Assets.xcassets/          # App icon & assets
│   ├── Services/
│   │   ├── SessionStore.swift
│   │   └── SoundManager.swift
│   └── Views/
│       ├── RootView.swift
│       ├── LibraryView.swift
│       ├── SearchView.swift
│       ├── StreamPlayerView.swift   # WebView + Better xCloud injector
│       ├── AnimatedBackground.swift
│       ├── LiquidGlassComponents.swift
│       └── SignInWebView.swift
├── project.yml
├── LICENSE
└── README.md
```

## Better xCloud

The official Better xCloud userscript is downloaded from the  
[redphx/better-xcloud](https://github.com/redphx/better-xcloud) releases, cached on device, and injected into every Xbox Cloud page load.

- Always enabled (no toggle)
- Modern glass overrides for panels & performance HUD
- Open **Library → Better xCloud** badge for tips

Better xCloud is © its authors and used under its license.  
This project is not affiliated with Microsoft or Xbox.

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

GameStream is an unofficial client. Xbox, xCloud, and related trademarks belong to Microsoft.  
Use at your own risk and comply with Microsoft’s terms of service.
