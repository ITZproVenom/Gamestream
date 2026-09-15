import SwiftUI

// Safe stand-ins for iOS 26 Liquid Glass so launch never depends on fragile system glass.

struct GSGlassButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(configuration.isPressed ? 0.7 : 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GSGlassContainer<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: spacing) {
            content()
        }
    }
}

extension View {
    /// Material glass that works on iOS 17+ and never crashes at launch.
    @ViewBuilder
    func gsGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 18, style: .continuous)) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func gsGlassInteractive(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    func gsGlassButton(prominent: Bool = false) -> some View {
        self.buttonStyle(GSGlassButtonStyle(prominent: prominent))
    }
}
