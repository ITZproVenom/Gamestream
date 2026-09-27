import SwiftUI
import UIKit

@main
struct GameStreamApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var auth = XboxAuth.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var catalog = Catalog.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var stream = StreamCoordinator.shared
    @StateObject private var rumble = ControllerRumble.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(settings)
                .environmentObject(catalog)
                .environmentObject(library)
                .environmentObject(stream)
                .environmentObject(rumble)
                .task { await startUp() }
                .onChange(of: scenePhase) { _, phase in
                    handle(phase)
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

        async let session = auth.refresh(reason: "launch")
        async let script: Void = BetterXCloud.shared.refreshIfNeeded()
        _ = await (session, script)

        if auth.state.isSignedIn {
            await catalog.refresh()
        }
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            AppLog.shared.debug("app", "foreground")
            // Coming back from the background is exactly when a token is most
            // likely to have expired.
            Task { await auth.refresh(reason: "foreground") }
        case .background:
            AppLog.shared.debug("app", "background")
            ControllerRumble.shared.stop()
        default:
            break
        }
    }
}
