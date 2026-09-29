import Foundation
import Combine
import os

/// An in-app log the user can read and share.
///
/// GameStream ships as an unsigned IPA, so there is no crash reporter and no
/// Xcode console attached when something fails on a real device. Sign-in in
/// particular fails in ways that are invisible from the outside, so every
/// meaningful step records a line here and Settings can export the result.
@MainActor
final class AppLog: ObservableObject {
    static let shared = AppLog()

    enum Level: String, Codable, Sendable {
        case debug, info, warn, error

        var symbol: String {
            switch self {
            case .debug: return "ladybug"
            case .info: return "info.circle"
            case .warn: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }

    struct Entry: Identifiable, Hashable, Sendable {
        let id = UUID()
        let date: Date
        let level: Level
        let category: String
        let message: String

        var line: String {
            let stamp = Entry.formatter.string(from: date)
            return "\(stamp) [\(level.rawValue.uppercased())] \(category): \(message)"
        }

        private static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }

    /// Bounded so a long streaming session cannot grow the log without limit.
    private let limit = 500

    @Published private(set) var entries: [Entry] = []

    private let logger = Logger(subsystem: "com.gamestream.app", category: "app")

    private init() {}

    func callAsFunction(_ level: Level = .info, _ category: String, _ message: String) {
        record(level, category, message)
    }

    func record(_ level: Level = .info, _ category: String, _ message: String) {
        let entry = Entry(date: Date(), level: level, category: category, message: message)
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        switch level {
        case .debug: logger.debug("\(category, privacy: .public): \(message, privacy: .public)")
        case .info: logger.info("\(category, privacy: .public): \(message, privacy: .public)")
        case .warn: logger.warning("\(category, privacy: .public): \(message, privacy: .public)")
        case .error: logger.error("\(category, privacy: .public): \(message, privacy: .public)")
        }
    }

    func debug(_ category: String, _ message: String) { record(.debug, category, message) }
    func info(_ category: String, _ message: String) { record(.info, category, message) }
    func warn(_ category: String, _ message: String) { record(.warn, category, message) }
    func error(_ category: String, _ message: String) { record(.error, category, message) }

    func clear() { entries.removeAll() }

    /// Newest last, ready to paste into a bug report.
    ///
    /// `context` is whatever the caller knows about the state the log was
    /// taken in. A log on its own says what happened but not what the app
    /// was: which renderer, which controller, what the connection measured.
    func exportText(context: [String] = []) -> String {
        let header = [
            "GameStream diagnostics",
            "Version \(AppInfo.fullVersionLine)",
            "Device \(AppInfo.deviceLine)",
            "Exported \(Date().formatted(date: .abbreviated, time: .standard))",
            ""
        ]
        let state = context.isEmpty ? [] : (["State"] + context.map { "  " + $0 } + [""])
        return (header + state + entries.map(\.line)).joined(separator: "\n")
    }
}

enum AppInfo {
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// The commit the build came from, stamped by CI.
    static var commit: String {
        Bundle.main.infoDictionary?["GSCommit"] as? String ?? "dev"
    }

    /// Which release channel produced this build.
    static var channel: String {
        Bundle.main.infoDictionary?["GSChannel"] as? String ?? "dev"
    }

    static var versionLine: String { "\(shortVersion) (\(buildNumber))" }

    /// Version, build, channel and commit in one line, for Settings and for
    /// exported diagnostics. Knowing which build a report came from matters
    /// more than the marketing version on its own.
    static var fullVersionLine: String {
        "\(shortVersion) (\(buildNumber)) · \(channel) · \(commit)"
    }

    static var deviceLine: String {
        let info = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(info.majorVersion).\(info.minorVersion)"
    }
}
