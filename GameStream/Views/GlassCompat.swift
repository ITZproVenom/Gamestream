import SwiftUI

// MARK: - Liquid Glass (iOS 26) — full native implementation
//
// System Liquid Glass only: glassEffect, GlassEffectContainer,
// .glass / .glassProminent. No material fallbacks.

extension View {
    /// Apply Liquid Glass in a shape (cards, docks, panels).
    func liquidGlass(
        in shape: some Shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    ) -> some View {
        self.glassEffect(.regular, in: shape)
    }

    /// Interactive Liquid Glass (chips, selected tab pill).
    func liquidGlassInteractive(
        in shape: some Shape = Capsule()
    ) -> some View {
        self.glassEffect(.regular.interactive(), in: shape)
    }
}

/// Groups morphing glass elements (tab bars, toolbars).
struct LiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}

struct LiquidGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct LiquidGlassActionButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    var prominent: Bool = true
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .modifier(LiquidGlassButtonModifier(prominent: prominent))
    }
}

private struct LiquidGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

struct LiquidGlassIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.glass)
    }
}
