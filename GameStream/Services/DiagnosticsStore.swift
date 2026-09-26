import Foundation
import Combine
import UIKit

/// Opt-in diagnostics + product analytics (iOS-only).
/// Queues sanitized events locally and uploads asynchronously to the controlled
/// Supabase Edge Function. Never logs passwords, cookies, auth tokens,
/// page HTML, or search query text.
///
/// Security: only the publishable/anon JWT is used. The service_role key must
/// never ship in the app — inserts go through `game-diagnostics` only.
@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    @Published var isOptedIn: Bool {
        didSet {
            UserDefaults.standard.set(isOptedIn, forKey: Keys.optIn)
            if isOptedIn {
                ensureSession()
                record(event: "opt_in", feature: "settings", properties: ["source": "settings"])
                scheduleFlush()
            }
        }
    }

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastUploadStatus: String = ""

    /// Stable for the current foreground session (regenerated after long background).
    private(set) var sessionId: String = ""

    private enum Keys {
        static let optIn = "GameStream.diagnostics.optIn.v1"
        static let queue = "GameStream.diagnostics.queue.v1"
        static let session = "GameStream.diagnostics.sessionId.v1"
    }

    private let endpoint = URL(string: "https://fswswvhpszebuxnloysy.supabase.co/functions/v1/game-diagnostics")!
    private let supabasePublishableKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZzd3N3dmhwc3plYnV4bmxveXN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxNDk3ODcsImV4cCI6MjEwNTcyNTc4N30.AY761m_RqpQ7qFP-_FBvO2T2lrsbTn3oQ1-lOAB-Sfg"
    private let maxQueue = 60
    private var flushTask: Task<Void, Never>?
    private var didLaunch = false
    private var backgroundedAt: Date?
    private var observers: [NSObjectProtocol] = []

    private init() {
        self.isOptedIn = UserDefaults.standard.bool(forKey: Keys.optIn)
        self.sessionId = UserDefaults.standard.string(forKey: Keys.session) ?? ""
        self.pendingCount = loadQueue().count
        if isOptedIn { ensureSession() }
        installSystemObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Session

    func ensureSession() {
        if sessionId.isEmpty {
            rotateSession(reason: "new")
        }
    }

    func rotateSession(reason: String) {
        sessionId = UUID().uuidString.lowercased()
        UserDefaults.standard.set(sessionId, forKey: Keys.session)
        if isOptedIn {
            record(event: "app_session_start", feature: "lifecycle", properties: ["reason": reason])
        }
    }

    // MARK: - Lifecycle helpers (call from App)

    func noteAppLaunch() {
        guard isOptedIn else { return }
        guard !didLaunch else { return }
        didLaunch = true
        ensureSession()
        record(event: "app_launch", feature: "lifecycle")
        record(event: "app_session_start", feature: "lifecycle", properties: ["reason": "launch"])
    }

    func noteForeground() {
        guard isOptedIn else { return }
        if let bg = backgroundedAt, Date().timeIntervalSince(bg) > 30 * 60 {
            rotateSession(reason: "resume_after_long_background")
        }
        backgroundedAt = nil
        record(event: "app_foreground", feature: "lifecycle")
    }

    func noteBackground() {
        guard isOptedIn else { return }
        backgroundedAt = Date()
        record(event: "app_background", feature: "lifecycle")
        scheduleFlush()
    }

    // MARK: - Public API

    func record(
        event: String,
        feature: String? = nil,
        properties: [String: String] = [:],
        durationMs: Double? = nil,
        gameId: String? = nil,
        gameTitle: String? = nil,
        errorCategory: String? = nil,
        errorCode: String? = nil
    ) {
        guard isOptedIn else { return }
        ensureSession()

        var props = sanitize(properties)
        if let durationMs { props["duration_ms"] = String(Int(durationMs.rounded())) }
        if let gameId, !gameId.isEmpty { props["game_id"] = String(gameId.prefix(64)) }
        if let gameTitle, !gameTitle.isEmpty { props["game_title"] = String(gameTitle.prefix(80)) }
        if let errorCategory, !errorCategory.isEmpty { props["error_category"] = String(errorCategory.prefix(64)) }
        if let errorCode, !errorCode.isEmpty { props["error_code"] = String(errorCode.prefix(64)) }

        let screen = UIScreen.main.bounds
        let entry: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "event": event,
            "event_id": UUID().uuidString.lowercased(),
            "session_id": sessionId,
            "props": props,
            "feature": feature as Any,
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "platform": "ios",
            "duration_ms": durationMs as Any,
            "game_id": gameId as Any,
            "error_category": errorCategory as Any,
            "screen_width": Double(screen.width),
            "screen_height": Double(screen.height)
        ].compactMapValues { value -> Any? in
            if value is NSNull { return nil }
            if case Optional<Any>.none = value as Any? { return nil }
            return value
        }

        var queue = loadQueue()
        queue.append(entry)
        if queue.count > maxQueue {
            queue = Array(queue.suffix(maxQueue))
        }
        saveQueue(queue)
        pendingCount = queue.count
        scheduleFlush()
    }

    func flushNow() {
        guard isOptedIn else {
            lastUploadStatus = "opt-in required"
            return
        }
        if loadQueue().isEmpty {
            record(event: "manual_upload", feature: "settings", properties: ["source": "settings"])
        }
        Task { await performUpload() }
    }

    func clearQueue() {
        UserDefaults.standard.removeObject(forKey: Keys.queue)
        pendingCount = 0
        lastUploadStatus = "cleared"
    }

    // MARK: - Sanitization

    private func sanitize(_ props: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        let blocked = ["password", "passwd", "cookie", "token", "auth", "jwt", "html", "secret", "authorization"]
        for (k, v) in props {
            let lower = k.lowercased()
            if blocked.contains(where: { lower.contains($0) }) { continue }
            // Never persist free-text search queries under any key name.
            if lower.contains("query") || lower == "q" || lower.contains("search_text") { continue }
            out[k] = String(v.prefix(120))
        }
        return out
    }

    // MARK: - Queue

    private func loadQueue() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: Keys.queue),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr
    }

    private func saveQueue(_ queue: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: queue) {
            UserDefaults.standard.set(data, forKey: Keys.queue)
        }
    }

    // MARK: - Upload

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await performUpload()
        }
    }

    private func performUpload() async {
        let queue = loadQueue()
        guard isOptedIn else {
            lastUploadStatus = "opt-in required"
            return
        }
        guard !queue.isEmpty else {
            lastUploadStatus = "nothing pending"
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let screen = UIScreen.main.bounds
        let body: [String: Any] = [
            "event_type": "diagnostic",
            "message": "batch",
            "platform": "ios",
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "screen_width": Double(screen.width),
            "screen_height": Double(screen.height),
            "events": queue,
            "device": [
                "model": UIDevice.current.model,
                "system": UIDevice.current.systemVersion
            ]
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            lastUploadStatus = "encode failed"
            return
        }
        request.httpBody = httpBody

        let expected = queue.count

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let ok = (json?["ok"] as? Bool) == true
            let inserted = (json?["inserted"] as? Int)
                ?? (json?["inserted"] as? NSNumber)?.intValue

            if (200...299).contains(code), ok {
                saveQueue([])
                pendingCount = 0
                if let inserted {
                    lastUploadStatus = inserted < expected
                        ? "ok \(code) · inserted \(inserted)/\(expected)"
                        : "ok \(code) · inserted \(inserted)"
                } else {
                    lastUploadStatus = "ok \(code)"
                }
            } else {
                let detail = String(data: data, encoding: .utf8).map { String($0.prefix(100)) } ?? ""
                lastUploadStatus = detail.isEmpty ? "http \(code)" : "http \(code) \(detail)"
            }
        } catch {
            lastUploadStatus = "error \(error.localizedDescription.prefix(60))"
        }
    }

    // MARK: - System observers

    private func installSystemObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.record(event: "memory_warning", feature: "performance")
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.noteBackground() }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.noteForeground() }
        })
    }
}

// MARK: - Dictionary helpers

private extension Dictionary where Key == String, Value == Any {
    func compactMapValues(_ transform: (Any) -> Any?) -> [String: Any] {
        var result: [String: Any] = [:]
        for (k, v) in self {
            if let mapped = transform(v) {
                result[k] = mapped
            }
        }
        return result
    }
}
