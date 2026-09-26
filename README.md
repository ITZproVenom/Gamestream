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

Builds are **separate by platform**. Pick iOS or Android — do not mix tags.

### Current builds

| Platform | Download this release | File |
|----------|----------------------|------|
| **iOS** | [📱 Latest iOS build](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios) | `GameStream-unsigned.ipa` |
| **Android** | [🤖 Latest Android build](https://github.com/ITZproVenom/Gamestream/releases) | See the latest Android release |
| **iOS Experimental** | [🧪 Experimental rumble build](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios-experimental-rumble) | `GameStream-unsigned.ipa` |

> **Experimental iOS build:** This is a separate prerelease for testing the experimental native controller-input and rumble path. It is not the normal `latest-ios` build.

### All builds

- **iOS only:** [filter `ios-build`](https://github.com/ITZproVenom/Gamestream/releases?q=ios-build&expanded=true)
- **iOS experimental:** [Experimental rumble release](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios-experimental-rumble)
- **Android only:** [filter `android-build`](https://github.com/ITZproVenom/Gamestream/releases?q=android-build&expanded=true)
- **All releases:** [Releases](https://github.com/ITZproVenom/Gamestream/releases)

**Install**
- **iOS:** AltStore / Sideloadly / TrollStore-compatible workflows (unsigned IPA; signing is required before installation where applicable)
- **Android:** allow unknown sources; the release APK is signed

> Releases are published separately per platform. Titles start with **📱 iOS** or **🤖 Android** so the two platforms are easy to distinguish.

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
