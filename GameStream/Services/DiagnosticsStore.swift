import Foundation
import Combine
import UIKit

/// Opt-in analytics/diagnostics for GameStream.
/// Events are sanitized, queued locally, and uploaded to the controlled Supabase Edge Function.
@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    @Published var isOptedIn: Bool {
        didSet {
            UserDefaults.standard.set(isOptedIn, forKey: Keys.optIn)
            if isOptedIn {
                record(event: "opt_in")
                scheduleFlush()
            }
        }
    }

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastUploadStatus: String = ""

    private enum Keys {
        static let optIn = "GameStream.diagnostics.optIn.v2"
        static let queue = "GameStream.diagnostics.queue.v2"
    }

    private let endpoint = URL(string: "https://fswswvhpszebuxnloysy.supabase.co/functions/v1/game-diagnostics")!
    private let supabaseKey = "sb_publishable_DwjFOZ9KSncIkW283CpSvg_cENfoSq2"
    private let maxQueue = 100
    private var flushTask: Task<Void, Never>?

    private init() {
        isOptedIn = UserDefaults.standard.bool(forKey: Keys.optIn)
        pendingCount = loadQueue().count
    }

    func record(event: String, properties: [String: String] = [:]) {
        guard isOptedIn else { return }
        var queue = loadQueue()
        let safe = sanitize(properties)
        let entry: [String: Any] = [
            "event": event,
            "event_id": UUID().uuidString,
            "ts": ISO8601DateFormatter().string(from: Date()),
            "props": safe,
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "platform": "ios"
        ]
        queue.append(entry)
        if queue.count > maxQueue { queue = Array(queue.suffix(maxQueue)) }
        saveQueue(queue)
        pendingCount = queue.count
        scheduleFlush()
    }

    func flushNow() {
        guard isOptedIn else { return }
        flushTask?.cancel()
        flushTask = Task { await performUpload() }
    }

    func clearQueue() {
        flushTask?.cancel()
        UserDefaults.standard.removeObject(forKey: Keys.queue)
        pendingCount = 0
        lastUploadStatus = "cleared"
    }

    private func sanitize(_ properties: [String: String]) -> [String: String] {
        let blocked = ["password", "passwd", "cookie", "token", "auth", "jwt", "html", "query", "search", "secret", "key", "email", "username"]
        var output: [String: String] = [:]
        for (key, value) in properties {
            let lower = key.lowercased()
            guard !blocked.contains(where: { lower.contains($0) }) else { continue }
            output[key] = String(value.prefix(160))
        }
        return output
    }

    private func loadQueue() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: Keys.queue),
              let queue = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return queue
    }

    private func saveQueue(_ queue: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: queue) else { return }
        UserDefaults.standard.set(data, forKey: Keys.queue)
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await performUpload()
        }
    }

    private func performUpload() async {
        let queue = loadQueue()
        guard !queue.isEmpty, isOptedIn else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "events": queue,
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "platform": "ios",
            "ios_version": UIDevice.current.systemVersion,
            "device": [
                "model": UIDevice.current.model,
                "system": UIDevice.current.systemVersion
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = data

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (200...299).contains(status) {
                saveQueue([])
                pendingCount = 0
                lastUploadStatus = "Uploaded"
            } else {
                lastUploadStatus = "HTTP \(status)"
            }
        } catch {
            lastUploadStatus = "Network error"
        }
    }
}
