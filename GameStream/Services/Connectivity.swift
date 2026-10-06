import Foundation
import Network
import Combine

/// What the device is connected through, watched rather than asked once.
///
/// This exists for one reason: the bitrate ceiling and the resolution are
/// negotiated into the session description when a stream is set up, so the
/// only moment they can be chosen is before a game launches. Knowing whether
/// that launch is about to happen over Wi-Fi or over a cellular plan is the
/// difference between a sensible default and a gigabyte of data spent by
/// accident.
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()

    enum Link: Equatable {
        case unknown
        case wifi
        case cellular
        case wired
        case other

        var title: String {
            switch self {
            case .unknown: return "Unknown"
            case .wifi: return "Wi-Fi"
            case .cellular: return "Cellular"
            case .wired: return "Wired"
            case .other: return "Other"
            }
        }
    }

    @Published private(set) var link: Link = .unknown
    /// Set by the system when the user has asked for less data to be used,
    /// which is a request worth honouring without being told twice.
    @Published private(set) var isConstrained = false
    @Published private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let link: Link
            if path.usesInterfaceType(.wifi) {
                link = .wifi
            } else if path.usesInterfaceType(.cellular) {
                link = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                link = .wired
            } else if path.status == .satisfied {
                link = .other
            } else {
                link = .unknown
            }
            let constrained = path.isConstrained
            let expensive = path.isExpensive
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.link != link {
                    AppLog.shared.info("network", "connected over \(link.title)")
                }
                self.link = link
                self.isConstrained = constrained
                self.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.gamestream.connectivity"))
    }

    /// Whether a launch right now would go over a metered link.
    var isMetered: Bool {
        link == .cellular || isConstrained || isExpensive
    }
}
