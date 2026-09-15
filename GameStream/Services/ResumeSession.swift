import Foundation

extension SessionStore {
    private static let resumeOnOpenKey = "GameStream.resumeLastOnOpen"
    private static var didConsumeLaunchResume = false

    var resumeLastOnOpen: Bool {
        get { UserDefaults.standard.bool(forKey: Self.resumeOnOpenKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.resumeOnOpenKey)
            objectWillChange.send()
        }
    }

    /// Launch the most recently streamed title directly into Xbox Cloud.
    @discardableResult
    func resumeLastStream() -> Bool {
        guard let game = continueGame else { return false }
        playGame(game)
        return true
    }

    /// Optional one-shot resume when the signed-in app first appears.
    /// Deferred so first-frame Liquid Glass + hub layout never race a WKWebView load.
    func consumeLaunchResumeIfNeeded() {
        guard !Self.didConsumeLaunchResume else { return }
        Self.didConsumeLaunchResume = true
        guard resumeLastOnOpen, isSignedIn, !isStreaming, continueGame != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            guard self.resumeLastOnOpen, self.isSignedIn, !self.isStreaming, self.continueGame != nil else { return }
            _ = self.resumeLastStream()
        }
    }
}
