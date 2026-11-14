import SwiftUI

private struct GameStreamSessionActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var gameStreamSessionActive: Bool {
        get { self[GameStreamSessionActiveKey.self] }
        set { self[GameStreamSessionActiveKey.self] = newValue }
    }
}

/// The shared look of GameStream 2.0.
///
/// Everything visual lives here so a change of mind is one edit rather than
/// twenty. The app targets iOS 26, so Liquid Glass is used directly: glass is
/// applied to floating controls and cards that sit *over* content, and never
/// to a full-screen background, which is the fastest way to make a Liquid
/// Glass interface look muddy.
enum Theme {
    static let cardRadius: CGFloat = 22
    static let tileRadius: CGFloat = 18
    static let heroRadius: CGFloat = 28

    static let cardShape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    static let tileShape = RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
    static let heroShape = RoundedRectangle(cornerRadius: heroRadius, style: .continuous)

    /// Section spacing used by every scrolling screen.
    static let sectionSpacing: CGFloat = 30
    static let pageInset: CGFloat = 20
}

/// The animated backdrop every screen sits on.
///
/// A mesh gradient in the accent colour, slowly drifting. It gives the glass
/// something worth refracting — glass over a flat grey reads as grey.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.gameStreamSessionActive) private var gameStreamSessionActive
    @EnvironmentObject private var settings: AppSettings

    @State private var drift: CGFloat = 0

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            if !gameStreamSessionActive {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        .init(0, 0), .init(0.5 + 0.1 * Float(drift), 0), .init(1, 0),
                        .init(0, 0.5), .init(0.5, 0.5 + 0.08 * Float(drift)), .init(1, 0.5),
                        .init(0, 1), .init(0.5 - 0.1 * Float(drift), 1), .init(1, 1)
                    ],
                    colors: mesh
                )
                .ignoresSafeArea()
                .blur(radius: settings.glowIntensity.blur)
                .opacity(min(1, (scheme == .dark ? 0.85 : 0.55)
                             * settings.glowIntensity.opacity / AppSettings.GlowIntensity.balanced.opacity))
            }
        }
        .ignoresSafeArea()
        .onAppear { startDrift() }
        .onChange(of: settings.backgroundMotion) { _, _ in startDrift() }
        .onChange(of: reduceMotion) { _, _ in startDrift() }
        .onChange(of: gameStreamSessionActive) { _, _ in startDrift() }
    }

    private func startDrift() {
        guard !gameStreamSessionActive, !reduceMotion,
              settings.backgroundMotion.duration > 0 else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { drift = 0.5 }
            return
        }
        drift = 0.5
        withAnimation(.easeInOut(duration: settings.backgroundMotion.duration).repeatForever(autoreverses: true)) {
            drift = 1
        }
    }

    private var mesh: [Color] {
        let base = Color(uiColor: .systemBackground)
        let palette = settings.backdrop.previewColors(accent: settings.accent.color)
        let glow = palette[0]
        let secondary = palette[1]
        let deep = palette[2]
        return [
            deep, secondary.opacity(0.72), base,
            glow.opacity(0.38), base, deep.opacity(0.82),
            base, secondary.opacity(0.56), base
        ]
    }
}

/// Applies the user's card treatment consistently to reusable content surfaces.
struct CardSurfaceModifier<S: Shape>: ViewModifier {
    @EnvironmentObject private var settings: AppSettings
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        switch settings.cardSurface {
        case .glass:
            content.glassEffect(.regular, in: shape)
        case .tinted:
            content.glassEffect(.regular.tint(settings.accent.color.opacity(0.22)), in: shape)
        case .solid:
            content.background(Color(uiColor: .secondarySystemBackground), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

/// A raised surface for content that sits above the backdrop.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    var tinted = false
    @ViewBuilder var content: Content

    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        content
            .padding(padding)
            .modifier(CardSurfaceModifier(shape: Theme.cardShape))
    }
}

/// A circular glass control, used for every floating icon button.
struct GlassIconButton: View {
    let systemImage: String
    var label: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        // The two styles are spelled out rather than erased into one value:
        // button styles are not interchangeable values, and wrapping them
        // costs more than the duplication saves.
        Group {
            if prominent {
                Button(action: action) { icon }.buttonStyle(.glassProminent)
            } else {
                Button(action: action) { icon }.buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 34, height: 34)
    }
}

/// A small piece of labelled data: playtime, session count, resolution.
struct StatChip: View {
    let value: String
    let caption: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                // Two lines are always reserved, so a row of chips is the
                // same height whichever captions it holds - "Day streak" and
                // "Sessions logged" are not the same length, and the cards
                // were ending at different heights.
                .frame(height: 30, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modifier(CardSurfaceModifier(shape: Theme.tileShape))
    }
}

/// A selectable capsule, used for genres and library filters.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .modifier(CardSurfaceModifier(shape: Capsule()))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The title above every section, with an optional trailing action.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}
