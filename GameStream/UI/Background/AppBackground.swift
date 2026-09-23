import SwiftUI

/// New app background driven by AppearanceStore (not the old AnimatedBackground type).
struct AppBackground: View {
    @ObservedObject private var appearance = AppearanceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animate: Bool {
        !reduceMotion
            && (appearance.backgroundStyle == .aurora || appearance.backgroundStyle == .mesh)
            && appearance.animationIntensity == .full
            && appearance.effectsMode != .performance
    }

    var body: some View {
        Group {
            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { context in
                    layers(t: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                layers(t: 0)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func layers(t: TimeInterval) -> some View {
        let accent = appearance.accent
        let light = appearance.mode == .light
        let glow = appearance.effectsMode == .performance ? 0.35 : appearance.glassIntensity
        let style = appearance.backgroundStyle

        ZStack {
            switch style {
            case .customColor:
                appearance.customBgColor.color
            case .customPhoto:
                Color.black
            case .midnight:
                Color(red: 0.02, green: 0.02, blue: 0.08)
            case .dusk:
                Color(red: 0.08, green: 0.04, blue: 0.12)
            case .solid:
                light ? Color(red: 0.93, green: 0.94, blue: 0.98) : Color.black
            default:
                light ? Color(red: 0.93, green: 0.94, blue: 0.98) : Color.black
            }

            if style == .customPhoto, let image = appearance.customBackgroundImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                Color.black.opacity(appearance.backgroundDim).ignoresSafeArea()
            }

            if style != .solid && style != .customColor && style != .customPhoto {
                RadialGradient(
                    colors: [
                        accent.primaryGlow.opacity((light ? 0.28 : 0.55) * glow),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5 + 0.28 * sin(t * 0.13), y: 0.35 + 0.25 * cos(t * 0.11)),
                    startRadius: 10,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [
                        accent.secondaryGlow.opacity(light ? 0.22 : 0.45),
                        .clear
                    ],
                    center: UnitPoint(x: 0.55 + 0.32 * cos(t * 0.09), y: 0.65 + 0.28 * sin(t * 0.12)),
                    startRadius: 10,
                    endRadius: 480
                )
            }
        }
    }
}
