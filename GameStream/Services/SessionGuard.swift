import Foundation
import UIKit

/// Watches the things that end a cloud gaming session badly: a hot phone, a
/// flat battery, and a session that was meant to be twenty minutes.
///
/// None of this is advice given once at launch. A stream is a sustained load,
/// and the phone's condition during minute forty is what matters.
@MainActor
final class SessionGuard: ObservableObject {
    static let shared = SessionGuard()

    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var batteryLevel: Double = 1
    @Published private(set) var isCharging = false
    /// Seconds left on the session limit, when one is set.
    @Published private(set) var remaining: TimeInterval?

    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var warnedAt: Set<String> = []
    private var limit: TimeInterval?
    private var startedAt: Date?
    /// Set once this guard has ended a session. Every ending condition is
    /// still true on the next tick, and without this the guard asked the
    /// coordinator to exit again every five seconds.
    private var ended = false

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        thermalState = ProcessInfo.processInfo.thermalState
        readBattery()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main) { _ in
                Task { @MainActor in SessionGuard.shared.thermalChanged() }
            })
    }

    // MARK: - Session lifetime

    func begin() {
        startedAt = Date()
        warnedAt.removeAll()
        ended = false
        // A phone that is already hot when the stream starts needs to be
        // treated as hot. Waiting for a change notification means the one
        // state that never announces itself is the one that matters.
        thermalState = ProcessInfo.processInfo.thermalState
        let minutes = AppSettings.shared.sessionLimitMinutes
        limit = minutes > 0 ? TimeInterval(minutes * 60) : nil
        remaining = limit
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.tick() }
            }
        }
    }

    func end() {
        ticker?.cancel()
        ticker = nil
        startedAt = nil
        limit = nil
        remaining = nil
        warnedAt.removeAll()
        ended = false
    }

    private func tick() {
        readBattery()
        checkBattery()
        checkThermal()

        guard let startedAt, let limit else { return }
        let left = limit - Date().timeIntervalSince(startedAt)
        remaining = max(0, left)

        if left <= 0 {
            endSession("Session limit reached. Ending the game.", key: "limit-end")
            return
        }
        if left <= 60 { warn("One minute left on your session limit.", key: "limit-1") }
        else if left <= 300 { warn("Five minutes left on your session limit.", key: "limit-5") }
    }

    // MARK: - Conditions

    private func thermalChanged() {
        thermalState = ProcessInfo.processInfo.thermalState
        checkThermal()
    }

    private func checkThermal() {
        guard AppSettings.shared.thermalGuard, startedAt != nil else { return }
        switch thermalState {
        case .serious:
            warn("The phone is getting hot. Dropping to 720p to cool down.",
                 key: "thermal-serious")
            StreamCoordinator.shared.reduceQuality(reason: "the phone is hot")
        case .critical:
            endSession("The phone is too hot to keep streaming. Ending the game.",
                       key: "thermal-critical")
        default:
            break
        }
    }

    private func readBattery() {
        let level = UIDevice.current.batteryLevel
        batteryLevel = level < 0 ? 1 : Double(level)
        isCharging = UIDevice.current.batteryState == .charging
            || UIDevice.current.batteryState == .full
    }

    private func checkBattery() {
        guard AppSettings.shared.batteryGuard, !isCharging else { return }
        if batteryLevel <= 0.05 {
            endSession("Battery is nearly flat. Ending the game so it saves your place.",
                       key: "battery-5")
        } else if batteryLevel <= 0.15 {
            warn("Battery is at \(Int(batteryLevel * 100))%. Plug in soon.", key: "battery-15")
        }
    }

    /// Says why, then ends the session exactly once.
    private func endSession(_ text: String, key: String) {
        guard !ended else { return }
        ended = true
        warn(text, key: key)
        ticker?.cancel()
        ticker = nil
        startedAt = nil
        StreamCoordinator.shared.exit()
    }

    /// Each warning is said once per session. Repeating it every five seconds
    /// would be noise, and noise gets ignored.
    private func warn(_ text: String, key: String) {
        guard !warnedAt.contains(key) else { return }
        warnedAt.insert(key)
        AppLog.shared.warn("session", text)
        StreamCoordinator.shared.show(notice: text)
    }

    var thermalDescription: String {
        switch thermalState {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Overheating"
        @unknown default: return "Unknown"
        }
    }
}
