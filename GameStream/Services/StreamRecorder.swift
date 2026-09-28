import Foundation
import ReplayKit
import AVFoundation
import Photos
import UIKit

/// Records the stream to a video file.
///
/// Screenshots were only ever half the ask: the interesting things in a game
/// happen over seconds, not in one frame. There is no way to pull frames out
/// of the player fast enough to build a video — the canvas read that makes a
/// screenshot work costs far too much at sixty frames a second — so this
/// records the screen instead, through ReplayKit.
///
/// Recording the screen rather than the video element has a real consequence
/// worth knowing: the app's own HUD is in the recording if it is on screen
/// when you capture. The overlay hides itself a few seconds after a tap, so
/// in practice a clip started and left alone is clean.
///
/// Samples are written straight through to an MP4. Holding them in memory to
/// write later is how a long recording ends as an out-of-memory crash with
/// nothing saved.
@MainActor
final class StreamRecorder: NSObject, ObservableObject {
    static let shared = StreamRecorder()

    enum State: Equatable {
        case idle
        case starting
        case recording(since: Date)
        case saving
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Seconds recorded so far, for the indicator.
    @Published private(set) var elapsed: TimeInterval = 0

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    private let recorder = RPScreenRecorder.shared()
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    /// The microphone gets its own track.
    ///
    /// ReplayKit delivers app audio and microphone audio as two independent
    /// streams with their own clocks and formats. Appending both to one
    /// input is not a mix, it is two sources fighting over one timeline: the
    /// writer refuses the first sample that goes backwards and the whole
    /// recording is lost. Two tracks is the only correct shape, and players
    /// play them together.
    private var micInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var ticker: Task<Void, Never>?

    private override init() { super.init() }

    // MARK: - Recording

    func toggle() async -> String {
        isRecording ? await stop() : await start()
    }

    func start() async -> String {
        guard !isRecording else { return "Already recording." }
        guard recorder.isAvailable else {
            state = .failed("unavailable")
            return "Screen recording is not available right now."
        }

        state = .starting
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamestream-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: url)
        outputURL = url

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

            let size = UIScreen.main.bounds.size
            let scale = UIScreen.main.scale
            // Even dimensions: the encoder rejects odd ones, and a rotated
            // phone produces them often enough to matter.
            let width = Int((size.width * scale).rounded()) & ~1
            let height = Int((size.height * scale).rounded()) & ~1

            let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: AppSettings.shared.recordingBitrateMbps * 1_000_000,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ])
            video.expectsMediaDataInRealTime = true
            if writer.canAdd(video) { writer.add(video) }

            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000
            ])
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) { writer.add(audio) }

            let wantsMicrophone = AppSettings.shared.recordMicrophone
            if wantsMicrophone {
                let mic = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44_100,
                    AVEncoderBitRateKey: 64_000
                ])
                mic.expectsMediaDataInRealTime = true
                if writer.canAdd(mic) {
                    writer.add(mic)
                    micInput = mic
                }
            }

            self.writer = writer
            videoInput = video
            audioInput = audio
            sessionStarted = false

            recorder.isMicrophoneEnabled = wantsMicrophone

            // Writing starts before capture does. The other way round, every
            // sample that arrives in the gap is dropped because the writer is
            // not writing yet, and the clip begins late.
            writer.startWriting()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                recorder.startCapture { [weak self] sample, type, error in
                    if let error {
                        // Capture can be ended by the system — backgrounding,
                        // a call, a screen recording started elsewhere. The
                        // clip so far is worth keeping, and the state has to
                        // stop claiming to be recording.
                        Task { @MainActor in
                            guard let self, self.isRecording else { return }
                            let detail = error.localizedDescription
                            AppLog.shared.warn("recorder", "capture ended: \(detail)")
                            _ = await self.stop()
                        }
                        return
                    }
                    self?.append(sample, of: type)
                } completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            let started = Date()
            state = .recording(since: started)
            startTicking(from: started)
            return "Recording."
        } catch {
            await tearDown()
            state = .failed(error.localizedDescription)
            return "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stop() async -> String {
        guard isRecording else { return "Not recording." }
        state = .saving
        ticker?.cancel()
        ticker = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            recorder.stopCapture { _ in continuation.resume() }
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()

        guard let writer, let url = outputURL else {
            state = .idle
            return "Nothing was recorded."
        }
        await writer.finishWriting()

        guard writer.status == .completed else {
            await tearDown()
            let reason = writer.error?.localizedDescription ?? "the file could not be written"
            state = .failed(reason)
            return "Recording failed: \(reason)"
        }

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else {
            await tearDown()
            state = .idle
            return "GameStream cannot add to Photos. Allow it in iOS Settings."
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .video, fileURL: url, options: nil)
            }
            let length = Int(elapsed)
            await tearDown()
            state = .idle
            AppLog.shared.info("recorder", "saved a \(length)s clip")
            return "Saved a \(length)s clip to Photos."
        } catch {
            await tearDown()
            state = .failed(error.localizedDescription)
            return "Could not save the clip: \(error.localizedDescription)"
        }
    }

    // MARK: - Sample handling

    /// Called on ReplayKit's own queue, not the main actor.
    private nonisolated func append(_ sample: CMSampleBuffer, of type: RPSampleBufferType) {
        Task { @MainActor in
            guard let writer, writer.status == .writing else { return }

            if !sessionStarted {
                // Only a video sample may open the session: starting on an
                // audio sample leaves the first frames before the timeline
                // origin and they are dropped silently.
                guard type == .video else { return }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
                sessionStarted = true
            }

            switch type {
            case .video:
                if videoInput?.isReadyForMoreMediaData == true {
                    videoInput?.append(sample)
                }
            case .audioApp:
                if audioInput?.isReadyForMoreMediaData == true {
                    audioInput?.append(sample)
                }
            case .audioMic:
                if let micInput, micInput.isReadyForMoreMediaData {
                    micInput.append(sample)
                }
            @unknown default:
                break
            }
        }
    }

    private func startTicking(from start: Date) {
        elapsed = 0
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                elapsed = Date().timeIntervalSince(start)
                // A session limit for recordings too: a forgotten recording
                // fills the device, and the phone gets hot enough streaming.
                let cap = AppSettings.shared.recordingLimitMinutes
                if cap > 0, elapsed > Double(cap * 60) {
                    _ = await stop()
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func tearDown() async {
        writer = nil
        videoInput = nil
        audioInput = nil
        micInput = nil
        sessionStarted = false
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        ticker?.cancel()
        ticker = nil
        elapsed = 0
    }
}
