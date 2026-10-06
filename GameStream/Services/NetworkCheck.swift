import Foundation

/// A latency probe against Xbox's own front door, run before a game starts.
///
/// Cloud gaming fails in a specific way: the picture arrives, the input does
/// not keep up, and the player blames the game. Measuring first means the app
/// can say "this connection is going to feel bad" before ten minutes are lost
/// to finding that out the hard way.
@MainActor
final class NetworkCheck: ObservableObject {
    static let shared = NetworkCheck()

    struct Reading: Equatable, Sendable {
        var latencyMs: Int
        var spreadMs: Int
        var reachable: Bool
        var measuredAt: Date
        /// Which host was actually measured. Xbox's website and the machine
        /// that runs the game are not in the same place, and a reading is
        /// only worth as much as the thing it was taken against.
        var host: String

        /// The plain verdict a player actually needs.
        var verdict: String {
            guard reachable else { return "No route to Xbox right now." }
            switch latencyMs {
            case ..<40: return "Excellent — this should feel like local play."
            case ..<75: return "Good — fine for anything except twitch shooters."
            case ..<130: return "Usable, with noticeable input lag."
            default: return "Poor — expect lag that gets in the way."
            }
        }

        var isPoor: Bool { !reachable || latencyMs >= 130 || spreadMs > 60 }

        var detail: String {
            guard reachable else { return verdict }
            return "\(latencyMs) ms, ±\(spreadMs) ms against \(host). \(verdict)"
        }
    }

    @Published private(set) var latest: Reading?
    @Published private(set) var isChecking = false

    private static let fallbackProbe = URL(string: "https://www.xbox.com/play")!
    /// The account's own cloud region, once anything has signed in to the
    /// cloud service. This is the host that serves the stream, so it is the
    /// one worth timing.
    private var regionProbe: URL?
    /// Read from the one path monitor the app runs. This type used to start a
    /// second `NWPathMonitor` of its own and publish values from it that
    /// nothing ever read, which was a watcher running for the lifetime of the
    /// app for no one.
    var isOnline: Bool { Connectivity.shared.link != .unknown }
    var isExpensive: Bool { Connectivity.shared.isExpensive }

    private init() {}

    /// Remembered so later checks measure the streaming region rather than
    /// the website's CDN.
    func rememberRegion(baseURI: String) {
        guard let url = URL(string: baseURI), url.host != nil else { return }
        regionProbe = url.appendingPathComponent("v2/login/user")
    }

    /// Three HEAD requests, reported as the median and the spread.
    ///
    /// The spread matters as much as the number: a steady 90 ms plays better
    /// than one that swings between 30 and 200.
    @discardableResult
    func measure() async -> Reading {
        // A second caller while the first is still measuring would otherwise
        // run its own four requests and clear the flag from under the first.
        if isChecking {
            if let latest { return latest }
            return Reading(latencyMs: 0, spreadMs: 0, reachable: isOnline,
                           measuredAt: Date(), host: "a check already running")
        }
        isChecking = true
        defer { isChecking = false }

        var samples: [Int] = []
        let target = regionProbe ?? Self.fallbackProbe
        let host = target.host ?? "Xbox"
        var request = URLRequest(url: target)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // Four attempts, first discarded: the opening request pays for DNS
        // and the TLS handshake, which is setup cost rather than latency and
        // makes a good connection read as a mediocre one.
        for attempt in 0..<4 {
            let start = Date()
            do {
                _ = try await URLSession.shared.data(for: request)
                if attempt > 0 {
                    samples.append(Int(Date().timeIntervalSince(start) * 1000))
                }
            } catch {
                continue
            }
        }

        let reading: Reading
        if samples.isEmpty {
            reading = Reading(latencyMs: 0, spreadMs: 0, reachable: false,
                              measuredAt: Date(), host: host)
        } else {
            let sorted = samples.sorted()
            reading = Reading(latencyMs: sorted[sorted.count / 2],
                              spreadMs: (sorted.last ?? 0) - (sorted.first ?? 0),
                              reachable: true,
                              measuredAt: Date(), host: host)
        }
        latest = reading
        AppLog.shared.info("network", reading.reachable
                           ? "\(host): round trip \(reading.latencyMs) ms "
                             + "(spread \(reading.spreadMs) ms)"
                           : "\(host) was not reachable")
        return reading
    }
}
