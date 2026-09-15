import SwiftUI

/// Keeps vertical scroll content locked to the container width so nested
/// horizontal carousels cannot inflate the parent and clip off-screen.
struct HubPage<Content: View>: View {
    var horizontalPadding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(width: width, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(width: width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Horizontal carousel that reports only the container width to its parent.
struct HubCarousel<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum HubMetrics {
    static func featuredCardWidth(containerWidth: CGFloat) -> CGFloat {
        let usable = max(containerWidth - 40, 240)
        return min(300, max(240, usable * 0.82))
    }

    static func posterWidth(containerWidth: CGFloat) -> CGFloat {
        let usable = max(containerWidth - 40, 200)
        return min(140, max(108, usable * 0.36))
    }
}

struct HubSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
