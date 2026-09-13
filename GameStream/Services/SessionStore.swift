import Foundation
import Combine

/// Holds sign-in state for whichever cloud gaming backend the user connects.
@MainActor
final class SessionStore: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var accountLabel: String?
    @Published var library: [GameEntry] = []

    private let gameService = GameLibraryService()

    func signIn(provider: StreamProvider) async {
        // TEMP: bypassing real auth so the UI/streaming screen is reachable
        // for testing. Swap back to the real flow once ready.
        self.accountLabel = "Test Account"
        self.isSignedIn = true
        self.library = [
            GameEntry(id: "test-1", title: "Test Game", artURL: nil)
        ]
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
