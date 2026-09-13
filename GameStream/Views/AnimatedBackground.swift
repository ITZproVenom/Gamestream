import SwiftUI

struct AnimatedBackground: View {
    @State private var animate = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Color.black

                RadialGradient(
                    colors: [.purple.opacity(0.35), .clear],
                    center: .init(
                        x: 0.5 + 0.3 * sin(t * 0.15),
                        y: 0.4 + 0.3 * cos(t * 0.12)
                    ),
                    startRadius: 20,
                    endRadius: 400
                )

                RadialGradient(
                    colors: [.blue.opacity(0.3), .clear],
                    center: .init(
                        x: 0.5 + 0.35 * cos(t * 0.1),
                        y: 0.6 + 0.35 * sin(t * 0.13)
                    ),
                    startRadius: 20,
                    endRadius: 450
                )
            }
            .ignoresSafeArea()
        }
    }
}
