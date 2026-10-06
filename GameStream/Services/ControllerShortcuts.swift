import Foundation
import GameController

/// Opens GameStream's overlay from the controller.
///
/// The player's own controls are drawn over a web page that owns every touch
/// on the video, which is why reaching them needs a two-finger tap or the
/// grab handle at the top. Neither is any use to someone playing on a pad
/// across the room, so the View button can be asked to do it instead.
///
/// This observes the button rather than claiming it. The page still receives
/// the same input, so the game keeps whatever it does with View; this only
/// adds a listener alongside it. It deliberately uses
/// `pressedChangedHandler` on the one button rather than the whole pad's
/// `valueChangedHandler`, which the rumble test installs and clears for its
/// own purposes.
@MainActor
final class ControllerShortcuts {
    static let shared = ControllerShortcuts()

    private var observers: [NSObjectProtocol] = []
    private var started = false
    /// Two presses inside this window, so a single View press still belongs
    /// to the game.
    private static let doubleWindow: TimeInterval = 0.45
    private var lastPress: Date?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect,
                                           object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ControllerShortcuts.shared.install() }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect,
                                           object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ControllerShortcuts.shared.install() }
        })
        install()
    }

    func settingsChanged() { install() }

    private func install() {
        let enabled = AppSettings.shared.overlayButtonEnabled
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            guard enabled else {
                pad.buttonOptions?.pressedChangedHandler = nil
                continue
            }
            pad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pressed()
                }
            }
        }
        if enabled {
            AppLog.shared.debug("controller", "the View button will open the overlay")
        }
    }

    private func pressed() {
        guard StreamCoordinator.shared.phase == .playing else { return }
        let now = Date()
        if let last = lastPress, now.timeIntervalSince(last) <= Self.doubleWindow {
            lastPress = nil
            AppLog.shared.info("controller", "the View button opened the overlay")
            StreamCoordinator.shared.requestOverlay()
            return
        }
        lastPress = now
    }
}
