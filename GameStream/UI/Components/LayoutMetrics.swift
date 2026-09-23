import SwiftUI

/// Screen-adaptive metrics for poster grids and rails.
/// Sized for modern Dynamic Island phones (390–430pt wide) and larger.
enum LayoutMetrics {
    /// Horizontal page padding.
    static let pagePadding: CGFloat = 20

    /// Space reserved under scroll content for the floating glass tab bar.
    static let tabBarClearance: CGFloat = 96

    static let gridSpacing: CGFloat = 12
    static let railSpacing: CGFloat = 12

    /// Title band: exactly 2 caption lines (no layout thrash between 1- and 2-line titles).
    static let titleBand: CGFloat = 36
    static let playBand: CGFloat = 34
    static let cardStackSpacing: CGFloat = 6

    /// Two-column library / search grid cell width.
    static func gridPosterWidth(containerWidth: CGFloat) -> CGFloat {
        let usable = max(containerWidth - pagePadding * 2 - gridSpacing, 200)
        return floor(usable / 2)
    }

    /// Horizontal rail poster width (~2.4–2.7 visible on phone).
    static func railPosterWidth(containerWidth: CGFloat) -> CGFloat {
        let usable = max(containerWidth - pagePadding * 2, 280)
        // Prefer ~2.5 cards on screen for 390–430pt devices
        let target = usable / 2.55
        return min(148, max(112, floor(target)))
    }

    /// Art height for a 3:4 poster at a given width.
    static func artHeight(posterWidth: CGFloat) -> CGFloat {
        posterWidth * (4.0 / 3.0)
    }

    /// Full card height: art + spacers + title + play.
    static func cardHeight(posterWidth: CGFloat) -> CGFloat {
        artHeight(posterWidth: posterWidth)
            + cardStackSpacing
            + titleBand
            + cardStackSpacing
            + playBand
    }
}
