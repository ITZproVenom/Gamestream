import SwiftUI

// MARK: - Shared Liquid Glass Primitives (iOS 26 native)

struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20

    init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct GlassActionButton: View {
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.glassProminent)
    }
}

struct GlassIconButton: View {
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

struct GlassSection<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 4)
            }
            content
        }
    }
}

// MARK: - Convenience helpers

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func interactiveGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 18, style: .continuous)) -> some View {
        self.glassEffect(.regular.interactive(), in: shape)
    }
}
