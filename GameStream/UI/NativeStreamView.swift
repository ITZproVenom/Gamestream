#if canImport(WebRTC)
import SwiftUI
import WebRTC

/// Renders a native stream's video track.
///
/// `RTCMTLVideoView` draws the decoded frames through Metal, which is the
/// only path that avoids a copy per frame. The track is attached and detached
/// as it changes rather than rebuilding the view, because rebuilding drops
/// frames on every reconnect.
struct NativeVideoView: UIViewRepresentable {
    let track: RTCVideoTrack?

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        if context.coordinator.attached !== track {
            context.coordinator.attached?.remove(view)
            track?.add(view)
            context.coordinator.attached = track
        }
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.attached?.remove(view)
        coordinator.attached = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var attached: RTCVideoTrack?
    }
}

/// The native player, end to end: provision a session, negotiate media, draw
/// the result. No webview anywhere in this path.
struct NativeStreamView: View {
    let game: Game
    @StateObject private var peer = NativeStreamPeer()
    @EnvironmentObject private var auth: XboxAuth
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Starting"
    @State private var session: XCloudSession.Handle?
    @State private var token: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NativeVideoView(track: peer.videoTrack).ignoresSafeArea()

            if peer.videoTrack == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack {
                HStack {
                    Button {
                        Task { await stop() }
                    } label: {
                        Label("Exit", systemImage: "xmark")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    if !peer.offeredCodecs.isEmpty {
                        Text(peer.offeredCodecs.joined(separator: " · "))
                            .font(.caption.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding()
                Spacer()
            }
        }
        .task { await start() }
        .onChange(of: peer.state) { _, value in
            switch value {
            case .negotiating(let step): status = step
            case .connected: status = "Connected"
            case .failed(let reason): status = "Failed: \(reason)"
            case .closed: status = "Closed"
            case .idle: status = "Starting"
            }
        }
    }

    private func start() async {
        guard let xsts = auth.xstsToken else {
            status = "Sign in first"
            return
        }
        do {
            status = "Signing in to the cloud service"
            let login = try await XCloudAPI.shared.login(xstsToken: xsts)
            token = login.gsToken

            status = "Asking for a session"
            let handle = try await XCloudSession.shared.provision(login: login,
                                                                  titleId: game.id)
            session = handle

            status = "Waiting for a server"
            _ = try await XCloudSession.shared.waitUntilReady(handle, token: login.gsToken) { state in
                Task { @MainActor in
                    status = state.queuePosition.map { "Queued at position \($0)" } ?? state.raw
                }
            }

            await peer.connect(handle: handle, token: login.gsToken)
        } catch {
            status = "Failed: \(error.localizedDescription)"
            await stop()
        }
    }

    private func stop() async {
        peer.close()
        if let session, let token {
            _ = await XCloudSession.shared.release(session, token: token)
        }
        session = nil
        dismiss()
    }
}
#endif
