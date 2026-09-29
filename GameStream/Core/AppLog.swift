import Foundation
import Combine
import os

/// An in-app log the user can read and share.
///
/// GameStream ships as an unsigned IPA, so there is no crash reporter and no
/// Xcode console attached when something fails on a real device. Sign-in in
/// particular fails in ways that are invisible from the outside, so every
/// meaningful step records a line here and Settings can export the result.
///
/// Every line is also appended to a file, because the log worth reading is
/// the one from the run that died, and until now that one was thrown away
/// with the process.
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

    private var file: FileHandle?
    private var writtenBytes = 0

    private init() { openFile() }

    func callAsFunction(_ level: Level = .info, _ category: String, _ message: String) {
        record(level, category, message)
    }

    func record(_ level: Level = .info, _ category: String, _ message: String) {
        // Scrubbed on the way in rather than on the way out, so a token
        // cannot reach the screen, the file or the system log either.
        let entry = Entry(date: Date(), level: level, category: category,
                          message: Redaction.apply(message))
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        append(entry.line)
        switch level {
        case .debug: logger.debug("\(category, privacy: .public): \(entry.message, privacy: .public)")
        case .info: logger.info("\(category, privacy: .public): \(entry.message, privacy: .public)")
        case .warn: logger.warning("\(category, privacy: .public): \(entry.message, privacy: .public)")
        case .error: logger.error("\(category, privacy: .public): \(entry.message, privacy: .public)")
        }
    }

    func debug(_ category: String, _ message: String) { record(.debug, category, message) }
    func info(_ category: String, _ message: String) { record(.info, category, message) }
    func warn(_ category: String, _ message: String) { record(.warn, category, message) }
    func error(_ category: String, _ message: String) { record(.error, category, message) }

    func clear() {
        entries.removeAll()
        file?.truncateFile(atOffset: 0)
        writtenBytes = 0
    }

    // MARK: - Disk

    /// Where the log files live. Application Support rather than Caches: the
    /// system is free to empty Caches whenever it likes, which is exactly the
    /// wrong behaviour for the record of why the app stopped working.
    nonisolated static var directory: URL { cachedDirectory }

    /// Resolved once. It is asked for on every crash-report check, and
    /// creating a directory each time to answer is work for nothing.
    private nonisolated static let cachedDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL.temporaryDirectory
        var folder = base.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // No reason for a diagnostic log to travel in somebody's iCloud backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return folder
    }()

    nonisolated static var currentURL: URL { directory.appendingPathComponent("session.log") }
    nonisolated static var previousURL: URL { directory.appendingPathComponent("previous.log") }

    /// This run starts a fresh file and keeps one run of history, which is
    /// the run anybody asking "why did it crash" wants to see.
    private func openFile() {
        let manager = FileManager.default
        if manager.fileExists(atPath: Self.currentURL.path) {
            try? manager.removeItem(at: Self.previousURL)
            try? manager.moveItem(at: Self.currentURL, to: Self.previousURL)
        }
        _ = manager.createFile(atPath: Self.currentURL.path, contents: nil)
        file = try? FileHandle(forWritingTo: Self.currentURL)
    }

    private func append(_ line: String) {
        guard let file, let data = (line + "\n").data(using: .utf8) else { return }
        try? file.write(contentsOf: data)
        writtenBytes += data.count
        // A long session should not be able to fill the device. Rolling over
        // keeps the tail, which is the part that explains anything.
        if writtenBytes > 512_000 {
            try? file.close()
            self.file = nil
            openFile()
            writtenBytes = 0
        }
    }

    /// The tail of the previous run's log, for a crash report to carry.
    nonisolated static func previousSessionLog(lines: Int = 200) -> String? {
        guard let text = try? String(contentsOf: previousURL, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text.components(separatedBy: "\n").suffix(lines).joined(separator: "\n")
    }

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
        // Entries were scrubbed as they were recorded; the header and the
        // context come from elsewhere, so the whole thing goes through again.
        return Redaction.apply((header + state + entries.map(\.line))
            .joined(separator: "\n"))
    }
}

/// Takes anything credential-shaped out of text that is about to be written
/// down or shared.
///
/// A log is only shareable if sharing it is safe, and the interesting parts of
/// this app's log are full of things that look like secrets: Xbox tokens,
/// authorisation headers, the URLs a sign-in bounces through. The rules below
/// are deliberately blunt. Losing a bit of detail to a false positive costs a
/// second guess; leaking a live token costs an account.
enum Redaction {
    private struct Rule {
        let expression: NSRegularExpression
        let template: String

        init?(_ pattern: String, _ template: String) {
            guard let expression = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]
            ) else { return nil }
            self.expression = expression
            self.template = template
        }
    }

    private nonisolated(unsafe) static let rules: [Rule] = [
        // An Xbox Live authorisation header, which is the token itself.
        Rule(#"XBL3\.0 x=[^\s;'"]+"#, "XBL3.0 x=[redacted]"),
        // Anything shaped like a JSON web token.
        Rule(#"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}[A-Za-z0-9_\-\.]*"#, "[jwt]"),
        // A named secret and whatever follows it.
        Rule(#"((?:access|refresh|id|bearer|auth|session)?[_\-]?"#
             + #"(?:token|secret|password|passwd|key|code|uhs|userhash|cookie)"#
             + #"["']?\s*[=:]\s*["']?)[A-Za-z0-9._\-+/%]{6,}"#, "$1[redacted]"),
        Rule(#"(Authorization["']?\s*[=:]\s*["']?)[^\s,;"']+"#, "$1[redacted]"),
        // Email addresses are not secrets but they are not ours to share.
        Rule(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "[email]"),
        // Whatever is left that is long and opaque enough to be a token.
        Rule(#"\b[A-Za-z0-9+/_\-]{40,}={0,2}\b"#, "[redacted]")
    ].compactMap { $0 }

    static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for rule in rules {
            result = rule.expression.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.template
            )
        }
        return result
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
