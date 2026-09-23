# GameStream — locked core vs clean-slate app

## LOCKED (do not rewrite)

| Area | Files |
|------|--------|
| Microsoft login WebView | `Views/SignInWebView.swift` |
| Streaming WebView + rumble | `Views/StreamPlayerView.swift` |
| Stream boot loader | `Views/PlayLoadingView.swift` |
| Auth URLs / cookies | `Services/MicrosoftAuth.swift` |
| Play / search launch | `Services/PlayCommands.swift`, `Services/HubSession.swift` |
| Better xCloud injection | `Services/BetterXCloudInjector.swift` |
| Session flags | `Services/SessionStore.swift` |

### Contract

- `session.playCatalogGame` / `playGame` → `isStreaming` + `webURL` → **StreamPlayerView**
- `session.openCloudSearch` → same player path
- `session.markSignedInAfterMicrosoftAuth()` → only from **SignInWebView**
- Shared `WKProcessPool` between SignIn and stream — never split

## CLEAN-SLATE APP (compiled)

```
Core/          AppTab + architecture notes
App/           AppRoot, AppShell
Features/      Home, Search, Settings, Details, Onboarding
UI/            AppBackground, GlassTabBar, GameCards
```

Legacy `Views/GameHubView`, `RootView`, `LibraryView`, `SearchView`, `SettingsView`, etc.
are **excluded from XcodeGen** and are not the foundation of the running UI.
