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
        let controller = GCController.current ?? GCController.controllers().first
        guard let pad = controller?.extendedGamepad else { return (axes, buttons) }
        buttons[0] = pad.buttonA.isPressed
        buttons[1] = pad.buttonB.isPressed
        buttons[2] = pad.buttonX.isPressed
        buttons[3] = pad.buttonY.isPressed
        buttons[4] = pad.leftShoulder.isPressed
        buttons[5] = pad.rightShoulder.isPressed
        buttons[6] = pad.leftTrigger.value > 0.1
        buttons[7] = pad.rightTrigger.value > 0.1
        buttons[8] = pad.buttonMenu.isPressed
        buttons[9] = pad.buttonOptions?.isPressed ?? false
        buttons[10] = pad.leftThumbstickButton?.isPressed ?? false
        buttons[11] = pad.rightThumbstickButton?.isPressed ?? false
        buttons[12] = pad.dpad.up.isPressed
        buttons[13] = pad.dpad.down.isPressed
        buttons[14] = pad.dpad.left.isPressed
        buttons[15] = pad.dpad.right.isPressed
        buttons[16] = pad.buttonHome?.isPressed ?? false
        axes[0] = Double(pad.leftThumbstick.xAxis.value)
        axes[1] = Double(pad.leftThumbstick.yAxis.value)
        axes[2] = Double(pad.rightThumbstick.xAxis.value)
        axes[3] = Double(pad.rightThumbstick.yAxis.value)
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
