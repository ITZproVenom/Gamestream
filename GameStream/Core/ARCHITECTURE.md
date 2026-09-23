# GameStream iOS architecture (clean-slate)

## Core/ (locked + shared contracts)

- `AppTab.swift` — tab identity used by session + shell
- Locked auth/stream sources (not rewritten):
  - `Views/SignInWebView.swift`
  - `Views/StreamPlayerView.swift`
  - `Views/PlayLoadingView.swift` (stream loading only)
  - `Services/MicrosoftAuth.swift`
  - `Services/PlayCommands.swift`
  - `Services/HubSession.swift`
  - `Services/BetterXCloudInjector.swift`
  - `Services/SessionStore.swift` (auth + stream fields)

## App/

- `AppRoot.swift` — signed-out / intro / welcome / Microsoft sheet
- `AppShell.swift` — signed-in tabs + handoff to `StreamPlayerView`

## Features/

- `Home/HomeFeature.swift`
- `Search/SearchFeature.swift`
- `Settings/SettingsFeature.swift`
- `Details/GameDetailsFeature.swift`
- `Onboarding/OnboardingFeature.swift`

## UI/

- `Background/AppBackground.swift`
- `Glass/GlassTabBar.swift`
- `Components/GameCards.swift`

## Intentionally NOT the foundation

Old `Views/GameHubView`, `LibraryView`, `SearchView`, `RootView`, etc. are
excluded from the XcodeGen target. They remain in the tree only as historical
specification; the running app does not compile or present them.
