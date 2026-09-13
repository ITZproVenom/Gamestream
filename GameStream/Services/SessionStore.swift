import Foundation
import Combine

/// Holds sign-in state for whichever cloud gaming backend the user connects.
/// Modeled after OPN.Auth's session/account separation (MIT-licensed, OpenCloudGaming/OpenNOW-Mac),
/// adapted for a single iOS app target instead of a macOS package graph.
@MainActor
final class SessionStore: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var accountLabel: String?
    @Published var library: [GameEntry] = []

    private let gameService = GameLibraryService()

    func signIn(provider: StreamProvider) async {
        // Real sign-in hands off to the provider's own OAuth/web login flow
        // (a WKWebView-based auth session) — no credentials are handled in-app.
        let account = await gameService.authenticate(provider: provider)
        self.accountLabel = account
        self.isSignedIn = account != nil
        if isSignedIn {
            self.library = await gameService.fetchLibrary(provider: provider)
        }
    }

    func signOut() {
        isSignedIn = false
        accountLabel = nil
        library = []
    }
}

enum StreamProvider: String, CaseIterable, Identifiable {
    case geforceNow = "GeForce NOW"
    var id: String { rawValue }
}

struct GameEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let artURL: URL?
}
