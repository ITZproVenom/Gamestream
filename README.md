<p align="center">
  <img src="docs/gamestream-icon.svg" alt="GameStream" width="120" height="120" />
</p>

<h1 align="center">GameStream</h1>

<p align="center">
  <strong>Xbox Cloud Gaming client for iOS & Android</strong><br>
  Better xCloud · Native GameHub · Sideload builds
</p>

<p align="center">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-26%2B-black?style=flat-square" />
  <img alt="Android" src="https://img.shields.io/badge/Android-8%2B-green?style=flat-square" />
  <img alt="Better xCloud" src="https://img.shields.io/badge/Better%20xCloud-Integrated-purple?style=flat-square" />
  <img alt="License" src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" />
</p>

---

## Download

Builds are **separate by platform and channel**. Stable iOS, iOS Beta, and Android releases have their own download pointers.

### Current builds

| Platform | Download this release | File |
|----------|----------------------|------|
| **iOS** | [📱 Latest iOS build](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios) | `GameStream-unsigned.ipa` |
| **Android** | [🤖 Latest Android build](https://github.com/ITZproVenom/Gamestream/releases) | See the latest Android release |
| **iOS Beta** | [🧪 Latest iOS beta](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios-beta) | `GameStream-unsigned.ipa` |

> **iOS Beta:** Experimental and in-development iOS changes are shipped through this beta channel. Beta builds do not replace or modify the normal `latest-ios` release.

### All builds

- **iOS stable:** [Latest iOS release](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios)
- **iOS historical builds:** [filter `ios-build`](https://github.com/ITZproVenom/Gamestream/releases?q=ios-build&expanded=true)
- **iOS beta:** [Latest iOS beta](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios-beta)
- **Android only:** [filter `android-build`](https://github.com/ITZproVenom/Gamestream/releases?q=android-build&expanded=true)
- **All releases:** [Releases](https://github.com/ITZproVenom/Gamestream/releases)

**Install**
- **iOS:** AltStore / Sideloadly / TrollStore-compatible workflows (unsigned IPA; signing is required before installation where applicable)
- **Android:** allow unknown sources; the release APK is signed

> Stable iOS releases use **📱 iOS**, beta iOS releases use **🧪 iOS Beta**, and Android releases use **🤖 Android**.

---

## Platforms

| Platform | Stack | Folder |
|----------|--------|--------|
| **iOS** | SwiftUI · Liquid Glass · WKWebView | repo root (`GameStream/`) |
| **Android** | Kotlin · Jetpack Compose · WebView | [`android/`](android/) |

Both inject **[Better xCloud](https://github.com/redphx/better-xcloud)** into [xbox.com/play](https://www.xbox.com/play).

---

## iOS quick start

```bash
pip3 install pillow && python3 scripts/generate_app_icons.py
xcodegen generate
open GameStream.xcodeproj
```

CI: `.github/workflows/build-ipa.yml`

---

## Android quick start

```bash
cd android
gradle wrapper --gradle-version 8.9   # if needed
./gradlew :app:assembleRelease
```

APK: `android/app/build/outputs/apk/release/app-release.apk`

CI: `.github/workflows/build-apk.yml`

---

## Features

- Native GameHub / Search / Settings (no website catalog UI)
- WebView only for Microsoft auth + active cloud stream
- Better xCloud quality prefs (resolution, clarity, codec, bitrate)
- Controller rumble with intensity and physical-controller tests on iOS
- Custom backgrounds, library layouts, categorized settings
- Favorites, recents, continue playing

---

## License

MIT — see [LICENSE](LICENSE).
