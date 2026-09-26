import SwiftUI
import UIKit

struct IntroView: View {
    var onFinished: () -> Void

    @State private var appeared = false
    @State private var kenBurns: CGFloat = 1.0
    @State private var artShift: CGFloat = 0

    private var posters: [URL] {
        Array(GameCatalog.games.compactMap(\.posterURL).prefix(12))
    }

    private var physicalWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var contentWidth: CGFloat {
        min(max(physicalWidth - 40, 280), 420)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background

            // Keep the entire foreground in a physical-screen-sized canvas.
            // This deliberately avoids GeometryReader's scene width so a sideload
            // or container host cannot make the glass controls drift off-screen.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    topBar
                        .padding(.top, proxy.safeAreaInsets.top + 6)

                    Spacer(minLength: 18)

                    heroCard

                    Spacer(minLength: 18)

                    actionArea
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8))
                }
                .frame(width: physicalWidth, height: proxy.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
                kenBurns = 1.08
                artShift = 24
            }
        }
    }

    private var background: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                posterWall(size: proxy.size)
                LinearGradient(
                    colors: [
                        .black.opacity(0.16),
                        .black.opacity(0.32),
                        .black.opacity(0.78),
                        .black.opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("GAMESTREAM")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(.white.opacity(0.72))

            Spacer(minLength: 12)

            Button("Skip", action: finish)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 17)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityLabel("Skip intro")
        }
        .padding(.horizontal, 20)
    }

    private var heroCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 76, height: 76)
                    .glassEffect(.regular, in: Circle())

                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(appeared ? 1 : 0.84)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 8) {
                Text("GameStream")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityAddTraits(.isHeader)

                Text("Xbox Cloud Gaming, Better xCloud, and your native GameHub in one place.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 310)
            }

            HStack(spacing: 8) {
                featurePill("Cloud Gaming", systemImage: "cloud.fill")
                featurePill("GameHub", systemImage: "square.grid.2x2.fill")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(width: contentWidth)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            Button(action: finish) {
                HStack(spacing: 10) {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.semibold))
                }
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(.glassProminent)
            .accessibilityLabel("Get Started")

            Text("Your games. One hub. Ready when you are.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .frame(width: contentWidth)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    private func featurePill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .glassEffect(.regular, in: Capsule())
    }

    private func posterWall(size: CGSize) -> some View {
        let columnCount = size.width > 700 ? 5 : 3
        let tileWidth = max(110, size.width / CGFloat(columnCount) + 18)
        let tileHeight = tileWidth * 1.42

        return ZStack {
            VStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<columnCount, id: \.self) { col in
                            let index = (row * columnCount + col) % max(posters.count, 1)
                            posterTile(index: index, width: tileWidth, height: tileHeight)
                        }
                    }
                    .offset(x: row.isMultiple(of: 2) ? artShift : -artShift)
                }
            }
            .scaleEffect(kenBurns)
            .frame(width: size.width + 80, height: size.height + 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func posterTile(index: Int, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if posters.indices.contains(index) {
                RemoteImage(url: posters[index]) {
                    fallbackPoster
                }
            } else {
                fallbackPoster
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var fallbackPoster: some View {
        LinearGradient(
            colors: [
                Color(red: 0.22, green: 0.08, blue: 0.38),
                Color(red: 0.05, green: 0.10, blue: 0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func finish() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onFinished()
    }
}
