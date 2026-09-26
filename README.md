<p align="center">
  <img src="docs/gamestream-icon.svg" alt="GameStream" width="128" height="128" />
</p>

<h1 align="center">GameStream</h1>

<p align="center">
  <strong>A clean native frontend for Xbox Cloud Gaming on iOS and Android.</strong><br>
  SwiftUI · Jetpack Compose · Better xCloud · Controller-first
</p>

<p align="center">
  <a href="https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios"><img alt="iOS Stable" src="https://img.shields.io/badge/iOS-Stable-111111?style=for-the-badge&logo=apple" /></a>
  <a href="https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios-beta"><img alt="iOS Beta" src="https://img.shields.io/badge/iOS-Beta-6E56CF?style=for-the-badge&logo=apple" /></a>
  <a href="https://github.com/ITZproVenom/Gamestream/releases/tag/latest-android"><img alt="Android" src="https://img.shields.io/badge/Android-Latest-3DDC84?style=for-the-badge&logo=android&logoColor=111111" /></a>
</p>

<p align="center">
  <a href="https://github.com/ITZproVenom/Gamestream/releases">Releases</a>
  ·
  <a href="https://github.com/ITZproVenom/Gamestream/blob/main/CHANGELOG.md">Changelog</a>
  ·
  <a href="https://github.com/ITZproVenom/Gamestream/blob/main/CREDITS.md">Credits</a>
</p>

---

## ✦ What is GameStream?

GameStream is a native-feeling Xbox Cloud Gaming client built around a simple idea:

> **The app should feel like an app, not a website inside a box.**

The native layer handles the GameHub, library, search, settings, favorites, recents, queues, activity, appearance, and controller navigation. The WebView is kept where it matters most: Microsoft authentication and the active Xbox Cloud Gaming session.

Better xCloud is integrated into the streaming layer for quality and playback controls.

### Highlights

- 🎮 Native GameHub, library, search, details, lists, and settings
- 🧊 iOS Liquid Glass styling with responsive layouts
- 🔎 Native search with recent searches and genre discovery
- ❤️ Favorites, recents, continue playing, queues, and activity
- 🎛️ Controller navigation across the native UI
- 📳 Physical controller rumble with left, right, and both-handle tests
- ⚙️ Resolution, region, appearance, motion, effects, and haptics controls
- 🖼️ Cached artwork and custom backgrounds
- 🌐 Better xCloud integration inside the streaming WebView
- 📱 Separate stable and beta release channels

---

## ⬇️ Downloads

Choose the channel you want. **Stable and Beta are intentionally separate.**

| Channel | Download | Purpose |
| --- | --- | --- |
| 📱 **iOS Stable** | [Latest iOS](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios) | Normal day-to-day build |
| 🧪 **iOS Beta** | [Latest iOS Beta](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-ios-beta) | Experimental and in-development changes |
| 🤖 **Android** | [Latest Android](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-android) | Current Android APK |

**Important:** Beta builds never replace the stable iOS pointer. Experimental iOS work belongs in Beta.

### Installation

**iOS**

Download the unsigned IPA and install it with a compatible sideloading workflow such as AltStore, Sideloadly, or TrollStore where supported.

**Android**

Download the signed APK and allow installation from the appropriate source on your device.

---

## 🧱 Architecture

GameStream is intentionally split into native app surfaces and the streaming boundary.

```text
GameStream
├── iOS
│   ├── SwiftUI GameHub
│   ├── Native catalog + artwork cache
│   ├── Session / library / activity stores
│   ├── Controller navigation + rumble
│   └── WebView streaming boundary
│       ├── Microsoft authentication
│       ├── Xbox Cloud Gaming
│       └── Better xCloud
│
└── Android
    ├── Jetpack Compose UI
    ├── WebView session
    └── Better xCloud integration
```

### iOS

The iOS target is built with **SwiftUI** and targets **iOS 26+**.

Key areas:

- `GameStream/Fresh/` for the current native catalog and UI layer
- `GameStream/Services/` for session, catalog, appearance, controller, and streaming services
- `GameStream/Views/` for the remaining stream/auth and supporting views
- `GameStream/Assets.xcassets/` for application artwork
- `project.yml` for XcodeGen configuration

### Android

The Android app lives under `android/` and uses Kotlin, Jetpack Compose, Material 3, and WebView.

---

## 🎮 Controller support

Controller input is treated as a first-class part of the app.

Native iOS controller support includes:

- UI navigation with an Xbox-style controller
- Connected-controller status
- Haptics controls
- Rumble intensity
- Physical Left / Right / Both rumble tests
- Stream rumble routing for supported controllers

The stream rumble path is kept separate from generic phone haptics so controller vibration can reach the physical controller.

---

## 🧪 Beta channel

The Beta channel is the safe place for unfinished or experimental iOS work.

That means:

- Stable `latest-ios` stays isolated
- Experimental changes publish through `latest-ios-beta`
- Beta builds use the same IPA packaging pipeline
- No experimental release should replace the stable pointer
- Controller, streaming, UI, and architecture experiments belong here until they are ready

---

## 🛠️ Development

### iOS

Requirements:

- macOS
- Xcode 26
- XcodeGen
- iOS 26 SDK

Generate the project:

```bash
pip3 install pillow
python3 scripts/install_icons.py
xcodegen generate
open GameStream.xcodeproj
```

Build through CI:

```text
.github/workflows/build-ipa.yml
```

### Android

```bash
cd android
./gradlew :app:assembleRelease
```

Build output:

```text
android/app/build/outputs/apk/release/app-release.apk
```

---

## 📚 Project docs

- [Changelog](CHANGELOG.md)
- [Credits](CREDITS.md)
- [Android notes](android/README.md)
- [MIT License](LICENSE)

---

## ♥ Credits

**GameStream is created and maintained by Bestin.**

Built with SwiftUI, Jetpack Compose, WebKit, GameController, Better xCloud, and the open-source ecosystem around Xbox Cloud Gaming.

See the full [Credits](CREDITS.md) for project acknowledgements.

---

<p align="center">
  <sub>GameStream · built for cloud gaming, shaped like a real app.</sub>
</p>
