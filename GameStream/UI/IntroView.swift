import SwiftUI

/// The short animation that plays when the app is launched cold.
///
/// Drawn entirely in SwiftUI from the app's own accent colour: there is no
/// video, no audio and no asset to ship, so it cannot fail to load and costs
/// nothing in the bundle. It covers the session check that is happening
/// behind it, which means the first thing a player sees is the app rather
/// than a spinner.
///
/// Three things keep it from becoming the kind of intro people resent:
/// it runs once per cold launch and never again until the app is relaunched,
/// a tap anywhere skips it immediately, and it can be turned off in Settings.
/// With Reduce Motion on it is a plain fade, because a sweeping wordmark is
/// exactly what that setting exists to avoid.
struct IntroView: View {
    let accent: Color
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sweep: CGFloat = -1.1
    @State private var wordmarkIn = false
    @State private var glow: CGFloat = 0
    @State private var scale: CGFloat = 1.06
    @State private var finished = false

    private let title = "GAMESTREAM"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // A faint pool of accent light behind the letters, so the sweep
            // has something to come out of rather than appearing on nothing.
            RadialGradient(
                colors: [accent.opacity(0.32 * glow), .clear],
                center: .center,
                startRadius: 1,
                endRadius: 420
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            wordmark
                .scaleEffect(scale)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("GameStream")
        .accessibilityHint("Double tap to skip the opening animation")
        .onAppear { run() }
    }

    private var wordmark: some View {
        Text(title)
            .font(.system(size: 42, weight: .heavy, design: .rounded))
            .kerning(6)
            .foregroundStyle(.white.opacity(wordmarkIn ? 0.92 : 0))
            .overlay {
                // The sweep is a bright band travelling across the letters,
                // masked to the text itself. Masking to the glyphs rather
                // than drawing a rectangle over them is what makes it read
                // as the wordmark lighting up instead of a bar passing by.
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, accent, .white, accent, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 220)
                    .offset(x: sweep * 300)
                    .blendMode(.screen)
                }
            }
            .mask {
                Text(title)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .kerning(6)
            }
            .shadow(color: accent.opacity(0.55 * glow), radius: 22)
            .padding(.horizontal, 24)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private func run() {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.35)) {
                wordmarkIn = true
                glow = 1
                scale = 1
            }
            schedule(after: 0.9)
            return
        }

        withAnimation(.easeOut(duration: 0.5)) {
            wordmarkIn = true
            scale = 1
        }
        withAnimation(.easeInOut(duration: 0.9).delay(0.15)) {
            sweep = 1.1
        }
        withAnimation(.easeInOut(duration: 0.55).delay(0.5)) {
            glow = 1
        }
        // A small settle at the end, so it finishes on a held frame rather
        // than cutting away mid-movement.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(1.15)) {
            scale = 1.02
        }
        schedule(after: 1.75)
    }

    private func schedule(after seconds: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            finish()
        }
    }

    /// Safe to call more than once: a tap during the animation and the timer
    /// that follows it would otherwise both try to dismiss.
    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}
