import Foundation
import Combine
import GameController

/// Detects a connected physical controller and surfaces D-pad / face-button
/// presses to the SwiftUI layer so the native UI (tab bar, actions) can be
/// driven like a console menu. GameController is only touched from `start()`
/// (never at process launch), every failure is swallowed, and presses are
/// delivered on the main actor.
@MainActor
final class ControllerManager: ObservableObject {
    static let shared = ControllerManager()

    /// True while at least one controller is connected.
    @Published private(set) var isConnected = false

    /// Set once by the UI. Called on the main actor for each button press
    /// while the app is not streaming (a stream hands input to the game page).
    var onPress: ((Press) -> Void)?

    enum Press {
        case up, down, left, right
        case lb, rb
        case a, b, x, y
        case menu
        case stickLeft, stickRight, stickUp, stickDown
    }

    private var controllers: [GCController] = []
    private var attached = Set<ObjectIdentifier>()
    private var observersRegistered = false

    func start() {
        ensureObservers()
        refresh()
    }

    private func ensureObservers() {
        guard !observersRegistered else { return }
        observersRegistered = true
        let center = NotificationCenter.default
        _ = center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        _ = center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let connected = GCController.controllers()
        controllers = connected
        isConnected = !connected.isEmpty
        attached = attached.filter { id in
            connected.contains { ObjectIdentifier($0) == id }
        }
        for controller in connected {
            attach(controller)
        }
    }

    private func attach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        guard !attached.contains(id), let pad = controller.extendedGamepad else { return }
        attached.insert(id)

        let dpad = pad.dpad
        dpad.up.pressedChangedHandler = pressHandler(.up)
        dpad.down.pressedChangedHandler = pressHandler(.down)
        dpad.left.pressedChangedHandler = pressHandler(.left)
        dpad.right.pressedChangedHandler = pressHandler(.right)

        pad.buttonA.pressedChangedHandler = pressHandler(.a)
        pad.buttonB.pressedChangedHandler = pressHandler(.b)
        pad.buttonX.pressedChangedHandler = pressHandler(.x)
        pad.buttonY.pressedChangedHandler = pressHandler(.y)
        pad.buttonMenu.pressedChangedHandler = pressHandler(.menu)

        // LB/RB cycle the top-level tabs.
        pad.leftShoulder.pressedChangedHandler = pressHandler(.lb)
        pad.rightShoulder.pressedChangedHandler = pressHandler(.rb)

        // Both sticks drive in-content game navigation (edge-triggered: pull
        // past the threshold fires once, then a recenter is required).
        pad.leftThumbstick.valueChangedHandler = stickHandler(StickLatch())
        pad.rightThumbstick.valueChangedHandler = stickHandler(StickLatch())
    }

    private final class StickLatch {
        var engaged = false
    }

    private func stickHandler(_ latch: StickLatch) -> (GCControllerDirectionPad, Float, Float) -> Void {
        { [weak self] _, xValue, yValue in
            guard let self else { return }
            let x = Float(xValue), y = Float(yValue)
            if latch.engaged {
                if abs(x) < 0.25 && abs(y) < 0.25 { latch.engaged = false }
                return
            }
            guard abs(x) >= 0.55 || abs(y) >= 0.55 else { return }
            latch.engaged = true
            let press: Press
            if abs(x) > abs(y) {
                press = x > 0 ? .stickRight : .stickLeft
            } else {
                press = y > 0 ? .stickDown : .stickUp
            }
            self.emit(press)
        }
    }

    private func pressHandler(_ press: Press) -> (GCControllerButtonInput, Float, Bool) -> Void {
        { [weak self] _, _, pressed in
            if pressed { self?.emit(press) }
        }
    }

    private func emit(_ press: Press) {
        Task { @MainActor in
            self.onPress?(press)
        }
    }
}