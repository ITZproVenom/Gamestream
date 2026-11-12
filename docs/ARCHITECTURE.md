# GameStream Architecture

GameStream is split around one deliberate boundary: **native app experience vs. cloud streaming session**.

## iOS

```text
SwiftUI
  │
  ├── GameHub
  ├── Search
  ├── Settings
  ├── Library / Favorites / Recents
  └── Controller navigation
        │
        ├── SessionStore
        ├── GameCatalog
        ├── AppearanceStore
        └── ControllerRumble
                 │
                 ▼
          Streaming boundary
                 │
                 ├── MicrosoftAuth
                 ├── SignInWebView
                 ├── StreamPlayerView
                 └── BetterXCloudInjector
                         │
                         ▼
                 Xbox Cloud Gaming
```

### Native layer

The native layer owns the parts of the product that should behave like a normal iOS application:

- navigation
- catalog presentation
- search
- game details
- favorites and recents
- queues and activity
- appearance
- settings
- controller navigation
- physical controller haptics

### Streaming boundary

The WebView is intentionally retained for the pieces that depend on the Xbox web client:

- Microsoft authentication
- Xbox Cloud Gaming playback
- Better xCloud injection
- WebRTC input and stream communication

This boundary keeps the native UI independent from the cloud site's catalog UI while preserving the actual streaming stack.

### Passkeys

Microsoft sign-in can use passkeys (WebAuthn). iOS only lets a WKWebView create or use a passkey when the relying-party ID is listed in the app's associated-domains entitlement **with the `webcredentials:` service type** (`GameStream/GameStream.entitlements`, wired through `CODE_SIGN_ENTITLEMENTS` in `project.yml`) — `applinks:` alone does not enable WebAuthn. Sign-in `target=_blank` popups are kept as separate top-level webviews sharing the default website data store, so the WebAuthn context and the resulting session both survive. CI ad-hoc-signs the unsigned archive with the same entitlements file before packaging the beta IPA and verifies the packaged binary carries it, because sideloading tools preserve an existing signature's entitlements.

## Controller rumble

The rumble pipeline is separate from phone haptics:

```text
Xbox Cloud
   ↓
WebRTC input channel
   ↓
GameStream bridge
   ↓
ControllerRumble
   ↓
GameController / Core Haptics
   ↓
Physical controller
```

The Settings test controls exercise the physical controller path directly.

## Release channels

### Stable

`latest-ios` is the normal iOS release pointer.

### Beta

`latest-ios-beta` is the testing channel for experimental and in-development iOS work.

Experimental changes must not replace the stable pointer.

## Android

Android follows the same product boundary with Kotlin + Jetpack Compose on the native side and WebView + Better xCloud for the cloud session.

## Guiding principles

1. Keep the native experience fast and predictable.
2. Keep streaming-specific code isolated from native catalog UI.
3. Prefer platform APIs over browser-only workarounds for controller features.
4. Treat stable and beta distribution as separate channels.
5. Keep the repository readable enough that the next change has an obvious home.
