# GameStream for Android

> A clean Kotlin + Jetpack Compose companion to the GameStream iOS client.

GameStream for Android provides a native shell around Xbox Cloud Gaming while keeping the active cloud session inside WebView with Better xCloud integration.

## ✦ Features

- 🎮 Native Library, Search, and Settings surfaces
- 🌐 Persistent WebView session and sign-in state
- ⚙️ Resolution and region preferences
- 🧩 Better xCloud integration
- 🌙 Material 3 dark UI
- 📦 CI-built release APK

## 🧱 Stack

| Layer | Technology |
| --- | --- |
| UI | Kotlin + Jetpack Compose |
| Design | Material 3 |
| Streaming | WebView + Xbox Cloud Gaming |
| Enhancements | Better xCloud |
| Build | Gradle + GitHub Actions |

## 🛠️ Build

From the repository root:

```bash
cd android
./gradlew :app:assembleRelease
```

APK:

```text
app/build/outputs/apk/release/app-release.apk
```

Or open `android/` in Android Studio and run the app.

## 📦 Releases

The current Android build is published through the repository's Android release channel:

**[Latest Android release](https://github.com/ITZproVenom/Gamestream/releases/tag/latest-android)**

CI workflow:

```text
.github/workflows/build-apk.yml
```

## Notes

- The Android UI intentionally does not attempt to reproduce iOS Liquid Glass.
- Streaming quality depends on the device WebView, network, and Xbox Cloud Gaming.
- Release APKs are intended for sideloading unless separately distributed through an app store.

## ♥ Credits

**Created and maintained by Bestin.**

See the root [Credits](../CREDITS.md) for project acknowledgements.
