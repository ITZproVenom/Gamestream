import Foundation
import Network

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
    }

    @Published private(set) var latest: Reading?
    @Published private(set) var isChecking = false

    private static let probe = URL(string: "https://www.xbox.com/play")!
    private let monitor = NWPathMonitor()
    @Published private(set) var isOnline = true
    @Published private(set) var isExpensive = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "gamestream.network"))
    }

    /// Three HEAD requests, reported as the median and the spread.
    ///
    /// The spread matters as much as the number: a steady 90 ms plays better
    /// than one that swings between 30 and 200.
    @discardableResult
    func measure() async -> Reading {
        if isChecking, let latest { return latest }
        isChecking = true
        defer { isChecking = false }

        var samples: [Int] = []
        var request = URLRequest(url: Self.probe)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        for _ in 0..<3 {
            let start = Date()
            do {
                _ = try await URLSession.shared.data(for: request)
                samples.append(Int(Date().timeIntervalSince(start) * 1000))
            } catch {
                continue
            }
        }

        let reading: Reading
        if samples.isEmpty {
            reading = Reading(latencyMs: 0, spreadMs: 0, reachable: false, measuredAt: Date())
        } else {
            let sorted = samples.sorted()
            reading = Reading(latencyMs: sorted[sorted.count / 2],
                              spreadMs: (sorted.last ?? 0) - (sorted.first ?? 0),
                              reachable: true,
                              measuredAt: Date())
        }
        latest = reading
        AppLog.shared.info("network", reading.reachable
                           ? "round trip \(reading.latencyMs) ms (spread \(reading.spreadMs) ms)"
                           : "Xbox was not reachable")
        return reading
    }
}
