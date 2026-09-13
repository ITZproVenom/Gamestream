import SwiftUI
import WebRTC

/// Video/input surface for an active session. Structured after
/// OPN.WebRTC.Media (OpenCloudGaming/OpenNOW-Mac, MIT): a signaling client
/// negotiates an RTCPeerConnection, and the resulting video track is
/// rendered into an RTCMTLVideoView-equivalent surface. The macOS package
/// renders into an NSView; this wraps WebRTC's iOS render surface instead
/// via UIViewRepresentable, and macOS-specific input/window-focus handling
/// is dropped in favor of GameController framework input (see InputBridge).
struct StreamPlayerView: View {
    let game: GameEntry
    @StateObject private var controller = StreamSessionController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let videoTrack = controller.remoteVideoTrack {
                WebRTCVideoView(track: videoTrack)
                    .ignoresSafeArea()
            } else {
                ProgressView("Connecting to \(game.title)…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .task { await controller.connect(gameId: game.id) }
        .onDisappear { controller.disconnect() }
    }
}

@MainActor
final class StreamSessionController: ObservableObject {
    @Published var remoteVideoTrack: RTCVideoTrack?

    private var peerConnection: RTCPeerConnection?
    private let libraryService = GameLibraryService()

    func connect(gameId: String) async {
        // Hook point: fetch a StreamSessionDescriptor from GameLibraryService,
        // open the signaling WebSocket at descriptor.signalingURL, and drive
        // the standard WebRTC offer/answer + ICE exchange to populate
        // `peerConnection` and `remoteVideoTrack`.
    }

    func disconnect() {
        peerConnection?.close()
        peerConnection = nil
        remoteVideoTrack = nil
    }
}

struct WebRTCVideoView: UIViewRepresentable {
    let track: RTCVideoTrack

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        track.add(view)
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {}
}
