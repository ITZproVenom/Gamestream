import SwiftUI

// MARK: - Liquid Glass (iOS 26) — full native implementation
//
// Uses system Liquid Glass only: glassEffect, GlassEffectContainer,
// .glass / .glassProminent button styles. No material fallbacks.

enum LiquidGlass {
    /// Standard floating glass for cards and panels.
    static var regular: Glass { .regular }

    /// Interactive glass that reacts to touch (tabs, chips, controls).
    static var interactive: Glass { .regular.interactive() }
}

extension View {
    /// Apply Liquid Glass in a shape (cards, docks, panels).
    func liquidGlass(
        _ glass: Glass = .regular,
        in shape: some Shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    ) -> some View {
        self.glassEffect(glass, in: shape)
    }

    /// Interactive Liquid Glass (buttons, selected tab pill, chips).
    func liquidGlassInteractive(
        in shape: some Shape = Capsule()
    ) -> some View {
        self.glassEffect(.regular.interactive(), in: shape)
    }

    /// Clear / subtle glass for overlays that should stay airy.
    func liquidGlassClear(
        in shape: some Shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    ) -> some View {
        self.glassEffect(.clear, in: shape)
    }
}

/// Groups morphing glass elements so the system can blend them (tab bars, toolbars).
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
        .buttonStyle(prominent ? .glassProminent : .glass)
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
