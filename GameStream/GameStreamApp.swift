import SwiftUI

@main
@MainActor
struct GameStreamApp: App {
    @StateObject private var session: SessionStore

    init() {
        _session = StateObject(wrappedValue: SessionStore())
        BetterXCloudInjector.shared.preload()
        ControllerRumble.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            FreshAppRoot()
                .environmentObject(session)
        }
    }
}
