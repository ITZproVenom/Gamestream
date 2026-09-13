import SwiftUI

struct IntroView: View {
    var onFinished: () -> Void

    @State private var appeared = false
    @State private var glow = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AnimatedBackground()

            cinematicArt
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 1.08)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: Capsule())
                        .accessibilityLabel("Skip intro")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(color: .purple.opacity(0.55), radius: glow ? 22 : 8)
                        .accessibilityHidden(true)

                    Text("GameStream")
                        .font(.system(size: sizeClass == .compact ? 40 : 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("Xbox Cloud Gaming, Better xCloud, and GameHub \u2014 one cinematic place to play.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 24)

                Button(action: finish) {
                    Text("Get Started")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 32)
                .padding(.top, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: 520)
                .accessibilityLabel("Get Started")
            }
        }
        .onAppear {
            if reduceMotion {
                appeared = true
                glow = true
            } else {
                withAnimation(.easeOut(duration: 0.9)) { appeared = true }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
            }
        }
    }

    private var cinematicArt: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                posterCard("bolt.fill", "Instant play", x: w * 0.14, y: h * 0.18, rot: -8)
                posterCard("sparkles", "Better xCloud", x: w * 0.72, y: h * 0.16, rot: 7)
                posterCard("square.grid.2x2.fill", "GameHub", x: w * 0.22, y: h * 0.42, rot: 5)
                posterCard("cloud.fill", "Xbox Cloud", x: w * 0.78, y: h * 0.40, rot: -6)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func posterCard(_ icon: String, _ title: String, x: CGFloat, y: CGFloat, rot: Double) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .frame(width: 128, height: 168)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
        )
        .rotationEffect(.degrees(rot))
        .position(x: x, y: y)
        .offset(y: appeared ? 0 : 24)
    }

    private func finish() {
        OnboardingStore.markIntroCompleted()
        onFinished()
    }
}

enum OnboardingStore {
    static let introKey = "GameStream.introCompleted.v1"

    static var hasCompletedIntro: Bool {
        UserDefaults.standard.bool(forKey: introKey)
    }

    static func markIntroCompleted() {
        UserDefaults.standard.set(true, forKey: introKey)
    }
}
