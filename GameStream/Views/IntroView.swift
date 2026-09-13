import SwiftUI
import UIKit

struct IntroView: View {
    var onFinished: () -> Void

    @State private var appeared = false
    @State private var artShift: CGFloat = 0

    var body: some View {
        ZStack {
            artwork
            Color.black.opacity(0.38).ignoresSafeArea()
            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.55), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("Skip") { finish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .accessibilityLabel("Skip intro")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 18) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .scaleEffect(appeared ? 1 : 0.86)
                        .opacity(appeared ? 1 : 0)

                    Text("GameStream")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)

                    Text("Xbox Cloud Gaming with Better xCloud and a native GameHub — play instantly.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .opacity(appeared ? 1 : 0)
                }
                .padding(24)
                .frame(maxWidth: 520)
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
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: 520)
                .accessibilityLabel("Get Started")
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { appeared = true }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                artShift = 28
            }
        }
    }

    private var artwork: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.04, blue: 0.28),
                    Color(red: 0.05, green: 0.08, blue: 0.22),
                    Color(red: 0.02, green: 0.02, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.55, green: 0.12, blue: 0.82).opacity(0.55), .clear],
                center: UnitPoint(x: 0.22, y: 0.22),
                startRadius: 10,
                endRadius: 380
            )
            .offset(x: -artShift, y: artShift * 0.4)
            RadialGradient(
                colors: [Color(red: 0.10, green: 0.38, blue: 0.95).opacity(0.42), .clear],
                center: UnitPoint(x: 0.82, y: 0.38),
                startRadius: 8,
                endRadius: 420
            )
            .offset(x: artShift, y: -artShift * 0.3)
            RadialGradient(
                colors: [Color(red: 0.05, green: 0.78, blue: 0.72).opacity(0.22), .clear],
                center: UnitPoint(x: 0.5, y: 0.82),
                startRadius: 6,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func finish() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        onFinished()
    }
}
