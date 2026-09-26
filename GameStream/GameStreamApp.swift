import SwiftUI

@main
@MainActor
struct GameStreamApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: SessionStore

    init() {
        _session = StateObject(wrappedValue: SessionStore())
        BetterXCloudInjector.shared.preload()
        ControllerRumble.shared.start()
        DiagnosticsStore.shared.record(event: "app_launch")
    }

    var body: some Scene {
        WindowGroup {
            FreshAppRoot()
                .environmentObject(session)
        }
            .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                DiagnosticsStore.shared.record(event: "app_foreground")
            case .background:
                DiagnosticsStore.shared.record(event: "app_background")
                DiagnosticsStore.shared.flushNow()
            default:
                break
            }
        }
    }
}
