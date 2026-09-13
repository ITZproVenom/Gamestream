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
- Branded **GameStream** app name + App Icon asset catalog

### Better xCloud (always on)
- 1080p / high-quality streaming options
- Modern glass stream stats HUD
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
| Apple Silicon / arm64 | Required |

An **Xbox account** with Cloud Gaming access is required to play.

## Build

```bash
# 1. Install the branded App Icon (optional but recommended)
pip3 install pillow   # only needed for generate_app_icons.py
python3 scripts/generate_app_icons.py

# 2. Generate the Xcode project
xcodegen generate

# 3. Open in Xcode
open GameStream.xcodeproj

# 4. Select your team / signing (or keep unsigned for the IPA workflow)
# 5. Run on device or simulator
```

### App name & icon

- **Display name:** GameStream  
- **Bundle ID:** `com.gamestream.app`  
- **App Icon:** `GameStream/Assets.xcassets/AppIcon.appiconset`  
  Generate PNGs with `scripts/generate_app_icons.py` (Pillow), then rebuild.

### Unsigned IPA (CI)

This repo includes `.github/workflows/build-ipa.yml` for building an unsigned IPA.

## Project structure

```
Gamestream/
├── GameStream/
│   ├── GameStreamApp.swift
│   ├── Info.plist
│   ├── Assets.xcassets/          # App Icon
│   ├── Services/
│   │   ├── SessionStore.swift
│   │   └── SoundManager.swift
│   └── Views/
│       ├── RootView.swift
│       ├── LibraryView.swift
│       ├── SearchView.swift
│       ├── StreamPlayerView.swift
│       ├── AnimatedBackground.swift
│       ├── LiquidGlassComponents.swift
│       └── SignInWebView.swift
├── scripts/
│   └── generate_app_icons.py
├── project.yml
├── LICENSE
└── README.md
```

## Better xCloud

The official Better xCloud userscript is downloaded from  
[redphx/better-xcloud](https://github.com/redphx/better-xcloud) releases, cached on device, and injected into every Xbox Cloud page load.

- Always enabled  
- Modern glass overrides for panels & performance HUD  
- Open **Library → Better xCloud** badge for tips  

Better xCloud is © its authors. This project is not affiliated with Microsoft or Xbox.

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

GameStream is an unofficial client. Xbox, xCloud, and related trademarks belong to Microsoft.  
Use at your own risk and comply with Microsoft’s terms of service.
