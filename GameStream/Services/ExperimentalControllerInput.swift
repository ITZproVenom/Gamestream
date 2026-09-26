import Foundation

/// A controller-rumble event emitted by the streaming layer.
///
/// This deliberately separates stream/protocol handling from the physical
/// controller backend, following the architecture used by native streaming
/// clients such as OpenNOW.
struct ControllerRumbleEvent: Sendable {
    let controllerID: Int
    let lowFrequency: Float
    let highFrequency: Float
    let leftTrigger: Float
    let rightTrigger: Float
    let durationMs: Double

    init(
        controllerID: Int = 0,
        lowFrequency: Float,
        highFrequency: Float,
        leftTrigger: Float = 0,
        rightTrigger: Float = 0,
        durationMs: Double
    ) {
        self.controllerID = controllerID
        self.lowFrequency = lowFrequency
        self.highFrequency = highFrequency
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.durationMs = durationMs
    }
}

/// Native controller input backend.
///
/// The WebRTC/WebView layer only emits ControllerRumbleEvent values. This
/// object owns the decision to deliver those events to the physical controller.
/// That keeps protocol parsing out of ControllerRumble and makes the backend
/// replaceable for future native streaming transports.
@MainActor
final class ExperimentalControllerInput {
    static let shared = ExperimentalControllerInput()

    private let rumble = ControllerRumble.shared
    private var running = false

    private init() {}

    func start() {
        guard !running else { return }
        running = true
        rumble.start()
    }

    func stop() {
        guard running else { return }
        running = false
        rumble.teardown()
    }

    func playRumble(_ event: ControllerRumbleEvent) {
        guard running else { return }

        rumble.play(
            leftMotorPercent: event.lowFrequency,
            rightMotorPercent: event.highFrequency,
            leftTriggerMotorPercent: event.leftTrigger,
            rightTriggerMotorPercent: event.rightTrigger,
            durationMs: event.durationMs
        )
    }

    func stopRumble() {
        rumble.play(
            leftMotorPercent: 0,
            rightMotorPercent: 0,
            leftTriggerMotorPercent: 0,
            rightTriggerMotorPercent: 0,
            durationMs: 0,
            force: true
        )
    }
}
