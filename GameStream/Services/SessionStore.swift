import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var accountLabel: String?

    func markSignedIn(as label: String = "Xbox Account") {
        self.accountLabel = label
        self.isSignedIn = true
    }

    func signOut() {
        isSignedIn = false
        accountLabel = nil
    }
}
