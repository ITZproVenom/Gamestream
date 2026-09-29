#if canImport(WebRTC)
import Foundation
import WebRTC

/// The native player's peer connection.
///
/// This is the part that replaces the website. The browser was never the
/// point — it was a way to get a WebRTC session without writing one. But
/// everything the app wants to do is on the other side of that boundary:
/// input timing, rumble packets, the touch overlay, the stats, the HUD. A
/// script injected into someone else's page can only ask; this can decide.
///
/// The session itself is provisioned by `XCloudSession`. What happens here is
/// the media negotiation that provisioning stops short of: build an offer,
/// hand it over, take the answer, trade candidates, and surface the tracks
/// and channels that come back.
@MainActor
final class NativeStreamPeer: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case negotiating(String)
        case connected
        case failed(String)
        case closed
    }

    @Published private(set) var state: State = .idle
    /// The remote video track, once there is one to render.
    @Published private(set) var videoTrack: RTCVideoTrack?
    /// Codecs the server actually offered, read from its answer.
    @Published private(set) var offeredCodecs: [String] = []

    /// One factory for the process. Building more than one is a documented
    /// way to get unpredictable behaviour out of libwebrtc.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    private var connection: RTCPeerConnection?
    /// Xbox names its channels. `input` carries controller state in and
    /// rumble out, which is the channel the whole rumble path depends on.
    private var inputChannel: RTCDataChannel?
    private var controlChannel: RTCDataChannel?
    private var messageChannel: RTCDataChannel?
    private var chatChannel: RTCDataChannel?
    private var pendingCandidates: [RTCIceCandidate] = []
    private var handle: XCloudSession.Handle?
    private var token: String?
    /// Candidates found after the first exchange still have to be handed
    /// over. Gathering is continual, and the candidate that actually works
    /// is often not one of the first: dropping everything after the opening
    /// round is a connection that fails for no visible reason.
    private var trickle: Task<Void, Never>?
    private var exchangedCandidates = 0

    /// Called with each rumble payload that arrives on the input channel, so
    /// the existing native rumble code can stay exactly as it is.
    var onRumble: (@MainActor (Data) -> Void)?

    /// True once the input channel is open in both directions. The driver
    /// waits for this rather than for video, because a picture arriving is
    /// no promise that the channel carrying the controller came up.
    @Published private(set) var inputReady = false

    // MARK: - Connecting

    func connect(handle: XCloudSession.Handle, token: String) async {
        // A retry asks the same object to connect again. Without this, the
        // previous peer connection stays alive and keeps gathering into the
        // same candidate list.
        if connection != nil { close() }
        self.handle = handle
        self.token = token
        state = .negotiating("Building the connection")

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.continualGatheringPolicy = .gatherContinually
        // No STUN. The service signals its own candidates over HTTP, and
        // pointing at Google's public server told a third party which
        // addresses this device streams from for no benefit at all.
        configuration.iceServers = []

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: nil)
        guard let peer = Self.factory.peerConnection(with: configuration,
                                                     constraints: constraints,
                                                     delegate: self) else {
            state = .failed("the peer connection could not be created")
            return
        }
        connection = peer

        // Receive-only media. The service decides what it sends; asking to
        // send would only add streams it has no use for.
        let receive = RTCRtpTransceiverInit()
        receive.direction = .recvOnly
        peer.addTransceiver(of: .video, init: receive)
        peer.addTransceiver(of: .audio, init: receive)

        // The channels have to exist in the offer, because the service reads
        // them from the description rather than opening them itself, and it
        // expects all four with these sub-protocols. Their stream ids are
        // SCTP's business: naming one while saying the channel is not
        // pre-negotiated is a contradiction, and the id we picked could
        // collide with whatever the stack assigned.
        messageChannel = channel(on: peer, label: "message", protocolName: "messageV1")
        controlChannel = channel(on: peer, label: "control", protocolName: "controlV1")
        inputChannel = channel(on: peer, label: "input", protocolName: "1.0")
        chatChannel = channel(on: peer, label: "chat", protocolName: "chatV1")

        do {
            state = .negotiating("Offering")
            let offer = try await peer.offer(for: constraints)
            let edited = RTCSessionDescription(type: offer.type,
                                               sdp: Self.prepare(offer.sdp))
            try await peer.setLocalDescription(edited)

            state = .negotiating("Waiting for the server")
            let answerText = try await XCloudSession.shared.exchangeOffer(
                edited.sdp, on: handle, token: token
            )
            guard let answerSDP = Self.sdp(fromExchange: answerText) else {
                state = .failed("the server's answer could not be read")
                return
            }
            offeredCodecs = Self.codecs(in: answerSDP)
            try await peer.setRemoteDescription(
                RTCSessionDescription(type: .answer, sdp: answerSDP)
            )

            state = .negotiating("Trading candidates")
            try await exchangeCandidates(on: peer)
        } catch let failure as XCloudSession.Failure {
            AppLog.shared.error("native", "negotiation failed: \(failure.errorDescription ?? "?")")
            state = .failed(failure.errorDescription ?? "negotiation failed")
        } catch {
            AppLog.shared.error("native", "negotiation failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    private func channel(on peer: RTCPeerConnection,
                         label: String,
                         protocolName: String,
                         ordered: Bool = true) -> RTCDataChannel? {
        let configuration = RTCDataChannelConfiguration()
        configuration.isOrdered = ordered
        // The service matches on the sub-protocol as well as the label.
        configuration.protocol = protocolName
        let created = peer.dataChannel(forLabel: label, configuration: configuration)
        created?.delegate = self
        return created
    }

    /// Hands over the candidates gathered so far and adds the server's.
    private func exchangeCandidates(on peer: RTCPeerConnection) async throws {
        guard let handle, let token else { return }
        // A short settle: gathering is continual, and sending an empty list
        // first only costs another round trip.
        try? await Task.sleep(nanoseconds: 700_000_000)

        let mine = Self.payload(for: pendingCandidates)
        exchangedCandidates = pendingCandidates.count
        AppLog.shared.debug("native", "handing over \(mine.count) candidate(s)")
        let response = try await XCloudSession.shared.exchangeCandidates(
            mine, on: handle, token: token
        )
        await add(Self.candidates(fromExchange: response), to: peer)
        startTrickling(on: peer)
    }

    private func add(_ candidates: [RTCIceCandidate], to peer: RTCPeerConnection) async {
        guard !candidates.isEmpty else { return }
        AppLog.shared.debug("native", "adding \(candidates.count) server candidate(s)")
        for candidate in candidates {
            try? await peer.add(candidate)
        }
    }

    private static func payload(for candidates: some Sequence<RTCIceCandidate>) -> [[String: Any]] {
        candidates.map { candidate in
            [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid ?? "0"
            ]
        }
    }

    /// Keeps handing over candidates as they are found, for as long as the
    /// connection has not settled.
    private func startTrickling(on peer: RTCPeerConnection) {
        trickle?.cancel()
        trickle = Task { [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.state == .connected { return }
                guard let handle = self.handle, let token = self.token else { return }
                let fresh = self.pendingCandidates.dropFirst(self.exchangedCandidates)
                self.exchangedCandidates = self.pendingCandidates.count
                // An empty hand-over is still worth making: the exchange is
                // how the server's own later candidates are collected, and
                // it has no other way to reach us. Only sending when we have
                // something new means never learning about the relay address
                // the server found second.
                let payload = Self.payload(for: fresh)
                guard let response = try? await XCloudSession.shared.exchangeCandidates(
                    payload, on: handle, token: token
                ) else { continue }
                await self.add(Self.candidates(fromExchange: response), to: peer)
            }
        }
    }

    func close() {
        trickle?.cancel()
        trickle = nil
        for open in [inputChannel, controlChannel, messageChannel, chatChannel] {
            open?.close()
        }
        inputChannel = nil
        controlChannel = nil
        messageChannel = nil
        chatChannel = nil
        inputReady = false
        connection?.close()
        connection = nil
        videoTrack = nil
        handle = nil
        token = nil
        pendingCandidates.removeAll()
        exchangedCandidates = 0
        state = .closed
    }

    // MARK: - Sending

    /// Sends an encoded controller frame on the input channel.
    @discardableResult
    func sendInput(_ payload: Data) -> Bool {
        guard let inputChannel, inputChannel.readyState == .open else { return false }
        return inputChannel.sendData(RTCDataBuffer(data: payload, isBinary: true))
    }

    // MARK: - Description handling

    /// Adjusts our own offer before it goes out.
    ///
    /// Only what this client can state truthfully: the receive bitrate
    /// ceiling. Codec order is left alone here because the answer decides it
    /// and guessing wrong costs a whole negotiation.
    static func prepare(_ sdp: String) -> String {
        let limit = AppSettings.shared.maxBitrateMbps
        guard limit > 0 else { return sdp }
        var lines = sdp.components(separatedBy: "\r\n")
        guard let videoIndex = lines.firstIndex(where: { $0.hasPrefix("m=video") }) else {
            return sdp
        }
        let kbps = limit * 1000
        // SDP fixes the order inside a media section: a bandwidth line has
        // to follow the connection line, not precede it. Put in the wrong
        // place the whole description can be rejected, which reads as a
        // negotiation that failed for no reason.
        let end = lines[(videoIndex + 1)...].firstIndex(where: { $0.hasPrefix("m=") })
            ?? lines.endIndex
        let section = (videoIndex + 1)..<end
        if let existing = lines[section].firstIndex(where: { $0.hasPrefix("b=AS:") }) {
            lines[existing] = "b=AS:\(kbps)"
        } else {
            let afterConnection = lines[section].lastIndex(where: { $0.hasPrefix("c=") })
                .map { $0 + 1 }
            lines.insert("b=AS:\(kbps)", at: afterConnection ?? (videoIndex + 1))
        }
        return lines.joined(separator: "\r\n")
    }

    /// The exchange endpoints answer with JSON, sometimes wrapping the real
    /// payload in another layer of JSON string.
    static func sdp(fromExchange text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return text }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let sdp = object["sdp"] as? String { return sdp }
            if let nested = object["exchangeResponse"] as? String {
                return sdp(fromExchange: nested)
            }
        }
        return text.contains("v=0") ? text : nil
    }

    static func candidates(fromExchange text: String) -> [RTCIceCandidate] {
        guard let data = text.data(using: .utf8) else { return [] }
        var entries: [[String: Any]] = []
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            entries = array
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let nested = object["candidate"] as? String,
                  let nestedData = nested.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: nestedData) as? [[String: Any]] {
            entries = array
        }
        return entries.compactMap { entry in
            guard let sdp = entry["candidate"] as? String, !sdp.isEmpty else { return nil }
            let index = (entry["sdpMLineIndex"] as? Int32)
                ?? Int32(entry["sdpMLineIndex"] as? Int ?? 0)
            return RTCIceCandidate(sdp: sdp,
                                   sdpMLineIndex: index,
                                   sdpMid: entry["sdpMid"] as? String)
        }
    }

    static func codecs(in sdp: String) -> [String] {
        var names: [String] = []
        for line in sdp.components(separatedBy: .newlines) where line.hasPrefix("a=rtpmap:") {
            let parts = line.components(separatedBy: " ")
            guard parts.count > 1 else { continue }
            let name = parts[1].components(separatedBy: "/").first ?? ""
            if !name.isEmpty && !names.contains(name) { names.append(name) }
        }
        return names
    }
}

// MARK: - Peer connection events

extension NativeStreamPeer: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in
            guard connection != nil else { return }
            pendingCandidates.append(candidate)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didAdd receiver: RTCRtpReceiver,
                                    streams: [RTCMediaStream]) {
        guard let track = receiver.track as? RTCVideoTrack else { return }
        Task { @MainActor in
            AppLog.shared.info("native", "video track arrived")
            videoTrack = track
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            // A closed connection still delivers a last state or two. Acting
            // on them puts a torn-down peer back into "Reconnecting".
            guard connection != nil else { return }
            AppLog.shared.debug("native", "ice state \(newState.rawValue)")
            switch newState {
            case .connected, .completed:
                state = .connected
            case .failed:
                state = .failed("the connection failed")
            case .disconnected:
                // Not fatal. ICE reports this while it re-checks a path, and
                // treating it as an ending tears down a stream that is about
                // to come back.
                state = .negotiating("Reconnecting")
            case .closed:
                state = .closed
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didOpen dataChannel: RTCDataChannel) {
        Task { @MainActor in
            AppLog.shared.debug("native", "channel '\(dataChannel.label)' opened by the server")
            dataChannel.delegate = self
            if dataChannel.label == "input" {
                inputChannel = dataChannel
                inputReady = dataChannel.readyState == .open
            }
            if dataChannel.label == "control" { controlChannel = dataChannel }
            if dataChannel.label == "message" { messageChannel = dataChannel }
            if dataChannel.label == "chat" { chatChannel = dataChannel }
        }
    }

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didChange newState: RTCIceGatheringState) {
        Task { @MainActor in
            AppLog.shared.debug("native", "ice gathering \(newState.rawValue)")
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didRemove candidates: [RTCIceCandidate]) {}
}

// MARK: - Data channel events

extension NativeStreamPeer: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let label = dataChannel.label
        let open = dataChannel.readyState == .open
        let state = dataChannel.readyState.rawValue
        Task { @MainActor in
            AppLog.shared.debug("native", "channel '\(label)' state \(state)")
            guard label == "input" else { return }
            inputReady = open
        }
    }

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel,
                                 didReceiveMessageWith buffer: RTCDataBuffer) {
        let label = dataChannel.label
        let data = buffer.data
        Task { @MainActor in
            guard label != "input" else {
                onRumble?(data)
                return
            }
            // The other channels carry the service's own words about the
            // session: why it disconnected, what it thinks the title is
            // doing. Throwing them away was why a session that ended on
            // its own never said why.
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                AppLog.shared.info("native", "\(label): \(text.prefix(300))")
            } else {
                AppLog.shared.debug("native", "\(label): \(data.count) bytes")
            }
        }
    }
}
#endif
