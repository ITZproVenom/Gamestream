import Foundation
import ReplayKit
import AVFoundation
import Photos
import UIKit

/// Holds the writer and its inputs, and appends samples on whatever queue
/// ReplayKit delivers them on.
///
/// The appending deliberately does not go through the main actor. ReplayKit
/// hands over samples on its own queue at the frame rate of the screen, and
/// forwarding each one into a task on another actor changes two things that
/// matter: the samples can be appended in a different order than they
/// arrived, which the writer treats as a fatal timeline error, and each
/// buffer has to stay alive across the hop. A serial queue with the writer
/// behind it keeps the order the capture had.
private final class SampleSink: @unchecked Sendable {
    private let lock = NSLock()
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let app: AVAssetWriterInput?
    private let mic: AVAssetWriterInput?
    private var sessionStarted = false
    private var finished = false

    /// Whether the app is currently drawing over the game.
    ///
    /// ReplayKit captures the screen, so anything on top of the picture
    /// lands in the clip. A clip of a game with the app's own controls
    /// burnt into it is a screen recording, not a clip. Frames are dropped
    /// while the overlay is up and the gap is taken back out of the
    /// timeline, so the clip holds only the game and still runs smoothly
    /// across the moment the controls were used.
    private var suppressed = false
    private var suppressedFrom: CMTime = .invalid
    private var timeOffset: CMTime = .zero

    func setSuppressed(_ value: Bool, at time: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        guard value != suppressed else { return }
        suppressed = value
        if value {
            suppressedFrom = time
        } else if suppressedFrom.isValid, time.isValid, time > suppressedFrom {
            timeOffset = CMTimeAdd(timeOffset, CMTimeSubtract(time, suppressedFrom))
            suppressedFrom = .invalid
        }
    }

    init(writer: AVAssetWriter,
         video: AVAssetWriterInput,
         app: AVAssetWriterInput?,
         mic: AVAssetWriterInput?) {
        self.writer = writer
        self.video = video
        self.app = app
        self.mic = mic
    }

    func append(_ sample: CMSampleBuffer, of type: RPSampleBufferType) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, writer.status == .writing, CMSampleBufferDataIsReady(sample) else {
            return
        }

        let stamp = CMSampleBufferGetPresentationTimeStamp(sample)

        // While the overlay is up, nothing is written. The elapsed time is
        // measured on the way out and taken off everything after it.
        if suppressed {
            if suppressedFrom.isValid == false { suppressedFrom = stamp }
            return
        }

        if !sessionStarted {
            // Only a video sample may open the session: starting on an audio
            // sample leaves the first frames before the timeline origin and
            // they are dropped silently.
            guard type == .video else { return }
            writer.startSession(atSourceTime: stamp)
            sessionStarted = true
        }

        let input: AVAssetWriterInput?
        switch type {
        case .video: input = video
        case .audioApp: input = app
        case .audioMic: input = mic
        @unknown default: input = nil
        }
        guard let input, input.isReadyForMoreMediaData else { return }

        guard timeOffset != .zero else {
            input.append(sample)
            return
        }
        // Shifted rather than dropped outright, so the clip has no hole
        // where the controls were and audio stays with the picture.
        guard let shifted = Self.retimed(sample, by: timeOffset) else { return }
        input.append(shifted)
    }

    /// The same sample, moved earlier on the timeline by `offset`.
    private static func retimed(_ sample: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count
        ) == noErr, count > 0 else { return nil }

        var timings = [CMSampleTimingInfo](
            repeating: CMSampleTimingInfo(), count: Int(count)
        )
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count
        ) == noErr else { return nil }

        for index in timings.indices {
            if timings[index].presentationTimeStamp.isValid {
                timings[index].presentationTimeStamp =
                    CMTimeSubtract(timings[index].presentationTimeStamp, offset)
            }
            if timings[index].decodeTimeStamp.isValid {
                timings[index].decodeTimeStamp =
                    CMTimeSubtract(timings[index].decodeTimeStamp, offset)
            }
        }

        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: count,
            sampleTimingArray: &timings,
            sampleBufferOut: &copy
        ) == noErr else { return nil }
        return copy
    }

    /// Closes the inputs and the file. Anything appended after this is
    /// ignored rather than crashing on a finished writer.
    func finish() async -> (status: AVAssetWriter.Status, error: Error?) {
        lock.lock()
        if finished {
            lock.unlock()
            return (writer.status, writer.error)
        }
        finished = true
        if sessionStarted {
            video.markAsFinished()
            app?.markAsFinished()
            mic?.markAsFinished()
        }
        let started = sessionStarted
        lock.unlock()

        guard started else { return (writer.status, writer.error) }
        await writer.finishWriting()
        return (writer.status, writer.error)
    }
}

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
    /// The microphone gets its own track.
    ///
    /// ReplayKit delivers app audio and microphone audio as two independent
    /// streams with their own clocks and formats. Appending both to one
    /// input is not a mix, it is two sources fighting over one timeline: the
    /// writer refuses the first sample that goes backwards and the whole
    /// recording is lost. Two tracks is the only correct shape, and players
    /// play them together.
    private var sink: SampleSink?
    private var overlayVisible = false

    /// Told by the player whenever the app draws over the game.
    ///
    /// ReplayKit captures the screen, so the controls would otherwise be
    /// burnt into the clip. Those frames are left out and the time they
    /// took is removed from the timeline, so a clip holds the game and
    /// nothing else. System interface such as Control Centre and
    /// notifications is never captured by an in-app recording in the first
    /// place, so only the app's own overlay had to be dealt with.
    func setOverlayVisible(_ visible: Bool) {
        guard overlayVisible != visible else { return }
        overlayVisible = visible
        guard let sink else { return }
        sink.setSuppressed(visible, at: CMClockGetTime(CMClockGetHostTimeClock()))
    }
    private var outputURL: URL?
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
                // The screen can rotate while recording. Saying how a
                // differently shaped frame should be fitted is better than
                // leaving it to be decided per sample.
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
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
            var mic: AVAssetWriterInput?
            if wantsMicrophone {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44_100,
                    AVEncoderBitRateKey: 64_000
                ])
                input.expectsMediaDataInRealTime = true
                if writer.canAdd(input) {
                    writer.add(input)
                    mic = input
                }
            }

            let sink = SampleSink(writer: writer, video: video, app: audio, mic: mic)
            self.sink = sink

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
                    // Captured directly: the sink is safe to touch from this
                    // queue, and reaching back through the recorder would
                    // mean crossing an actor boundary per frame.
                    sink.append(sample, of: type)
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
            recorder.stopCapture { _ in }
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

        guard let sink, let url = outputURL else {
            await tearDown()
            state = .idle
            return "Nothing was recorded."
        }
        let result = await sink.finish()

        guard result.status == .completed else {
            await tearDown()
            let reason = result.error?.localizedDescription
                ?? "nothing was captured before it stopped"
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
        sink = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        ticker?.cancel()
        ticker = nil
        elapsed = 0
    }
}
