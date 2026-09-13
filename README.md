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

## Quick start

```bash
# 1. App icon (required for a proper home-screen icon)
pip3 install pillow
python3 scripts/generate_app_icons.py

# 2. Xcode project
xcodegen generate
open GameStream.xcodeproj
```

Then run on a device or simulator. Sign in with your Xbox account in **Library**.

## Overview

**GameStream** is a native iOS app for [Xbox Cloud Gaming](https://www.xbox.com/play).  
It wraps the official web experience in **Liquid Glass** UI and injects **[Better xCloud](https://github.com/redphx/better-xcloud)** on every load.

## Features

- iOS 26 Liquid Glass navigation (auto-hides while streaming)
- Persistent sign-in
- Working Settings (resolution / region applied to Better xCloud)
- Better xCloud always on + modern glass UI overrides
- Stream performance tweaks (shared process pool, persistent cookies)

## App icon

The repo ships an empty App Icon slot. Generate the branded icon before building:

```bash
pip3 install pillow
python3 scripts/generate_app_icons.py
```

This writes `GameStream/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.  
Xcode expands it for all device sizes.

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

Unofficial client. Xbox / xCloud trademarks belong to Microsoft.
