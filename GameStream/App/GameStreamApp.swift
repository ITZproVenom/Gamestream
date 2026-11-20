import SwiftUI
import UIKit
import CoreSpotlight

/// Keeps the one observer the app needs, and replaces it rather than
/// adding a second one when the app starts its work again.
@MainActor
final class MemoryWarningObserver {
    private var observer: NSObjectProtocol?

    func install() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AppLog.shared.warn("app", "the system warned about memory"
                                   + (StreamCoordinator.shared.phase.isActive
                                      ? " during a stream" : ""))
            }
        }
    }
}

@main
struct GameStreamApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var auth = XboxAuth.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var catalog = Catalog.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var stream = StreamCoordinator.shared
    @StateObject private var rumble = ControllerRumble.shared
    /// Bumped when the catalogue's market changes, so the hidden page is
    /// asked again. The market the app reads its own list from is the
    /// phone's, but the live list - the one with the titles outside the
    /// subscription - is the service's answer, and that follows the market.
    @State private var catalogueReloadToken = 0

    init() {
        // Before anything else, so the first thing that can fail is already
        // being watched.
        CrashReporter.install()
    }

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
                        // The catalogue lags behind what the cloud can play,
                        // so a title that is not in it can still be started
                        // by its product id.
                        let direct = DirectLaunch.game(forID: identifier)
                        AppLog.shared.info("deeplink", "playing \(direct.title) by its product id")
                        stream.play(direct)
                        return
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
            guard let game = DeepLink.game(for: identifier, in: catalog) else {
                // Opening from Spotlight on a cold start used to do nothing
                // at all: the catalog was empty, there was no match, and the
                // tap was dropped without a word.
                AppLog.shared.warn("deeplink", "no game matches \(identifier) yet; "
                                   + "waiting for the catalogue")
                Task {
                    if catalog.games.isEmpty { await catalog.refresh() }
                    guard let found = DeepLink.game(for: identifier, in: catalog) else {
                        AppLog.shared.warn("deeplink", "no game matches \(identifier)")
                        return
                    }
                    RootView.Navigator.shared.show(found)
                }
                return
            }
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
                // Xbox's own cloud list, read in the background. The
                // subscription feed the app uses leaves out anything
                // outside the subscription, so a title that launched
                // yesterday is missing from the catalogue and cannot be
                // started from the app at all. The page is hidden and takes
                // no touches; all that is wanted is what it lists.
                .background {
                    XboxWebView(
                        role: .cloudCatalogue,
                        url: URL(string: "https://play.xbox.com/")!,
                        reloadToken: catalogueReloadToken,
                        onCloudCatalogue: { games in
                            CloudCatalogue.shared.absorb(games)
                        }
                    )
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
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
                .onChange(of: settings.catalogRegion) { _, _ in
                    // The catalogue the app shows is the phone's own
                    // market, but the live list is the service's answer,
                    // and the answer follows the market that was asked
                    // for. Without this the change did nothing until the
                    // app was opened again.
                    catalogueReloadToken &+= 1
                    Task { await catalog.refresh() }
                }
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
    /// The memory-warning observer.
    ///
    /// It is kept in a box rather than in a property of the app itself,
    /// because the app is a struct: a struct cannot change its own stored
    /// properties from a method without mutating itself, and the method is
    /// not called on a mutable copy.
    private let memoryWarning = MemoryWarningObserver()

    private func startUp() async {
        AppLog.shared.info("app", "GameStream \(AppInfo.versionLine) starting")
        if let summary = CrashReporter.pendingSummary {
            AppLog.shared.error("app", "the previous run ended in \(summary); "
                                + "the report is in Settings, Diagnostics")
        }
        // The app is most likely to be reclaimed for memory mid-stream, and
        // that death runs no code of ours. A warning beforehand is the only
        // trace left, so it goes in the log rather than being ignored.
        // The observer is kept and replaced rather than added: the start-up
        // can run more than once when the scene is rebuilt, and each memory
        // warning would then be written to the log once per time it had
        // been added.
        memoryWarning.install()
        UIApplication.shared.isIdleTimerDisabled = settings.keepAwake
        rumble.start()
        Connectivity.shared.start()
        ControllerShortcuts.shared.start()
        GamepadBridge.shared.start()

        async let session = auth.refresh(reason: "launch")
        async let script: Void = BetterXCloud.shared.refreshIfNeeded()
        _ = await (session, script)

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
            GamepadBridge.shared.attach()
            Connectivity.shared.start()
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
            // Nothing is being watched while the app is in the background,
            // so the controller does not need to be read at all.
            GamepadBridge.shared.detach()
            Connectivity.shared.stop()
        default:
            break
        }
    }
}
