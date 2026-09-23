import Foundation
import Combine
import UIKit

/// Opt-in diagnostics subsystem (iOS-only).
/// Queues sanitized events locally and uploads asynchronously to the controlled
/// Supabase Edge Function. Never logs passwords, cookies, auth tokens,
/// page HTML, or search query text.
@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    @Published var isOptedIn: Bool {
        didSet {
            UserDefaults.standard.set(isOptedIn, forKey: Keys.optIn)
            if isOptedIn {
                scheduleFlush()
            }
        }
    }

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastUploadStatus: String = ""

    private enum Keys {
        static let optIn = "GameStream.diagnostics.optIn.v1"
        static let queue = "GameStream.diagnostics.queue.v1"
    }

    // Controlled upload path — Supabase Edge Function (already deployed & verified)
    private let endpoint = URL(string: "https://fswswvhpszebuxnloysy.supabase.co/functions/v1/game-diagnostics")!
    // Supabase publishable key + verified legacy anon JWT for diagnostics Edge Function
    private let supabasePublishableKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZzd3N3dmhwc3plYnV4bmxveXN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxNDk3ODcsImV4cCI6MjEwNTcyNTc4N30.AY761m_RqpQ7qFP-_FBvO2T2lrsbTn3oQ1-lOAB-Sfg"
    private let maxQueue = 40
    private var flushTask: Task<Void, Never>?

    private init() {
        self.isOptedIn = UserDefaults.standard.bool(forKey: Keys.optIn)
        self.pendingCount = loadQueue().count
    }

    // MARK: - Public API

    func record(event: String, properties: [String: String] = [:]) {
        guard isOptedIn else { return }
        let sanitized = sanitize(properties)
        var queue = loadQueue()
        let entry: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "event": event,
            "props": sanitized,
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "platform": "ios"
        ]
        queue.append(entry)
        if queue.count > maxQueue {
            queue = Array(queue.suffix(maxQueue))
        }
        saveQueue(queue)
        pendingCount = queue.count
        scheduleFlush()
    }

    func flushNow() {
        guard isOptedIn else { return }
        Task { await performUpload() }
    }

    func clearQueue() {
        UserDefaults.standard.removeObject(forKey: Keys.queue)
        pendingCount = 0
        lastUploadStatus = "cleared"
    }

    // MARK: - Sanitization (hard rules from handoff)

    private func sanitize(_ props: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        let blocked = ["password", "passwd", "cookie", "token", "auth", "jwt", "html", "query", "search", "secret", "key"]
        for (k, v) in props {
            let lower = k.lowercased()
            if blocked.contains(where: { lower.contains($0) }) { continue }
            let trimmed = String(v.prefix(120))
            out[k] = trimmed
        }
        return out
    }

    // MARK: - Queue persistence

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

    // MARK: - Async upload

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await performUpload()
        }
    }

    private func performUpload() async {
        let queue = loadQueue()
        guard !queue.isEmpty, isOptedIn else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "events": queue,
            "device": [
                "model": UIDevice.current.model,
                "system": UIDevice.current.systemVersion
            ]
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = httpBody

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                saveQueue([])
                pendingCount = 0
                lastUploadStatus = "ok \(http.statusCode)"
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastUploadStatus = "http \(code)"
            }
        } catch {
            lastUploadStatus = "error"
        }
    }
}
