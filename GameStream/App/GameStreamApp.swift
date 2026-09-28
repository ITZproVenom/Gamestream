import SwiftUI
import UIKit
import CoreSpotlight

@main
struct GameStreamApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var auth = XboxAuth.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var catalog = Catalog.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var stream = StreamCoordinator.shared
    @StateObject private var rumble = ControllerRumble.shared

    /// One entry point for every way the app can be asked to do something
    /// from outside: a URL, a Spotlight result, or a Shortcut.
    @MainActor
    private func perform(_ action: DeepLink.Action) {
        switch action {
        case .play(let identifier):
            guard let game = DeepLink.game(for: identifier, in: catalog) else {
                // A shortcut can arrive before the catalogue exists, which is
                // most of the time on a first launch. Asking again after it
                // loads is the difference between working and warning.
                AppLog.shared.warn("deeplink", "no game matches \(identifier) yet; "
                                   + "waiting for the catalogue")
                Task {
                    if catalog.games.isEmpty { await catalog.refresh() }
                    guard let found = DeepLink.game(for: identifier, in: catalog) else {
                        AppLog.shared.warn("deeplink", "no game matches \(identifier)")
                        return
                    }
                    AppLog.shared.info("deeplink", "playing \(found.title)")
                    stream.play(found)
                }
                return
            }
            AppLog.shared.info("deeplink", "playing \(game.title)")
            stream.play(game)
        case .open(let identifier):
            guard let game = DeepLink.game(for: identifier, in: catalog) else { return }
            RootView.Navigator.shared.show(game)
        case .search(let text):
            RootView.Navigator.shared.search(text)
        case .library:
            RootView.Navigator.shared.showLibrary()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(settings)
                .environmentObject(catalog)
                .environmentObject(library)
                .environmentObject(stream)
                .environmentObject(rumble)
                .environmentObject(PendingIntent.shared)
                .task { await startUp() }
                .onOpenURL { url in
                    if let action = DeepLink.action(for: url) { perform(action) }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let action = DeepLink.action(for: activity) { perform(action) }
                }
                .onChange(of: PendingIntent.shared.request) { _, request in
                    guard let request else { return }
                    PendingIntent.shared.request = nil
                    perform(request)
                }
                .onChange(of: scenePhase) { _, phase in
                    handle(phase)
                }
                // Signing in is the first moment there is anything to fetch.
                // Without this the catalogue was only ever loaded at launch,
                // so the first run after a sign-in showed an empty Home and
                // pull-to-refresh was the only way out of it.
                .onChange(of: auth.state) { _, state in
                    guard state.isSignedIn else { return }
                    Task { await loadCatalogueIfNeeded(maximumAge: 0) }
                }
                .onChange(of: settings.keepAwake) { _, keepAwake in
                    // Streaming always keeps the screen on; outside a session
                    // the preference decides.
                    if !stream.phase.isActive {
                        UIApplication.shared.isIdleTimerDisabled = keepAwake
                    }
                }
        }
    }

    /// Start-up order matters: find out whether the user can stream before
    /// deciding which screen to show, and do the slower work alongside it.
    private func startUp() async {
        AppLog.shared.info("app", "GameStream \(AppInfo.versionLine) starting")
        UIApplication.shared.isIdleTimerDisabled = settings.keepAwake
        rumble.start()

        await auth.refresh(reason: "launch")

        if auth.state.isSignedIn {
            await loadCatalogueIfNeeded(maximumAge: 0)
        }
    }

    /// Fetches the catalogue when what is on screen is older than
    /// `maximumAge` seconds. An empty catalogue is always old enough.
    @MainActor
    private func loadCatalogueIfNeeded(maximumAge: TimeInterval) async {
        // Launch and the sign-in change can both ask at once. Refreshing
        // twice would cancel the first fetch halfway and pay for it again.
        if catalog.isLoading { return }
        if !catalog.games.isEmpty, let updated = catalog.updatedAt,
           Date().timeIntervalSince(updated) < maximumAge {
            return
        }
        await catalog.refresh()
        SpotlightIndex.update(with: catalog.games)
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            AppLog.shared.debug("app", "foreground")
            // Coming back from the background is exactly when a token is most
            // likely to have expired.
            Task {
                await auth.refresh(reason: "foreground")
                // Game Pass adds and removes titles constantly, and the
                // catalogue was only ever fetched at launch: an app left
                // open for days offered games that had gone and hid ones
                // that had arrived.
                guard auth.state.isSignedIn, !stream.phase.isActive else { return }
                await loadCatalogueIfNeeded(maximumAge: 6 * 3600)
            }
        case .background:
            AppLog.shared.debug("app", "background")
            ControllerRumble.shared.stop()
        default:
            break
        }
    }
}
