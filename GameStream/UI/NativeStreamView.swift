#if canImport(WebRTC)
import SwiftUI
import UIKit
import WebRTC

/// Renders a native stream's video track.
///
/// `RTCMTLVideoView` draws the decoded frames through Metal, which is the
/// only path that avoids a copy per frame. The track is attached and detached
/// as it changes rather than rebuilding the view, because rebuilding drops
/// frames on every reconnect.
struct NativeVideoView: UIViewRepresentable {
    let track: RTCVideoTrack?
    /// "Fill the screen" is a picture setting, and the native path has to
    /// honour it too or the same switch means different things in the two
    /// players.
    let fills: Bool

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.videoContentMode = fills ? .scaleAspectFill : .scaleAspectFit
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
    @State private var heartbeat: Task<Void, Never>?
    /// Set when a step fails. The view stays up so the reason can be read:
    /// dismissing on failure meant the message was written and thrown away
    /// in the same breath, and every failure looked like the screen simply
    /// closing itself.
    @State private var failure: String?
    @State private var steps: [String] = []
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NativeVideoView(track: peer.videoTrack, fills: settings.fillScreen)
                .ignoresSafeArea()

            if let failure {
                VStack(alignment: .leading, spacing: 14) {
                    Label("The native stream could not start", systemImage: "bolt.slash.fill")
                        .font(.headline)
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if !steps.isEmpty {
                        Text("How far it got")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(steps.joined(separator: "\n"))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 12) {
                        Button("Try again") {
                            Task { await retry() }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Exit") {
                            Task { await stop() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 2)
                }
                .padding(22)
                .frame(maxWidth: 460, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(24)
            } else if peer.videoTrack == nil {
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
                // Said plainly, because a stream you cannot play looks like
                // a broken stream rather than an unfinished one.
                if peer.videoTrack != nil {
                    Text("Video only for now: this path does not send controller "
                         + "input yet. Use Play for a playable stream.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 18)
                }
            }
        }
        .task { await start() }
        .onDisappear {
            heartbeat?.cancel()
            heartbeat = nil
            UIApplication.shared.isIdleTimerDisabled = AppSettings.shared.keepAwake
        }
        .onChange(of: peer.state) { _, value in
            switch value {
            case .negotiating(let step): status = step
            case .connected: status = "Connected"
            case .failed(let reason):
                status = "Failed: \(reason)"
                Task { await fail(reason) }
            case .closed: status = "Closed"
            case .idle: status = "Starting"
            }
        }
    }

    /// Records each step, so a failure says how far it got rather than only
    /// what broke.
    @MainActor
    private func note(_ step: String) {
        status = step
        steps.append(step)
        AppLog.shared.info("native", step)
    }

    private func retry() async {
        failure = nil
        steps = []
        await start()
    }

    private func fail(_ reason: String) async {
        AppLog.shared.error("native", reason)
        failure = reason
        heartbeat?.cancel()
        heartbeat = nil
        peer.close()
        // The session is given back even though the screen stays up: a
        // failed attempt must not sit on one of the account's slots while
        // the reason is being read.
        if let session, let token {
            _ = await XCloudSession.shared.release(session, token: token)
        }
        session = nil
    }

    private func start() async {
        guard let xsts = auth.xstsToken else {
            await fail("No cloud-gaming token is available. Sign in on the Xbox "
                       + "page first, then try again.")
            return
        }
        // Nothing else keeps the screen on in this path, and a stream that
        // dims out after thirty seconds is not a stream.
        UIApplication.shared.isIdleTimerDisabled = true
        do {
            note("Signing in to the cloud service")
            let login = try await XCloudAPI.shared.login(xstsToken: xsts)
            token = login.gsToken
            note("Token obtained; \(login.regions.count) region(s)")

            // A game page carries a store ProductId. The cloud service asks
            // for sessions by its own title id, so the two have to be
            // related before anything can be provisioned.
            note("Looking up the cloud title for \(game.id)")
            let title = try await XCloudSession.shared.titleInfo(productId: game.id,
                                                                 login: login)
            note("Asking for a session for \(title.name ?? title.titleId)")
            let osName = XCloudSession.osName(forResolution: AppSettings.shared.resolutionPref)
            let handle = try await XCloudSession.shared.provision(login: login,
                                                                  titleId: title.titleId,
                                                                  osName: osName)
            session = handle
            note("Session granted at \(handle.path)")

            note("Waiting for a server")
            _ = try await XCloudSession.shared.waitUntilReady(handle, token: login.gsToken) { state in
                Task { @MainActor in
                    note(state.queuePosition.map { "Queued at position \($0)" } ?? state.raw)
                }
            }

            startHeartbeat(handle: handle, token: login.gsToken)
            note("Negotiating media")
            await peer.connect(handle: handle, token: login.gsToken)
        } catch {
            await fail(error.localizedDescription)
        }
    }

    /// The service reclaims a session that stops talking to it. Provisioning
    /// one and then going quiet is how a slot is lost for minutes with
    /// nothing playing in it.
    private func startHeartbeat(handle: XCloudSession.Handle, token: String) {
        heartbeat?.cancel()
        heartbeat = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await XCloudSession.shared.keepAlive(handle, token: token)
            }
        }
    }

    private func stop() async {
        heartbeat?.cancel()
        heartbeat = nil
        UIApplication.shared.isIdleTimerDisabled = AppSettings.shared.keepAwake
        peer.close()
        if let session, let token {
            _ = await XCloudSession.shared.release(session, token: token)
        }
        session = nil
        dismiss()
    }
}
#endif
