# Changelog

All notable changes to GameStream are documented here.

## 2026-09-26

### Controller rumble rewrite

Xbox Cloud rumble now follows the real Better xCloud FourMotorRumble path instead of `navigator.vibrate()` / Gamepad `vibrationActuator` shims.

- JS bridge hooks `RTCPeerConnection.createDataChannel` (the same discovery Better xCloud uses) and attaches its own listener to the WebRTC `"input"` channel.
- Packets are parsed with Better xCloud's DeviceVibrationManager layout: gamepadIndex, left/right motor %, left/right trigger %, durationMs.
- `inputConfiguration.enableVibration` is forced on so the Xbox server actually sends vibration packets (WKWebView has no `vibrationActuator`).
- Native side keeps one `CHHapticEngine` per locality (`leftHandle` / `rightHandle` / `handles` / `default` / triggers) alive for the session and retains pattern players so COD gunfire is not dropped.
- Settings Left / Right / Both buttons drive the matching physical handles, with aggregate-handle fallback.
- Diagnostic logs cover controller discovery, localities, input-channel capture, parsed motors, dispatch, and engine failure.

### iOS Full Rebuild

The native iOS application layer has been rebuilt from scratch.

The new build replaces the previous native home, library, search, detail, lists, activity, settings, and app-shell implementations with a new SwiftUI architecture. The Microsoft authentication flow and Xbox Cloud WebView/streaming layer remain intentionally preserved.

### New Native Experience

- New application shell with a native four-tab structure: Home, Library, Search, and Settings.
- New Home experience with a featured game surface, recently played games, favorites, activity summary, and genre discovery.
- New Library with a clean responsive two-column poster grid and menu-based filters.
- New Search with native iOS searchable navigation, recent searches, genre discovery, and result grids.
- New game detail experience with play, favorite, queue, metadata, related games, and list actions.
- New Lists system with list creation, deletion, game membership, and dedicated list views.
- New Activity view backed by local stream-session records.
- New Settings built around native iOS Form controls for appearance, streaming quality, server region, controller haptics, library maintenance, account controls, and catalog refresh.
- New catalog layer that retrieves and hydrates Xbox Game Pass catalog data independently of the former catalog implementation.
- New persistent session data layer for favorites, recents, queue, and play history.

### Architecture Boundary

- Microsoft authentication remains in the existing Microsoft-auth implementation.
- Sign-in WebView remains unchanged.
- Xbox Cloud WebView and streaming bridge remain unchanged.
- Better xCloud injection support remains available to the preserved WebView layer.
- Legacy native UI and catalog sources are no longer included in the Xcode target.

### Build

- **Build #602**
- Commit: `2899350a02fbbd96005d2dd6da490d6ddda0ed7f`
- GitHub Actions build: successful
- IPA: `GameStream-unsigned.ipa`
- IPA size: 551,079 bytes
- Release tag: `latest-ios`
- Release is unsigned and intended for AltStore / Sideloadly / TrollStore.

### Previous Work

Earlier releases included the crash-isolation fixes, catalog concurrency hardening, artwork cache fixes, controller/streaming stability work, and the previous Library/Search/Settings redesign passes. Those native surfaces have now been superseded by the full rebuild above.
