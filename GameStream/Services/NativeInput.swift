//  NativeInput.swift
//  GameStream
//
//  The controller half of the native player. The stream service speaks a
//  small binary protocol over the "input" data channel: little endian,
//  fixed header, one report per bit of a type mask. This file writes the
//  reports we send (client metadata, gamepad) and reads the two we care
//  about coming back (vibration, server video size).

import Foundation
import GameController

// MARK: - Wire format

/// Which reports a packet carries. The service reads this mask first and
/// then walks the payload in bit order, so the writer must keep that order.
struct XCloudReportType: OptionSet {
    let rawValue: UInt16

    static let metadata       = XCloudReportType(rawValue: 1 << 0)
    static let gamepad        = XCloudReportType(rawValue: 1 << 1)
    static let pointer        = XCloudReportType(rawValue: 1 << 2)
    static let clientMetadata = XCloudReportType(rawValue: 1 << 3)
    static let serverMetadata = XCloudReportType(rawValue: 1 << 4)
    static let mouse          = XCloudReportType(rawValue: 1 << 5)
    static let keyboard       = XCloudReportType(rawValue: 1 << 6)
    static let vibration      = XCloudReportType(rawValue: 1 << 7)
    static let sensor         = XCloudReportType(rawValue: 1 << 8)
}

/// The button mask. These are the service's bit positions, not Apple's and
/// not XInput's, so they are written out rather than derived.
struct XCloudButtons: OptionSet {
    let rawValue: UInt16

    static let nexus         = XCloudButtons(rawValue: 1 << 1)
    static let menu          = XCloudButtons(rawValue: 1 << 2)
    static let view          = XCloudButtons(rawValue: 1 << 3)
    static let a             = XCloudButtons(rawValue: 1 << 4)
    static let b             = XCloudButtons(rawValue: 1 << 5)
    static let x             = XCloudButtons(rawValue: 1 << 6)
    static let y             = XCloudButtons(rawValue: 1 << 7)
    static let dpadUp        = XCloudButtons(rawValue: 1 << 8)
    static let dpadDown      = XCloudButtons(rawValue: 1 << 9)
    static let dpadLeft      = XCloudButtons(rawValue: 1 << 10)
    static let dpadRight     = XCloudButtons(rawValue: 1 << 11)
    static let leftShoulder  = XCloudButtons(rawValue: 1 << 12)
    static let rightShoulder = XCloudButtons(rawValue: 1 << 13)
    static let leftThumb     = XCloudButtons(rawValue: 1 << 14)
    static let rightThumb    = XCloudButtons(rawValue: 1 << 15)
}

/// One sampled controller. Sticks are -1...1 with y up, triggers 0...1,
/// exactly as GameController reports them; the packet writer does the
/// inversion and the scaling.
struct XCloudGamepadFrame: Equatable {
    var index: UInt8 = 0
    var buttons: XCloudButtons = []
    var leftX: Float = 0
    var leftY: Float = 0
    var rightX: Float = 0
    var rightY: Float = 0
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0

    static func idle(index: UInt8) -> XCloudGamepadFrame {
        XCloudGamepadFrame(index: index)
    }

    static func == (a: XCloudGamepadFrame, b: XCloudGamepadFrame) -> Bool {
        a.index == b.index && a.buttons.rawValue == b.buttons.rawValue
            && a.leftX == b.leftX && a.leftY == b.leftY
            && a.rightX == b.rightX && a.rightY == b.rightY
            && a.leftTrigger == b.leftTrigger && a.rightTrigger == b.rightTrigger
    }
}

/// A vibration order from the game.
struct XCloudVibration {
    var gamepadIndex: UInt8
    var left: Float
    var right: Float
    var leftTrigger: Float
    var rightTrigger: Float
    var durationMs: UInt16
    var delayMs: UInt16
    var repeatCount: UInt8
}

enum XCloudInputPacket {
    /// 2 bytes of report mask, 4 of sequence, 8 of timestamp.
    static let headerSize = 14

    /// Sent once when the channel opens. Without it the service never
    /// starts reading gamepad reports, so this is not optional.
    static func clientMetadata(sequence: UInt32, maxTouchPoints: UInt8 = 0) -> Data {
        var packet = header(.clientMetadata, sequence: sequence, payload: 1)
        packet[headerSize] = maxTouchPoints
        return packet
    }

    /// One packet holding every controller that changed since the last flush.
    static func gamepad(sequence: UInt32, frames: [XCloudGamepadFrame]) -> Data {
        guard !frames.isEmpty else { return Data() }
        let body = encode(frames)
        var packet = header(.gamepad, sequence: sequence, payload: body.count)
        packet.replaceSubrange(headerSize..<(headerSize + body.count), with: body)
        return packet
    }

    /// 1 byte of count, then 23 per controller.
    private static func encode(_ frames: [XCloudGamepadFrame]) -> Data {
        var data = Data(count: 1 + frames.count * 23)
        data[0] = UInt8(min(frames.count, 255))
        var at = 1
        for frame in frames.prefix(255) {
            data[at] = frame.index
            at += 1
            data.writeLittle(frame.buttons.rawValue, at: at); at += 2
            // Y is sent pointing down, which is the opposite of what
            // GameController hands us.
            data.writeLittle(axis(frame.leftX), at: at);   at += 2
            data.writeLittle(axis(-frame.leftY), at: at);  at += 2
            data.writeLittle(axis(frame.rightX), at: at);  at += 2
            data.writeLittle(axis(-frame.rightY), at: at); at += 2
            data.writeLittle(trigger(frame.leftTrigger), at: at);  at += 2
            data.writeLittle(trigger(frame.rightTrigger), at: at); at += 2
            // Physicality: this is a real pad, not an on-screen one. The
            // second field really is big endian here.
            data.writeLittle(UInt32(1), at: at); at += 4
            data.writeBig(UInt32(1), at: at);    at += 4
        }
        return data
    }

    /// A vibration report: type, padding, rumble kind, pad index, then the
    /// four motors as percentages.
    static func vibration(from data: Data) -> XCloudVibration? {
        guard data.count >= 13 else { return nil }
        let type: UInt16 = data.readLittle(at: 0)
        guard XCloudReportType(rawValue: type).contains(.vibration) else { return nil }
        // Rumble kind 0 is the four motor rumble; nothing else is defined.
        guard data[2] == 0 else { return nil }
        return XCloudVibration(gamepadIndex: data[3],
                               left: Float(data[4]) / 100,
                               right: Float(data[5]) / 100,
                               leftTrigger: Float(data[6]) / 100,
                               rightTrigger: Float(data[7]) / 100,
                               durationMs: data.readLittle(at: 8),
                               delayMs: data.readLittle(at: 10),
                               repeatCount: data[12])
    }

    /// The service's video size, which arrives on the same channel. Height
    /// comes first.
    static func serverSize(from data: Data) -> (width: UInt32, height: UInt32)? {
        guard data.count >= 10 else { return nil }
        let type: UInt16 = data.readLittle(at: 0)
        guard XCloudReportType(rawValue: type).contains(.serverMetadata) else { return nil }
        let height: UInt32 = data.readLittle(at: 2)
        let width: UInt32 = data.readLittle(at: 6)
        return (width, height)
    }

    private static func header(_ type: XCloudReportType,
                               sequence: UInt32,
                               payload: Int) -> Data {
        var data = Data(count: headerSize + payload)
        data.writeLittle(type.rawValue, at: 0)
        data.writeLittle(sequence, at: 2)
        data.writeLittle(Double(Int64(ProcessInfo.processInfo.systemUptime * 1000)), at: 6)
        return data
    }

    private static func axis(_ value: Float) -> Int16 {
        Int16(max(-1, min(1, value)) * 32767)
    }

    private static func trigger(_ value: Float) -> UInt16 {
        UInt16(max(0, min(1, value)) * 65535)
    }
}

private extension Data {
    mutating func writeLittle(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    mutating func writeLittle(_ value: Int16, at offset: Int) {
        writeLittle(UInt16(bitPattern: value), at: offset)
    }

    mutating func writeLittle(_ value: UInt32, at offset: Int) {
        for i in 0..<4 { self[offset + i] = UInt8((value >> (8 * UInt32(i))) & 0xFF) }
    }

    mutating func writeBig(_ value: UInt32, at offset: Int) {
        for i in 0..<4 { self[offset + i] = UInt8((value >> (8 * UInt32(3 - i))) & 0xFF) }
    }

    mutating func writeLittle(_ value: Double, at offset: Int) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes in
            for (i, byte) in bytes.enumerated() { self[offset + i] = byte }
        }
    }

    func readLittle<T: FixedWidthInteger>(at offset: Int) -> T {
        var value: T = 0
        let size = MemoryLayout<T>.size
        guard offset + size <= count else { return 0 }
        withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: (startIndex + offset)..<(startIndex + offset + size))
        }
        return T(littleEndian: value)
    }
}

// MARK: - Driver

/// Samples the attached controllers and pushes them down the input channel,
/// and turns the vibration reports that come back into real rumble.
///
/// Sampling is event driven — GameController tells us when something moved
/// — but sending is on a fixed 8 ms tick, so a pad that is being thrashed
/// cannot flood the channel and a pad that is still costs nothing.
@MainActor
final class NativeInputDriver: ObservableObject {
    /// True once the channel has accepted the opening metadata packet.
    @Published private(set) var isRunning = false
    /// What the player is holding, for the caption and diagnostics.
    @Published private(set) var controllerName: String?
    /// The size the service says it is encoding at.
    @Published private(set) var serverSize: (width: UInt32, height: UInt32)?
    /// Counts, so a silent input path can be told apart from an ignored one.
    @Published private(set) var packetsSent = 0
    @Published private(set) var vibrationsReceived = 0

    private var send: (@MainActor (Data) -> Bool)?
    private var sequence: UInt32 = 0
    private var pending: [UInt8: XCloudGamepadFrame] = [:]
    private var last: [UInt8: XCloudGamepadFrame] = [:]
    private var lastSentAt = Date.distantPast
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var attached: [ObjectIdentifier: UInt8] = [:]

    /// Resend the current state if nothing has changed for this long. The
    /// channel is reliable, but a stream that has been backgrounded and
    /// resumed can leave the service holding a stale frame.
    private let heartbeat: TimeInterval = 0.5

    func start(send: @escaping @MainActor (Data) -> Bool) {
        stop()
        self.send = send
        sequence = 0
        pending = [:]
        last = [:]

        let opening = XCloudInputPacket.clientMetadata(sequence: next())
        let accepted = send(opening)
        isRunning = accepted
        AppLog.shared.info("native", accepted
                           ? "input channel opened, client metadata sent"
                           : "input channel refused the opening packet")

        observe()
        for controller in GCController.controllers() { attach(controller) }

        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000)
                guard let self else { return }
                self.flush()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        // Let go of every button on the way out, or the game keeps holding
        // whatever was pressed when the stream ended.
        if send != nil {
            for index in attached.values {
                _ = send?(XCloudInputPacket.gamepad(sequence: next(),
                                                    frames: [.idle(index: index)]))
            }
        }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        attached = [:]
        pending = [:]
        last = [:]
        send = nil
        isRunning = false
        controllerName = nil
    }

    /// A message the service sent us on the input channel.
    func receive(_ data: Data) {
        if let size = XCloudInputPacket.serverSize(from: data) {
            if serverSize?.width != size.width || serverSize?.height != size.height {
                serverSize = size
                AppLog.shared.info("native", "server is encoding at \(size.width)x\(size.height)")
            }
            return
        }
        guard let order = XCloudInputPacket.vibration(from: data) else { return }
        vibrationsReceived += 1
        let duration = order.durationMs == 0 ? 80 : Double(order.durationMs)
        let fire = {
            ControllerRumble.shared.play(left: order.left,
                                         right: order.right,
                                         leftTrigger: order.leftTrigger,
                                         rightTrigger: order.rightTrigger,
                                         durationMs: duration)
        }
        if order.delayMs > 0 {
            let delay = Double(order.delayMs) / 1000
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { _ = fire() }
        } else {
            _ = fire()
        }
    }

    // MARK: - Sampling

    private func observe() {
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: .GCControllerDidConnect,
                                            object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.attach(controller) }
        })
        observers.append(centre.addObserver(forName: .GCControllerDidDisconnect,
                                            object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.detach(controller) }
        })
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let key = ObjectIdentifier(controller)
        if attached[key] == nil {
            attached[key] = UInt8(attached.count)
        }
        guard let index = attached[key] else { return }
        controllerName = controller.vendorName
        AppLog.shared.info("native", "controller \(index) attached: \(controller.vendorName ?? "unknown")")
        pad.valueChangedHandler = { [weak self] pad, _ in
            Task { @MainActor in self?.sample(pad, index: index) }
        }
        // Send the resting state straight away so the service knows the pad
        // exists before the first button is pressed.
        sample(pad, index: index)
    }

    private func detach(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        guard let index = attached.removeValue(forKey: key) else { return }
        AppLog.shared.info("native", "controller \(index) disconnected")
        pending[index] = .idle(index: index)
        if attached.isEmpty { controllerName = nil }
    }

    private func sample(_ pad: GCExtendedGamepad, index: UInt8) {
        var frame = XCloudGamepadFrame(index: index)
        var buttons: XCloudButtons = []
        if pad.buttonA.isPressed { buttons.insert(.a) }
        if pad.buttonB.isPressed { buttons.insert(.b) }
        if pad.buttonX.isPressed { buttons.insert(.x) }
        if pad.buttonY.isPressed { buttons.insert(.y) }
        if pad.leftShoulder.isPressed { buttons.insert(.leftShoulder) }
        if pad.rightShoulder.isPressed { buttons.insert(.rightShoulder) }
        if pad.buttonMenu.isPressed { buttons.insert(.menu) }
        if pad.buttonOptions?.isPressed == true { buttons.insert(.view) }
        if pad.buttonHome?.isPressed == true { buttons.insert(.nexus) }
        if pad.leftThumbstickButton?.isPressed == true { buttons.insert(.leftThumb) }
        if pad.rightThumbstickButton?.isPressed == true { buttons.insert(.rightThumb) }
        if pad.dpad.up.isPressed { buttons.insert(.dpadUp) }
        if pad.dpad.down.isPressed { buttons.insert(.dpadDown) }
        if pad.dpad.left.isPressed { buttons.insert(.dpadLeft) }
        if pad.dpad.right.isPressed { buttons.insert(.dpadRight) }
        frame.buttons = buttons

        let dead = Float(0.06)
        func stick(_ value: Float) -> Float { abs(value) < dead ? 0 : value }
        frame.leftX = stick(pad.leftThumbstick.xAxis.value)
        frame.leftY = stick(pad.leftThumbstick.yAxis.value)
        frame.rightX = stick(pad.rightThumbstick.xAxis.value)
        frame.rightY = stick(pad.rightThumbstick.yAxis.value)
        // Some pads report the trigger as a button only. Treating a press
        // as full pull is better than a trigger that never fires.
        frame.leftTrigger = pad.leftTrigger.value > 0 ? pad.leftTrigger.value
            : (pad.leftTrigger.isPressed ? 1 : 0)
        frame.rightTrigger = pad.rightTrigger.value > 0 ? pad.rightTrigger.value
            : (pad.rightTrigger.isPressed ? 1 : 0)

        pending[index] = frame
    }

    // MARK: - Sending

    private func flush() {
        guard let send else { return }
        var frames: [XCloudGamepadFrame] = []
        for (index, frame) in pending where last[index] != frame {
            frames.append(frame)
            last[index] = frame
        }
        pending = [:]

        if frames.isEmpty {
            guard Date().timeIntervalSince(lastSentAt) > heartbeat,
                  !last.isEmpty else { return }
            frames = Array(last.values)
        }

        let packet = XCloudInputPacket.gamepad(sequence: next(), frames: frames)
        guard !packet.isEmpty else { return }
        if send(packet) {
            packetsSent += 1
            lastSentAt = Date()
        }
    }

    private func next() -> UInt32 {
        let value = sequence
        sequence &+= 1
        return value
    }
}
