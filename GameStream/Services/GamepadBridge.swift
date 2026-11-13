import Foundation
import GameController

/// Mirrors the phone's controller into the streaming page as a Gamepad API device.
///
/// Apple's WKWebView does not hand an attached controller to the web page:
/// `navigator.getGamepads()` is empty no matter what is paired. Xbox's cloud
/// client asks the page for a controller before it starts a session and keeps
/// asking while one is missing - "Controller not detected", then the "Let's
/// get ready" dialog, then a chip in the header for the whole session.
///
/// The page is therefore given a gamepad it can see, and the state of the
/// real controller is pushed into it, so the buttons and sticks the player
/// presses arrive in the game. The pad's vibration actuator is part of the
/// same object, which is how the game's rumble requests reach the controller.
@MainActor
final class GamepadBridge {
    static let shared = GamepadBridge()

    /// The name of the controller the page is being shown, for the log.
    private(set) var controllerName: String = ""

    private var observers: [NSObjectProtocol] = []
    /// Pushes are coalesced: a controller reports every value it moves, and
    /// the page only needs to hear about it a few times a second.
    private var pendingPush = false
    private var lastPayload = ""
    /// The loop that keeps the page in step with the pad.
    private var pollTask: Task<Void, Never>?
    private let log = AppLog.shared

    private init() {}

    /// Starts mirroring the controller into the live player page.
    ///
    /// The page polls `navigator.getGamepads()` itself, so the state has to
    /// be pushed into it rather than waited for. Thirty times a second is
    /// more than enough for a game to feel direct and little enough to cost
    /// nothing.
    func attach() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.push(force: false)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        log.debug("controller", "the page is being kept in step with the controller")
    }

    func detach() {
        pollTask?.cancel()
        pollTask = nil
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect,
                                           object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { GamepadBridge.shared.controllerChanged() }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect,
                                           object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { GamepadBridge.shared.controllerChanged() }
        })
        controllerChanged()
    }

    /// A pad appeared or went away.
    func controllerChanged() {
        let controller = GCController.current ?? GCController.controllers().first
        controllerName = controller?.vendorName ?? ""
        let present = controller != nil
        log.info("controller", present
                 ? "the page will be shown a gamepad (\(controllerName))"
                 : "the page will be shown no gamepad")

        // Tell the page right away, so the site's own controller check has
        // something to find before it asks the player to connect one.
        push(force: true)
    }

    /// Called when the controller's state changed.
    func inputChanged() {
        push(force: false)
    }

    /// The current state of the pad, in the page's own terms.
    private func snapshot() -> (axes: [Double], buttons: [Bool]) {
        var buttons = [Bool](repeating: false, count: 17)
        var axes = [Double](repeating: 0, count: 4)
        guard let profile = (GCController.current ?? GCController.controllers().first)?.extendedProfile else {
            return (axes, buttons)
        }
        buttons[0] = profile.buttonA.pressed
        buttons[1] = profile.buttonB.pressed
        buttons[2] = profile.buttonX.pressed
        buttons[3] = profile.buttonY.pressed
        buttons[4] = profile.leftShoulder.pressed
        buttons[5] = profile.rightShoulder.pressed
        buttons[6] = profile.leftTrigger.value > 0.1
        buttons[7] = profile.rightTrigger.value > 0.1
        buttons[8] = profile.buttonMenu.pressed
        buttons[9] = profile.buttonOptions.pressed
        buttons[10] = profile.leftThumbstickButton.pressed
        buttons[11] = profile.rightThumbstickButton.pressed
        buttons[12] = profile.dpad.up.pressed
        buttons[13] = profile.dpad.down.pressed
        buttons[14] = profile.dpad.left.pressed
        buttons[15] = profile.dpad.right.pressed
        buttons[16] = profile.buttonHome.pressed
        axes[0] = Double(profile.leftThumbstick.xAxis.value)
        axes[1] = Double(profile.leftThumbstick.yAxis.value)
        axes[2] = Double(profile.rightThumbstick.xAxis.value)
        axes[3] = Double(profile.rightThumbstick.yAxis.value)
        return (axes, buttons)
    }

    private func push(force: Bool) {
        guard XboxWebView.Registry.shared.streamView != nil else { return }
        if pendingPush, !force { return }
        pendingPush = true

        // The pad in the page is the real one, mirrored. It is only present
        // while a controller is attached, so the page is never told about a
        // controller the player does not have.
        let connected = !GCController.controllers().isEmpty
        let state = snapshot()
        let payload: [String: Any] = [
            "connected": connected,
            "axes": state.axes,
            "buttons": state.buttons.map { $0 ? 1 : 0 }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        guard force || json != lastPayload else { pendingPush = false; return }
        lastPayload = json

        XboxWebView.Registry.shared.run("window.__gsGamepad && window.__gsGamepad(\(json));")
        pendingPush = false
    }
}
