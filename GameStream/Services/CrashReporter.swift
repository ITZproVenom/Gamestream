import Foundation

/// Records why the last run ended, when it did not end the usual way.
///
/// GameStream installs as an unsigned IPA, so there is no App Store crash
/// reporting behind it and no Xcode attached when it dies on a real device.
/// Two of the three ways it can die are observable from inside the process:
/// an uncaught exception, which arrives with a readable reason and a
/// symbolicated stack, and a fatal signal, which arrives with almost nothing
/// but can still be written down before the process goes. The third -- the
/// system reclaiming the app for using too much memory, which is the real
/// risk during a long stream -- runs none of our code at all, so the best
/// available answer is a breadcrumb in the log beforehand and a missing
/// shutdown afterwards.
///
/// The report is written to a file so it survives the process, picked up on
/// the next launch, and scrubbed before anybody sees it.
enum CrashReporter {
    static var reportURL: URL { AppLog.directory.appendingPathComponent("crash.txt") }
    static var pendingURL: URL { AppLog.directory.appendingPathComponent("crash-pending.txt") }

    /// The signals worth catching. `SIGPIPE` is deliberately absent: a dropped
    /// socket is not a crash and should not be filed as one.
    private static let watched: [(number: Int32, label: String)] = [
        (SIGABRT, "SIGABRT (abort)"),
        (SIGSEGV, "SIGSEGV (bad memory access)"),
        (SIGBUS, "SIGBUS (bus error)"),
        (SIGILL, "SIGILL (illegal instruction)"),
        (SIGFPE, "SIGFPE (arithmetic error)"),
        (SIGTRAP, "SIGTRAP (Swift runtime failure)")
    ]

    // Everything the signal handler touches is prepared here, while it is
    // still safe to allocate. A signal handler that calls malloc on the way
    // down is a handler that sometimes deadlocks instead of reporting.
    private nonisolated(unsafe) static var handle: FileHandle?
    private nonisolated(unsafe) static var descriptor: Int32 = -1
    private nonisolated(unsafe) static var header: UnsafeMutablePointer<CChar>?
    private nonisolated(unsafe) static var labels: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    private nonisolated(unsafe) static var frames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    private nonisolated(unsafe) static var previousHandler: (@convention(c) (NSException) -> Void)?
    private nonisolated(unsafe) static var installed = false

    private static let frameLimit: Int32 = 64
    private static let slotCount = 32

    /// Call as early as possible, before anything else can fail.
    static func install() {
        guard !installed else { return }
        installed = true

        let manager = FileManager.default
        // A non-empty report can only have come from the previous run. It is
        // moved aside first so this run cannot append to somebody else's
        // crash, and so a second crash does not overwrite the evidence.
        let attributes = try? manager.attributesOfItem(atPath: reportURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        if size > 0 {
            try? manager.removeItem(at: pendingURL)
            try? manager.moveItem(at: reportURL, to: pendingURL)
        } else {
            try? manager.removeItem(at: reportURL)
        }

        _ = manager.createFile(atPath: reportURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: reportURL)
        descriptor = handle?.fileDescriptor ?? -1
        guard descriptor >= 0 else { return }

        header = strdup("GameStream \(AppInfo.fullVersionLine) on \(AppInfo.deviceLine)\n")
        let buffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(
            capacity: Int(frameLimit)
        )
        buffer.initialize(repeating: nil, count: Int(frameLimit))
        frames = buffer

        let slots = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(
            capacity: slotCount
        )
        slots.initialize(repeating: nil, count: slotCount)
        for entry in watched where entry.number > 0 && Int(entry.number) < slotCount {
            slots[Int(entry.number)] = strdup("\n=== \(entry.label) ===\n")
        }
        labels = slots

        previousHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.record(exception)
            CrashReporter.previousHandler?(exception)
        }

        let handler = signalHandler
        for entry in watched { _ = signal(entry.number, handler) }
    }

    /// Async-signal-safe on purpose: a pre-rendered header, a pre-rendered
    /// label, a pre-allocated frame buffer, and `backtrace_symbols_fd`, which
    /// is the one symbolising call documented not to allocate.
    private static let signalHandler: @convention(c) (Int32) -> Void = { number in
        let fd = CrashReporter.descriptor
        if fd >= 0 {
            if let header = CrashReporter.header { _ = write(fd, header, strlen(header)) }
            if number > 0, Int(number) < CrashReporter.slotCount,
               let label = CrashReporter.labels?[Int(number)] {
                _ = write(fd, label, strlen(label))
            }
            if let frames = CrashReporter.frames {
                let depth = backtrace(frames, CrashReporter.frameLimit)
                backtrace_symbols_fd(frames, depth, fd)
            }
            _ = fsync(fd)
        }
        // Hand the signal back so the system still produces its own record.
        _ = signal(number, SIG_DFL)
        _ = raise(number)
    }

    private static func record(_ exception: NSException) {
        var lines = [
            "GameStream \(AppInfo.fullVersionLine) on \(AppInfo.deviceLine)",
            "",
            "=== uncaught exception ===",
            exception.name.rawValue,
            Redaction.apply(exception.reason ?? "no reason given"),
            ""
        ]
        lines.append(contentsOf: exception.callStackSymbols)
        guard let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) else { return }
        try? handle?.write(contentsOf: data)
        try? handle?.synchronize()
    }

    // MARK: - Reading it back

    /// The crash from the previous run together with the tail of the log that
    /// led into it. Either half on its own rarely explains anything.
    static func pendingReport() -> String? {
        guard let crash = try? String(contentsOf: pendingURL, encoding: .utf8),
              !crash.isEmpty else { return nil }
        var text = crash
        if let log = AppLog.previousSessionLog() {
            text += "\n=== log before the crash ===\n" + log
        }
        return Redaction.apply(text)
    }

    /// A one-line summary for a settings row, without the stack.
    static var pendingSummary: String? {
        guard let crash = try? String(contentsOf: pendingURL, encoding: .utf8) else { return nil }
        let marker = crash.components(separatedBy: "\n").first {
            $0.hasPrefix("=== ")
        }
        guard let marker else { return nil }
        return marker.replacingOccurrences(of: "=== ", with: "")
            .replacingOccurrences(of: " ===", with: "")
    }

    static func clearPending() {
        try? FileManager.default.removeItem(at: pendingURL)
    }
}
