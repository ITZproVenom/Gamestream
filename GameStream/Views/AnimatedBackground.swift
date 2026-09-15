import SwiftUI

struct AnimatedBackground: View {
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        TimelineView(.animation) { timeline in
            let animate = appearance.backgroundStyle == .aurora && appearance.animationIntensity == .full && appearance.effectsMode != .performance
            let t = animate ? timeline.date.timeIntervalSinceReferenceDate : 0
            let accent = appearance.accent
            let light = appearance.mode == .light
            let glowScale: Double = appearance.effectsMode == .performance ? 0.35 : appearance.glassIntensity

            ZStack {
                (light ? Color(red: 0.93, green: 0.94, blue: 0.98) : Color.black)

                RadialGradient(
                    colors: [
                        accent.primaryGlow.opacity((light ? 0.28 : 0.55) * glowScale),
                        accent.primaryGlow.opacity((light ? 0.12 : 0.25) * glowScale),
                        .clear
                    ],
                    center: UnitPoint(
                        x: 0.5 + 0.28 * sin(t * 0.13),
                        y: 0.35 + 0.25 * cos(t * 0.11)
                    ),
                    startRadius: 10,
                    endRadius: 420
                )

                RadialGradient(
                    colors: [
                        accent.secondaryGlow.opacity(light ? 0.22 : 0.45),
                        accent.secondaryGlow.opacity(light ? 0.10 : 0.20),
                        .clear
                    ],
                    center: UnitPoint(
                        x: 0.55 + 0.32 * cos(t * 0.09),
                        y: 0.65 + 0.28 * sin(t * 0.12)
                    ),
                    startRadius: 10,
                    endRadius: 480
                )

                RadialGradient(
                    colors: [
                        accent.tint.opacity(light ? 0.16 : 0.22),
                        .clear
                    ],
                    center: UnitPoint(
                        x: 0.3 + 0.2 * sin(t * 0.08),
                        y: 0.75 + 0.15 * cos(t * 0.14)
                    ),
                    startRadius: 5,
                    endRadius: 280
                )

                LinearGradient(
                    colors: [
                        (light ? Color.white : Color.black).opacity(light ? 0.18 : 0.35),
                        .clear,
                        .clear,
                        (light ? Color.white : Color.black).opacity(light ? 0.22 : 0.45)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: appearance.accent)
            .animation(.easeInOut(duration: 0.35), value: appearance.mode)
        }
    }
}
