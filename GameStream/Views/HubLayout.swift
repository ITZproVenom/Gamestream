import SwiftUI

private struct HubContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var hubContentWidth: CGFloat {
        get { self[HubContentWidthKey.self] }
        set { self[HubContentWidthKey.self] = newValue }
    }
}

struct HubPage<Content: View>: View {
    var horizontalPadding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let pageWidth = max(geo.size.width, 1)
            let contentWidth = max(pageWidth - (horizontalPadding * 2), 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content()
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(width: pageWidth, height: geo.size.height, alignment: .top)
            .environment(\.hubContentWidth, contentWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HubCarousel<Content: View>: View {
    var spacing: CGFloat = 12
    /// Explicit row height stops LazyHStack from collapsing into the section above.
    var rowHeight: CGFloat? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.hubContentWidth) private var hubWidth

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) {
                content()
            }
            .padding(.trailing, 8)
        }
        .frame(width: max(hubWidth, 1), alignment: .leading)
        .frame(height: rowHeight)
        .clipped()
    }
}

enum HubMetrics {
    static func featuredCardWidth(containerWidth: CGFloat) -> CGFloat {
        min(300, max(250, max(containerWidth, 240) * 0.86))
    }

    static func posterWidth(containerWidth: CGFloat, compact: Bool = false) -> CGFloat {
        let usable = max(containerWidth, 200)
        let factor: CGFloat = compact ? 0.40 : 0.43
        let cap: CGFloat = compact ? 128 : 146
        let floor: CGFloat = compact ? 110 : 124
        return min(cap, max(floor, usable * factor))
    }

    /// Art (3:4 of width) + title band + play + spacing.
    static func posterRowHeight(posterWidth: CGFloat) -> CGFloat {
        let art = posterWidth * (4.0 / 3.0)
        return art + GamePosterCard.titleBand + GamePosterCard.playBand + GamePosterCard.spacing * 2 + 4
    }
}

struct HubSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
