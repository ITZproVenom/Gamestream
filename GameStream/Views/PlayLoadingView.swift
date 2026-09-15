import SwiftUI

/// Full-screen branded loader shown while the stream session boots after Play.
struct PlayLoadingView: View {
    let title: String
    @State private var pulse = false
    @State private var ring = false
    @State private var statusIndex = 0
    @State private var shimmer = false

    private let statuses = [
        "Starting session…",
        "Connecting to Xbox Cloud…",
        "Applying stream quality…",
        "Preparing stream…"
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.04, blue: 0.12),
                    Color(red: 0.08, green: 0.06, blue: 0.22),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.purple.opacity(0.30))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: pulse ? 48 : -36, y: pulse ? -90 : -50)
            Circle()
                .fill(Color.cyan.opacity(0.20))
                .frame(width: 240, height: 240)
                .blur(radius: 55)
                .offset(x: pulse ? -56 : 24, y: pulse ? 110 : 70)

            VStack(spacing: 26) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(
                                Color.white.opacity(0.14 - Double(i) * 0.03),
                                lineWidth: 2
                            )
                            .frame(width: CGFloat(92 + i * 30), height: CGFloat(92 + i * 30))
                            .scaleEffect(ring ? 1.1 + CGFloat(i) * 0.05 : 0.9)
                            .opacity(ring ? 0.3 : 0.9)
                    }

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 0.75, green: 0.7, blue: 1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(pulse ? 1.07 : 0.95)
                }
                .frame(height: 170)

                VStack(spacing: 10) {
                    Text(title.isEmpty ? "GameStream" : title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 28)

                    Text(statuses[statusIndex % statuses.count])
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .animation(.easeInOut(duration: 0.35), value: statusIndex)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.55, green: 0.45, blue: 1),
                                        Color(red: 0.35, green: 0.75, blue: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * (shimmer ? 0.72 : 0.28))
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: shimmer)
                    }
                }
                .frame(width: 160, height: 5)
                .padding(.top, 6)

                Text("GameStream · Xbox Cloud")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                ring = true
            }
            shimmer = true
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_700_000_000)
                statusIndex = (statusIndex + 1) % statuses.count
            }
        }
    }
}
