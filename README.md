<p align="center">
  <img src="docs/gamestream-icon.svg" alt="GameStream" width="120" height="120" />
</p>

<h1 align="center">GameStream</h1>

<p align="center">
  <strong>Xbox Cloud Gaming client for iOS &amp; Android</strong><br>
  Better xCloud · Native shells · Sideload builds
</p>

<p align="center">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-26%2B-black?style=flat-square" />
  <img alt="Android" src="https://img.shields.io/badge/Android-8%2B-green?style=flat-square" />
  <img alt="Better xCloud" src="https://img.shields.io/badge/Better%20xCloud-Integrated-purple?style=flat-square" />
  <img alt="License" src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" />
</p>

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

CI builds an **unsigned IPA** (`.github/workflows/build-ipa.yml`) and publishes it to [Releases](../../releases) with a changelog.

---

## Android quick start

```bash
cd android
gradle wrapper --gradle-version 8.9   # if needed
./gradlew :app:assembleRelease
```

APK: `android/app/build/outputs/apk/release/app-release.apk`

Or open `android/` in Android Studio.

CI: `.github/workflows/build-apk.yml`.

---

## Features

- Native GameHub / Search / Settings (no website catalog UI)
- WebView only for Microsoft auth + active cloud stream
- Better xCloud quality prefs (resolution, clarity, codec, bitrate)
- Custom Play loading screen with UI sounds
- Favorites, recents, continue playing

---

## License

MIT — see [LICENSE](LICENSE).
