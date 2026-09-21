<p align="center">
  <img src="docs/gamestream-icon.svg" alt="GameStream" width="120" height="120" />
</p>

<h1 align="center">GameStream</h1>

<p align="center">
  <strong>Xbox Cloud Gaming client for iOS & Android</strong><br>
  Better xCloud · Native shells · Sideload builds
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

These `latest-*` tags always track the newest successful CI publish for that platform.

| Platform | Download this release | File |
|----------|----------------------|------|
| **iOS** | [📱 Latest iOS IPA](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios) | `GameStream-unsigned.ipa` |
| **Android** | [🤖 Latest Android APK](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-android) | `GameStream-release.apk` |

Pinned snapshot of the current code (in-game rumble polyfill):

- iOS snapshot: [`ios-build-20260919-2007-adddda7`](https://github.com/ITZproVenom/Gamestream/releases/tag/ios-build-20260919-2007-adddda7)
- Android snapshot: see [`latest-android`](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-android) (last APK-producing commit is the rumble polyfill)

### All builds

- **iOS only:** [filter `ios-build`](https://github.com/ITZproVenom/Gamestream/releases?q=ios-build&expanded=true)
- **Android only:** [filter `android-build`](https://github.com/ITZproVenom/Gamestream/releases?q=android-build&expanded=true)
- **All releases:** [Releases](https://github.com/ITZproVenom/Gamestream/releases)

**Install**
- **iOS:** AltStore / Sideloadly / TrollStore (unsigned IPA)
- **Android:** allow unknown sources; APK is signed so it updates over previous official builds

> New dated `ios-build-*` / `android-build-*` releases only publish when that platform’s **app code** changes. Titles start with **📱 iOS** or **🤖 Android** so they’re easy to spot.

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
- Controller rumble (intensity + test) on iOS & Android
- Custom backgrounds, library layouts, categorized settings
- Favorites, recents, continue playing

---

## License

MIT — see [LICENSE](LICENSE).
