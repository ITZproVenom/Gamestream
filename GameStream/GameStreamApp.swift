import SwiftUI

@main
@MainActor
struct GameStreamApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            FreshAppRoot()
                .environmentObject(session)
        }
    }
}
