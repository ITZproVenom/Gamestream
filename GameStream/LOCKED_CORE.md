# GameStream — locked core vs rebuild surface

## LOCKED (do not rewrite)

These systems are trusted and working. New UI calls into them; it does not replace them.

| Area | Files |
|------|--------|
| Microsoft / Xbox login WebView | `Views/SignInWebView.swift` |
| Streaming WebView + rumble bridge | `Views/StreamPlayerView.swift` |
| Auth URLs / cookie checks | `Services/MicrosoftAuth.swift` |
| Play / stream / search launch | `Services/PlayCommands.swift`, `Services/HubSession.swift` |
| Better xCloud injection | `Services/BetterXCloudInjector.swift` |
| Session flags used by player | `Services/SessionStore.swift` (auth + stream fields) |

### Contract the new UI uses

- `session.playCatalogGame(_:)` / `playGame(_:)` → sets `isStreaming` + `webURL` → `StreamPlayerView`
- `session.openSearch(query:)` → `openCloudSearch` → same WebView path
- `session.markSignedInAfterMicrosoftAuth()` → called only from `SignInWebView`
- `session.signOut()` / `revalidatePersistedLogin()` → existing cookie logic
- Shared `WKProcessPool` between SignIn and stream WebViews — never split

## REBUILT (UI / navigation)

- `RootView`, `GameHubView`, `SearchHubView`, `SettingsView`
- `GameHubCards`, `HubLayout`, `JumpBackInDock`, `GameDetailView`
- `IntroView`, `WelcomeView` (still hand off to SignInWebView)
- Glass helpers: `GlassCompat`, `LiquidGlassComponents`

## Acceptance flow

Fresh install → Intro → Welcome → **SignInWebView (locked)** → new Home → Play → **StreamPlayerView (locked)**
