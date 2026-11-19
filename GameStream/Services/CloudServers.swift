import Foundation
import UIKit

/// One of the cloud servers the account can be served by.
///
/// The list comes from Microsoft's own answer to the app's sign-in: it
/// says which servers exist for this account, and in which market. The
/// first label of the server's address is the region - "wus" for West US,
/// and so on - and that is what the session is created against.
struct CloudServer: Identifiable, Hashable, Sendable {
    let name: String
    let title: String
    let baseURL: URL?
    let isDefault: Bool

    var id: String { name }

    /// The short name the service uses for this server, taken from its
    /// address: "https://wus.core.gssv-play-prod.xboxlive.com" is "WUS".
    var shortName: String {
        guard let host = baseURL?.host else { return name.uppercased() }
        let label = host.split(separator: ".").first ?? ""
        return label.uppercased()
    }
}

/// The servers, how far away they are, and how long their queue is.
///
/// A queue is the one thing the service does not publish before a
/// session is created, so the estimate for each server is the one from
/// the last time a session was started there. It is kept per server and
/// shown as the last known figure rather than as a live one, because
/// pretending it is live would be a lie.
@MainActor
final class CloudServers: ObservableObject {
    static let shared = CloudServers()

    /// The servers the account can use, as the service listed them.
    @Published private(set) var servers: [CloudServer] = []
    /// How long each server took to answer, in milliseconds.
    @Published private(set) var pings: [String: Int] = [:]
    /// The last estimated wait for each server, in seconds.
    @Published private(set) var queues: [String: Int] = [:]
    /// The server the player picked. Empty means the service's own default.
    @Published var chosen: String = ""
    @Published private(set) var measuredAt: Date?

    private init() {}

    /// Forgets everything: the servers, the pings and the choice.
    ///
    /// The servers belong to an account. When it changes, they are not the
    /// account's any more, and a server that was picked for the old one
    /// would be asked for on behalf of the new one.
    func reset() {
        servers = []
        pings = [:]
        queues = [:]
        chosen = ""
        measuredAt = nil
    }

    /// Takes the server list from the service's answer.
    func absorb(_ regions: [[String: Any]]) {
        var parsed: [CloudServer] = []
        for region in regions {
            guard let name = region["name"] as? String, !name.isEmpty else { continue }
            let base = (region["baseUri"] as? String).flatMap { URL(string: $0) }
            let title = (region["displayName"] as? String) ?? name
            parsed.append(CloudServer(name: name, title: title,
                                      baseURL: base,
                                      isDefault: region["isDefault"] as? Bool ?? false))
        }
        guard !parsed.isEmpty else { return }
        // The service's own order is the order it prefers.
        servers = parsed
        AppLog.shared.info("servers", "\(parsed.count) cloud servers: "
                           + parsed.map(\.shortName).joined(separator: ", "))
        measure()
    }

    /// Times every server.
    ///
    /// The servers are asked at the same time, because the point of the
    /// list is to compare them: one after another would take as long as the
    /// slowest of them.
    func measure() {
        guard !servers.isEmpty else { return }
        let targets = servers.compactMap { server -> (String, URL)? in
            guard let url = server.baseURL else { return nil }
            return (server.name, url)
        }
        guard !targets.isEmpty else { return }
        Task {
            await withTaskGroup(of: (String, Int?).self) { group in
                for (name, url) in targets {
                    group.addTask {
                        let start = Date()
                        var request = URLRequest(url: url)
                        request.httpMethod = "HEAD"
                        request.timeoutInterval = 6
                        request.cachePolicy = .reloadIgnoringLocalCacheData
                        _ = try? await URLSession.shared.data(for: request)
                        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                        return (name, elapsed)
                    }
                }
                var results: [String: Int] = [:]
                for await (name, elapsed) in group {
                    if let elapsed { results[name] = elapsed }
                }
                await MainActor.run {
                    self.pings = results
                    self.measuredAt = Date()
                    AppLog.shared.info("servers", "measured "
                                       + results.map { "\($0.key): \($0.value)ms" }
                                       .joined(separator: ", "))
                }
            }
        }
    }

    /// Records the wait the service estimated for a session.
    func recordWait(seconds: Int, for name: String?) {
        guard seconds > 0 else { return }
        let key = name ?? servers.first(where: \.isDefault)?.name ?? ""
        guard !key.isEmpty else { return }
        queues[key] = seconds
    }

    /// The servers, best first.
    ///
    /// The ping matters most - a server on the other side of the world is
    /// no good however short its queue - and the queue breaks the ties.
    var ranked: [CloudServer] {
        let maxPing = max(pings.values.max() ?? 1, 1)
        let maxQueue = max(queues.values.max() ?? 1, 1)
        return servers.sorted { score($0, maxPing: maxPing, maxQueue: maxQueue)
            < score($1, maxPing: maxPing, maxQueue: maxQueue) }
    }

    private func score(_ server: CloudServer, maxPing: Int, maxQueue: Int) -> Double {
        let ping = Double(pings[server.name] ?? maxPing)
        let queue = Double(queues[server.name] ?? maxQueue)
        return 0.75 * ping / Double(maxPing) + 0.25 * queue / Double(maxQueue)
    }

    /// What the picker shows for one server.
    func queueText(for server: CloudServer) -> String {
        guard let seconds = queues[server.name] else { return "queue unknown" }
        if seconds < 60 { return "queue about \(seconds)s" }
        return "queue about \(seconds / 60) min"
    }

    func pingText(for server: CloudServer) -> String {
        guard let ping = pings[server.name] else { return "…" }
        return "\(ping) ms"
    }
}
