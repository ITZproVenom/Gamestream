import SwiftUI

/// Full-screen branded loader shown while the stream session boots after Play.
struct PlayLoadingView: View {
    let title: String
    @State private var pulse = false
    @State private var ring = false
    @State private var statusIndex = 0

    private let statuses = [
        "Starting session…",
        "Connecting to Xbox Cloud…",
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
                .fill(Color.purple.opacity(0.28))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: pulse ? 40 : -30, y: pulse ? -80 : -40)
            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: pulse ? -50 : 20, y: pulse ? 100 : 60)

            VStack(spacing: 28) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(
                                Color.white.opacity(0.12 - Double(i) * 0.03),
                                lineWidth: 2
                            )
                            .frame(width: CGFloat(88 + i * 28), height: CGFloat(88 + i * 28))
                            .scaleEffect(ring ? 1.08 + CGFloat(i) * 0.04 : 0.92)
                            .opacity(ring ? 0.35 : 0.85)
                    }

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 0.75, green: 0.7, blue: 1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(pulse ? 1.06 : 0.96)
                }
                .frame(height: 160)

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
                        .foregroundStyle(.white.opacity(0.65))
                        .animation(.easeInOut(duration: 0.35), value: statusIndex)
                }

                ProgressView()
                    .controlSize(.regular)
                    .tint(.white.opacity(0.9))
                    .padding(.top, 4)

                Text("GameStream")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 12)
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
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                statusIndex = (statusIndex + 1) % statuses.count
            }
        }
    }
}
