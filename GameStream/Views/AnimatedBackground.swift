import SwiftUI

struct AnimatedBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                // Deep base
                Color.black

                // Primary moving light (purple)
                RadialGradient(
                    colors: [
                        Color(red: 0.45, green: 0.15, blue: 0.85).opacity(0.55),
                        Color(red: 0.35, green: 0.10, blue: 0.70).opacity(0.25),
                        .clear
                    ],
                    center: UnitPoint(
                        x: 0.5 + 0.28 * sin(t * 0.13),
                        y: 0.35 + 0.25 * cos(t * 0.11)
                    ),
                    startRadius: 10,
                    endRadius: 420
                )

                // Secondary light (blue)
                RadialGradient(
                    colors: [
                        Color(red: 0.15, green: 0.35, blue: 0.95).opacity(0.45),
                        Color(red: 0.10, green: 0.25, blue: 0.80).opacity(0.20),
                        .clear
                    ],
                    center: UnitPoint(
                        x: 0.55 + 0.32 * cos(t * 0.09),
                        y: 0.65 + 0.28 * sin(t * 0.12)
                    ),
                    startRadius: 10,
                    endRadius: 480
                )

                // Accent glow (cyan / teal)
                RadialGradient(
                    colors: [
                        Color(red: 0.10, green: 0.75, blue: 0.85).opacity(0.22),
                        .clear
                    ],
                    center: UnitPoint(
                        x: 0.3 + 0.2 * sin(t * 0.08),
                        y: 0.75 + 0.15 * cos(t * 0.14)
                    ),
                    startRadius: 5,
                    endRadius: 280
                )

                // Subtle top vignette for depth
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.35),
                        .clear,
                        .clear,
                        Color.black.opacity(0.45)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
    }
}
