import SwiftUI

/// Screen-adaptive metrics for poster grids and rails.
///
/// Baseline: **iPhone 13** — 390 × 844 pt, notch, home indicator.
/// Also covers 14/15/16 (390) and Plus/Max (~428–430) via container width.
enum LayoutMetrics {
    /// Horizontal page padding (comfortable on 390pt).
    static let pagePadding: CGFloat = 16

    /// Space under scroll content for floating glass tab bar + home indicator.
    /// iPhone 13 home indicator ~34pt; tab bar ~62pt + padding.
    static let tabBarClearance: CGFloat = 100

    static let gridSpacing: CGFloat = 12
    static let railSpacing: CGFloat = 12

    /// Title band: exactly 2 caption lines.
    static let titleBand: CGFloat = 36
    static let playBand: CGFloat = 34
    static let cardStackSpacing: CGFloat = 6

    /// Hero height for notch phones (iPhone 13 class).
    static func heroHeight(compact: Bool) -> CGFloat {
        compact ? 188 : 208
    }

    /// Two-column library / search cell width from full page width.
    static func gridPosterWidth(containerWidth: CGFloat) -> CGFloat {
        let usable = max(containerWidth - pagePadding * 2 - gridSpacing, 200)
        return floor(usable / 2)
    }

    /// Horizontal rail poster width.
    /// On 390pt: ~2.45 cards visible so titles stay readable.
    static func railPosterWidth(containerWidth: CGFloat) -> CGFloat {
        let usable = max(containerWidth - pagePadding * 2, 280)
        let target = usable / 2.45
        // Floor/cap tuned for iPhone 13 (390) through Max (430)
        return min(142, max(118, floor(target)))
    }

    static func artHeight(posterWidth: CGFloat) -> CGFloat {
        posterWidth * (4.0 / 3.0)
    }

    static func cardHeight(posterWidth: CGFloat) -> CGFloat {
        artHeight(posterWidth: posterWidth)
            + cardStackSpacing
            + titleBand
            + cardStackSpacing
            + playBand
    }
}
