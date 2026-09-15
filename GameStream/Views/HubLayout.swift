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
                .padding(.bottom, 28)
                .frame(width: width, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(width: width, height: geo.size.height, alignment: .top)
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
        .clipped()
    }
}

enum HubMetrics {
    static func featuredCardWidth(containerWidth: CGFloat) -> CGFloat {
        let usable = max(containerWidth - 40, 220)
        return min(280, max(220, usable * 0.78))
    }

    static func posterWidth(containerWidth: CGFloat, compact: Bool = false) -> CGFloat {
        let usable = max(containerWidth - 40, 180)
        let factor: CGFloat = compact ? 0.30 : 0.34
        let cap: CGFloat = compact ? 118 : 132
        let floor: CGFloat = compact ? 96 : 104
        return min(cap, max(floor, usable * factor))
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
