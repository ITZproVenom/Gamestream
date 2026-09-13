# GameStream for Android

Native **Kotlin + Jetpack Compose** port of GameStream: Xbox Cloud Gaming in a WebView with **Better xCloud** injected on every load.

## Features

- Library / Search / Settings tabs
- Better xCloud userscript + modern CSS overrides
- Resolution & region settings written into BX `localStorage`
- Bottom bar hides while streaming
- Persistent cookies / sign-in flag

## Build

```bash
cd android
# first time only if gradlew is missing:
gradle wrapper --gradle-version 8.9

./gradlew :app:assembleDebug
```

APK output:

`app/build/outputs/apk/debug/app-debug.apk`

Or open the `android/` folder in **Android Studio** and Run.

## CI

`.github/workflows/build-apk.yml` builds a debug APK on pushes that touch `android/` and attaches it to the **latest** GitHub Release.

## Notes

- This is **not** Liquid Glass (iOS-only). UI uses Material 3 dark theme.
- Streaming quality depends on device WebView / network; Better xCloud still helps a lot.
- Debug APK is unsigned for Play Store — sideload only.
