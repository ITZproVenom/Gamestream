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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                posterWall(size: geo.size)
                Color.black.opacity(0.28).ignoresSafeArea()
                LinearGradient(
                    colors: [
                        .black.opacity(0.15),
                        .black.opacity(0.42),
                        .black.opacity(0.92)
                    ],
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
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, max(geo.safeAreaInsets.top + 8, 12))

                    Spacer(minLength: 8)
                        .frame(maxHeight: 40)

                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .scaleEffect(appeared ? 1 : 0.86)
                            .opacity(appeared ? 1 : 0)
                            .accessibilityHidden(true)

                        Text("GameStream")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)

                        Text("Xbox Cloud Gaming with Better xCloud and a native GameHub — play instantly.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: 340)
                            .opacity(appeared ? 1 : 0)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
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
                    .padding(.top, 12)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 10) + 12)
                    .frame(maxWidth: 520)
                    .accessibilityLabel("Get Started")
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { appeared = true }
            withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) {
                kenBurns = 1.12
                artShift = 36
            }
        }
    }

    private func posterWall(size: CGSize) -> some View {
        let columnCount = size.width > 700 ? 5 : 3
        let tileWidth = max(110, size.width / CGFloat(columnCount) + 18)
        let tileHeight = tileWidth * 1.42
        return ZStack {
            Color.black
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { row in
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
            .frame(width: size.width + 80, height: size.height + 120)
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func posterTile(index: Int, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if posters.indices.contains(index) {
                AsyncImage(url: posters[index]) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallbackPoster
                    }
                }
            } else {
                fallbackPoster
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
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
