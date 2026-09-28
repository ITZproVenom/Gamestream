import Foundation
import GameController

/// Controller chords, so the pad can drive the app during a stream.
///
/// Reaching for the screen mid-game to open a menu is the thing a controller
/// is supposed to make unnecessary. These are chords rather than single
/// buttons: nothing here can fire during normal play by accident.
@MainActor
final class ControllerShortcuts: ObservableObject {
    static let shared = ControllerShortcuts()

    /// Held for this long before the action fires, so a brush does nothing.
    private static let holdSeconds: TimeInterval = 0.45

    private var started = false
    private var observers: [NSObjectProtocol] = []
    private var heldSince: [String: Date] = [:]
    private var firedFor: Set<String> = []

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect,
                                            object: nil, queue: .main) { _ in
            Task { @MainActor in ControllerShortcuts.shared.attachAll() }
        })
        attachAll()
    }

    private func attachAll() {
        for controller in GCController.controllers() { attach(controller) }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self] gamepad, _ in
            Task { @MainActor in self?.evaluate(gamepad) }
        }
    }

    /// Chords, all requiring both shoulder buttons so they cannot collide
    /// with in-game controls:
    ///   LB + RB + View   → the app's stream overlay
    ///   LB + RB + Menu   → the Xbox guide
    ///   LB + RB + A      → the enhancement menu
    ///   LB + RB + Y      → statistics
    private func evaluate(_ pad: GCExtendedGamepad) {
        guard AppSettings.shared.controllerShortcuts else { return }
        guard StreamCoordinator.shared.phase == .playing else { return }

        let modifier = pad.leftShoulder.isPressed && pad.rightShoulder.isPressed
        guard modifier else {
            heldSince.removeAll()
            firedFor.removeAll()
            return
        }

        check("overlay", pressed: pad.buttonOptions?.isPressed == true) {
            StreamCoordinator.shared.requestOverlay()
        }
        check("guide", pressed: pad.buttonMenu.isPressed) {
            StreamCoordinator.shared.pressGuide()
        }
        check("enhancements", pressed: pad.buttonA.isPressed) {
            StreamCoordinator.shared.openEnhancementMenu()
        }
        check("stats", pressed: pad.buttonY.isPressed) {
            AppSettings.shared.showStreamStats.toggle()
        }
    }

    private func check(_ key: String, pressed: Bool, action: () -> Void) {
        guard pressed else {
            heldSince[key] = nil
            firedFor.remove(key)
            return
        }
        guard !firedFor.contains(key) else { return }
        let since = heldSince[key] ?? Date()
        heldSince[key] = since
        guard Date().timeIntervalSince(since) >= Self.holdSeconds else { return }
        firedFor.insert(key)
        AppLog.shared.info("controller", "shortcut: \(key)")
        action()
    }
}
