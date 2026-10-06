# Changelog

All notable changes to GameStream are documented here.

## 2.1.1 (beta)

An audit pass over both apps. Nothing here is a new feature; all of it is
behaviour that was wrong.

### iOS

- Touch controls stand down when a controller is connected, and come back when
  it disconnects.
- A catalogue page that failed to load no longer deletes the games it would
  have carried. The pages that did load are merged with what is already on
  screen, and the failure is logged rather than reported as a successful
  refresh.
- Favourites, recents and the queue keep a copy of every game they were told
  to remember, so a game missing from today's Game Pass response cannot
  disappear from your own library.
- The thermal warning only speaks while a stream is running, and no longer
  claims the resolution was lowered, which it never was.
- A failed or unreadable account check no longer reports a signed-out account
  over a session that is known to work.
- Search prepares its folded text when the catalogue changes instead of folding
  every title, genre and description on each keystroke.
- The two time formatters clamp their input, so a bad reading cannot trap.
- The animated backdrop holds still when Reduce Motion is on.
- The bandwidth line is written after the connection line, which is the order a
  session description requires, and both description setters forward their
  remaining arguments so the older callback form still reports back.
- The rumble data channel is hooked once per connection rather than once per
  renegotiation.
- The auto-start helper gives a Play press four seconds to take effect instead
  of pressing again every second until the video starts.
- The stacked screenshot has a deadline: a stalled stream used to leave it
  waiting for a frame that was never coming.
- A locale with no region no longer produces a language tag like "en-en", a
  second redundant network monitor is gone, and the Library genre filter is
  cleared when the selected genre leaves the shelf.
- New: a short wordmark animation on launch, which can be turned off in
  Appearance.

### Android (1.6.0)

- Playtime was never recorded at all. The page reports its URL every second and
  a half and each report ended the timed session and started a new one, so the
  elapsed time never reached the twenty seconds a session needs to count.
- Favourites, recents, the queue and collections stored only a product id and
  looked the rest up in the live catalogue, so anything today's response did
  not carry vanished from your library. A full copy of every game you touch is
  kept now.
- The catalogue was fetched for market US in English whatever the device asked
  for, which meant titles your region cannot stream. It uses your market and
  language, falling back to the US list only when the local market is empty.
- A catalogue page that failed deleted games, as on iOS.
- Leaving the player left the web view alive, so the stream kept running and
  the game audio carried on over the rest of the app.
- The first launch loaded the page twice.
- Poster rows built a card and an artwork request for every game handed to
  them, including the whole catalogue in Browse. They are lazy now.
- Appearance settings did nothing until the app was restarted. The accent,
  theme, layout, density and background now apply immediately.
- Rose, cyan and mono were offered as accents with no colour behind them.
- Aurora, Still and Mesh all drew the same flat fill. They are real gradients
  now, and they hold still when motion is reduced.
- White was offered as a background colour while every label in the app is
  white, which made the interface invisible.
- Favourites came back in a random order after a restart.
- The Better xCloud restyle reacted to every DOM mutation on the stream page.

## 2.1.0 (beta)

### Fixed

- Taking the next game in the queue dropped you out of the player. The player
  is a full-screen cover driven by whether a session is active, and moving on
  ended one session and started the next in the same turn, so SwiftUI was
  asked to dismiss and re-present it at once. The dismissal won: the next game
  started behind the library. A session change now never passes through the
  idle state. The finished game is still written to Activity, the counters
  still reset, and the same page is pointed at the new launch URL.
- Pointing the player at a new game loaded it and then immediately reloaded,
  which re-fetched the page that had been on screen before it.
- "Try again" kept the exhausted automatic-reconnect budget. After three
  automatic attempts the manual button worked, but the next drop in that
  session was reported as an error instead of being rejoined. A manual retry
  now starts a fresh attempt, and it clears the quality warning latch as well,
  which was both suppressing the warning for the rest of the session and
  holding an old timestamp that made the first bad sample of a new attempt
  trip it immediately.

### Added

- **Touch controls for every game.** Whether the on-screen pad appears is not
  the page's decision: the session is set up with an input configuration, and
  the server only sends the touch overlay for a game that asked for touch
  input. The web client asks on the handful of titles Microsoft built layouts
  for and declines everywhere else, which is why most games do nothing at all
  on a phone with no controller attached. Streaming now has a three-way Touch
  controls setting - Hidden, When offered, Every game - and on Every game the
  app rewrites the input configuration on its way to Xbox rather than patching
  the site's minified JavaScript. It cannot invent a layout: a game without
  one gets the generic overlay, and if the session never sends a configuration
  at all the app says so instead of implying the setting worked. This replaces
  the old "hide the site's touch controls" switch, which could only ever take
  something away; an existing choice to hide them is carried over.
- **Use less data on cellular.** On a cellular or otherwise metered
  connection the stream is capped at a chosen bitrate and 720p. It only ever
  lowers what was asked for, never raises a cap set deliberately, and like
  every bitrate choice it is negotiated when a session starts, so it applies
  to the next launch - which Settings now says plainly when the limit is in
  force.
- **Open the overlay with the View button.** The player's controls sit over a
  web page that owns every touch on the video, so reaching them needed a
  two-finger tap or the grab handle, neither of which is any use on a pad
  across the room. Press View twice during a game instead. The page still
  receives the button, so whatever the game does with it keeps working; this
  only listens alongside it. Off by default.

## 2.0.0 — 2026-09-27 (beta)

A rebuild of the iOS app. Two problems ran underneath most of the reported
bugs, and both are fixed at the root rather than patched at the symptom.

### Sign-in now verifies something real

1.x built a legacy `login.srf?wp=MBI_SSL` request by hand and then decided it
had succeeded when a cookie with a familiar-looking name appeared. Xbox Cloud
Gaming does not authenticate from those cookies. After the site's own
`/auth/msa` redirect it stores XSTS tokens in localStorage, and streaming
needs the token whose relying party is `gssv.xboxlive.com`. Checking the wrong
thing is why sign-in looked like it worked and the player then asked the user
to sign in again.

GameStream no longer constructs a login URL and injects nothing into the
sign-in page. It loads xbox.com, lets Microsoft run its own flow, and reads
that token back to confirm the session can actually stream.

### Every source file is in the build

`project.yml` listed sources one by one, and forty of the fifty-four Swift
files had drifted out of the target. The shipped interface was
`Fresh/FreshUI.swift`; the entire `Views/` and `Services/` tree was dead code
that still looked authoritative, so fixes were being made to files the app
never compiled. The target now takes the whole folder, and CI fails the build
if any Swift file is missing from it.

### Fixed

- The loading overlay hid on the first navigation, so a connecting stream was
  indistinguishable from a black screen. It now waits for the video element to
  report that it is playing, and a watchdog reports a stream that never starts.
- Stream failures had nowhere to appear. They are now shown with a retry.
- The screen slept during a game.
- Rumble ignored each packet's duration and only stopped if a zero-motor
  packet happened to arrive, so a dropped session left the controller buzzing.
- Stream-isolation CSS was applied to every xbox.com page, setting
  `overflow: hidden` and hiding anything with "header", "banner" or "social"
  in its class name. That is why the built-in browser could not be scrolled.
  It is now scoped to the launch page.
- The auto-start script clicked any button labelled play, ok, continue or
  start, anywhere on the site, every 600 ms for 45 seconds. It now runs only
  on a launch page and matches the launch prompts exactly.
- Favourites and recents disappeared whenever the catalog response omitted
  them, because only IDs were stored. The library keeps each game in full.
- Poster loading performed synchronous disk reads on the main thread.
- Opening Settings re-applied stored values and reloaded a running stream.
- The Better xCloud userscript was injected twice on every page.
- Toggles backed directly by `UserDefaults` appeared to snap back.
- Two app icon filenames had been replaced with placeholder email addresses,
  leaving the 20×20 slots pointing at files with no extension.

### Added

- A diagnostics screen with a live log, the exact sign-in state, where the
  token was found and when it expires, and copy or share for bug reports.
- A player overlay with exit, next-in-queue and the live resolution.
- Per-game playtime and a fuller activity history.
- Concurrent catalog loading with a cache, so a cold start is not an empty
  screen.
- Up Next, lists, genre filters and search history as first-class features.

### Releases

This workflow publishes to the beta channel only. It never creates, moves or
deletes the stable `latest-ios` pointer.

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

- New application shell with a native three-tab structure: Home, Search, and Settings, with the GameHub acting as the primary native library surface.
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

### Credits

The native rebuild keeps the project creator credit visible in the app and repository: **Made with ♥ by Bestin.**

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
