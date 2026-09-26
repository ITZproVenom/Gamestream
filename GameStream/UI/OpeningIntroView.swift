import SwiftUI

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
            withAnimation(.easeOut(duration: 0.55)) {
                visible = true
                scale = 1
                titleOpacity = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                minimumDurationComplete = true
                if isReady {
                    finishWhenReady()
                }
            }
        }
        .onChange(of: isReady) { _, ready in
            if ready && minimumDurationComplete {
                finishWhenReady()
            }
        }
    }

    @MainActor
    private func finishWhenReady() {
        guard visible, minimumDurationComplete else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            visible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onFinished()
        }
    }
}
