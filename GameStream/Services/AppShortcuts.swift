import AppIntents
import Foundation

/// Shortcuts and Siri support: "Play Halo on GameStream".
///
/// The intent resolves against the catalog the app already has, so it works
/// with whatever is currently on Game Pass rather than a hardcoded list.
struct PlayGameIntent: AppIntent {
    static var title: LocalizedStringResource = "Play a game"
    static var description = IntentDescription(
        "Starts an Xbox Cloud Gaming session for a game in your library."
    )
    static var openAppWhenRun = true

    @Parameter(title: "Game")
    var game: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingIntent.shared.request = .play(game)
        return .result()
    }
}

struct OpenLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open my library"
    static var description = IntentDescription("Opens your GameStream library.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingIntent.shared.request = .library
        return .result()
    }
}

struct ResumeLastGameIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume the last game"
    static var description = IntentDescription("Starts the game you played most recently.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Recents, not the activity log: the log only keeps sessions longer
        // than fifteen seconds, so "resume" could skip the game you just
        // started and quit.
        if let last = LibraryStore.shared.recents.first {
            PendingIntent.shared.request = .play(last.id)
        }
        return .result()
    }
}

/// An intent cannot reach the running interface directly, so it leaves the
/// request here and the root view picks it up when the app comes forward.
@MainActor
final class PendingIntent: ObservableObject {
    static let shared = PendingIntent()
    @Published var request: DeepLink.Action?
    private init() {}
}

struct GameStreamShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeLastGameIntent(),
            phrases: ["Resume my game in \(.applicationName)"],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: ["Open my \(.applicationName) library"],
            shortTitle: "Library",
            systemImageName: "square.grid.2x2.fill"
        )
    }
}
