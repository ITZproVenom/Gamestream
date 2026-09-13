import Foundation

/// Catalog + session lifecycle calls, structured after OPN.GameServices
/// (OpenCloudGaming/OpenNOW-Mac, MIT). The macOS package talks to GFN's
/// catalog/session endpoints directly from Swift; this port keeps the same
/// shape (authenticate -> fetch library -> start/stop session) but drives
/// auth through an in-app WKWebView OAuth sheet instead of macOS's
/// ASWebAuthenticationSession, since GFN has no public REST/auth SDK.
struct GameLibraryService {
    func authenticate(provider: StreamProvider) async -> String? {
        // Hook point: present WebAuthView(provider.loginURL) and capture the
        // resulting session cookie/token from the callback redirect.
        // Left unimplemented here — wire to your own WKWebView auth sheet.
        return nil
    }

    func fetchLibrary(provider: StreamProvider) async -> [GameEntry] {
        // Hook point: call the provider's catalog endpoint with the session
        // token captured above. Returns an empty library until wired up.
        return []
    }

    func startSession(gameId: String) async throws -> StreamSessionDescriptor {
        throw GameServiceError.notConfigured
    }

    func stopSession(_ descriptor: StreamSessionDescriptor) async {
        // Hook point: tear down the WebRTC session and notify the backend.
    }
}

struct StreamSessionDescriptor {
    let sessionId: String
    let signalingURL: URL
}

enum GameServiceError: Error {
    case notConfigured
}
