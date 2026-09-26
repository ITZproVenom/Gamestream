import SwiftUI
import AVFoundation

@MainActor
final class OpeningIntroSound {
    static let shared = OpeningIntroSound()
    private var player: AVAudioPlayer?
    private init() {}

    func play() {
        do {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true)
            player = try AVAudioPlayer(data: Self.makeWAV())
            player?.volume = 0.72
            player?.prepareToPlay()
            player?.play()
        } catch {
            // Decorative audio must never affect app launch.
        }
    }

    private static func makeWAV() -> Data {
        let sampleRate = 44_100
        let duration = 2.05
        let count = Int(Double(sampleRate) * duration)
        var pcm = [Int16]()
        pcm.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            var value = 0.0
            let notes: [(Double, Double, Double)] = [
                (0.00, 130.81, 0.22), (0.24, 196.00, 0.15),
                (0.48, 261.63, 0.11), (0.72, 523.25, 0.045)
            ]
            for (start, frequency, amplitude) in notes where t >= start {
                let attack = min(1.0, (t - start) / 0.12)
                let release = max(0.0, min(1.0, (duration - t) / 0.55))
                value += sin(2.0 * .pi * frequency * t) * amplitude * attack * release
            }
            if t < 0.42 {
                value += sin(2.0 * .pi * 65.0 * t) * 0.30 * exp(-t * 7.5)
            }
            let master = min(1.0, t / 0.06) * max(0.0, min(1.0, (duration - t) / 0.4))
            pcm.append(Int16(max(-1.0, min(1.0, value * master * 0.82)) * 32767.0))
        }

        var data = Data()
        func u16(_ v: UInt16) { data.append(contentsOf: [UInt8(v & 255), UInt8(v >> 8)]) }
        func u32(_ v: UInt32) { data.append(contentsOf: [UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8(v >> 24)]) }
        data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count * 2))
        for sample in pcm { u16(UInt16(bitPattern: sample)) }
        return data
    }
}

struct OpeningIntroView: View {
    let isReady: Bool
    let onFinished: () -> Void
    @State private var visible = false
    @State private var scale = 0.78
    @State private var titleOpacity = 0.0
    @State private var minimumDurationComplete = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Circle()
                .fill(Color.red.opacity(0.13))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .scaleEffect(visible ? 1.15 : 0.7)

            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 82, height: 82)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(scale)

                Text("GAMESTREAM")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)
            }
        }
        .opacity(visible ? 1 : 0)
        .onAppear {
            OpeningIntroSound.shared.play()
            withAnimation(.easeOut(duration: 0.55)) {
                visible = true; scale = 1; titleOpacity = 1
            }
            // Keep the cinematic layer alive while the catalog/posters initialize.
            // Once ready, let the animation finish naturally.
            try? await Task.sleep(for: .milliseconds(1200))
            await MainActor.run { minimumDurationComplete = true }
            if isReady {
                finishWhenReady()
            }
        }
        .onChange(of: isReady) { _, ready in
            if ready && minimumDurationComplete { finishWhenReady() }
        }
    }

    @MainActor
    private func finishWhenReady() {
        guard visible, minimumDurationComplete else { return }
        withAnimation(.easeInOut(duration: 0.28)) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: onFinished)
    }
}
