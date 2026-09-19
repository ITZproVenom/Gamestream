import SwiftUI
import Combine
import UIKit

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum AccentTheme: String, CaseIterable, Identifiable {
    case violet, azure, emerald, crimson, gold, rose, cyan, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .violet: return "Violet"
        case .azure: return "Azure"
        case .emerald: return "Emerald"
        case .crimson: return "Crimson"
        case .gold: return "Gold"
        case .rose: return "Rose"
        case .cyan: return "Cyan"
        case .mono: return "Mono"
        }
    }
    var tint: Color {
        switch self {
        case .violet: return Color(red: 0.62, green: 0.38, blue: 1.0)
        case .azure: return Color(red: 0.28, green: 0.58, blue: 1.0)
        case .emerald: return Color(red: 0.18, green: 0.78, blue: 0.58)
        case .crimson: return Color(red: 0.95, green: 0.28, blue: 0.42)
        case .gold: return Color(red: 0.96, green: 0.74, blue: 0.28)
        case .rose: return Color(red: 0.95, green: 0.45, blue: 0.65)
        case .cyan: return Color(red: 0.20, green: 0.85, blue: 0.90)
        case .mono: return Color(red: 0.85, green: 0.85, blue: 0.90)
        }
    }
    var primaryGlow: Color {
        switch self {
        case .violet: return Color(red: 0.45, green: 0.15, blue: 0.85)
        case .azure: return Color(red: 0.15, green: 0.35, blue: 0.95)
        case .emerald: return Color(red: 0.08, green: 0.55, blue: 0.42)
        case .crimson: return Color(red: 0.72, green: 0.12, blue: 0.28)
        case .gold: return Color(red: 0.72, green: 0.48, blue: 0.08)
        case .rose: return Color(red: 0.70, green: 0.20, blue: 0.40)
        case .cyan: return Color(red: 0.08, green: 0.55, blue: 0.65)
        case .mono: return Color(red: 0.35, green: 0.35, blue: 0.42)
        }
    }
    var secondaryGlow: Color {
        switch self {
        case .violet: return Color(red: 0.15, green: 0.35, blue: 0.95)
        case .azure: return Color(red: 0.10, green: 0.75, blue: 0.85)
        case .emerald: return Color(red: 0.12, green: 0.38, blue: 0.78)
        case .crimson: return Color(red: 0.45, green: 0.10, blue: 0.55)
        case .gold: return Color(red: 0.85, green: 0.35, blue: 0.12)
        case .rose: return Color(red: 0.55, green: 0.15, blue: 0.55)
        case .cyan: return Color(red: 0.15, green: 0.35, blue: 0.90)
        case .mono: return Color(red: 0.55, green: 0.55, blue: 0.62)
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case aurora, still, solid, mesh, dusk, midnight, customColor, customPhoto
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .still: return "Still"
        case .solid: return "Solid"
        case .mesh: return "Mesh"
        case .dusk: return "Dusk"
        case .midnight: return "Midnight"
        case .customColor: return "Custom color"
        case .customPhoto: return "Custom photo"
        }
    }
}

enum CustomBgColor: String, CaseIterable, Identifiable {
    case deepBlack, charcoal, navy, forest, plum, wine, slate, pureWhite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .deepBlack: return "Deep black"
        case .charcoal: return "Charcoal"
        case .navy: return "Navy"
        case .forest: return "Forest"
        case .plum: return "Plum"
        case .wine: return "Wine"
        case .slate: return "Slate"
        case .pureWhite: return "White"
        }
    }
    var color: Color {
        switch self {
        case .deepBlack: return Color(red: 0.04, green: 0.04, blue: 0.06)
        case .charcoal: return Color(red: 0.12, green: 0.12, blue: 0.14)
        case .navy: return Color(red: 0.06, green: 0.10, blue: 0.22)
        case .forest: return Color(red: 0.05, green: 0.14, blue: 0.10)
        case .plum: return Color(red: 0.14, green: 0.06, blue: 0.18)
        case .wine: return Color(red: 0.18, green: 0.05, blue: 0.10)
        case .slate: return Color(red: 0.10, green: 0.12, blue: 0.16)
        case .pureWhite: return Color(red: 0.96, green: 0.96, blue: 0.98)
        }
    }
}

enum GameCardStyle: String, CaseIterable, Identifiable {
    case poster, wide, compact
    var id: String { rawValue }
    var title: String {
        switch self {
        case .poster: return "Poster"
        case .wide: return "Wide"
        case .compact: return "Compact"
        }
    }
}

enum LibraryDensity: String, CaseIterable, Identifiable {
    case spacious, comfortable, compact
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spacious: return "Spacious"
        case .comfortable: return "Comfortable"
        case .compact: return "Compact"
        }
    }
    var sectionSpacing: CGFloat {
        switch self {
        case .spacious: return 32
        case .comfortable: return 24
        case .compact: return 16
        }
    }
    var carouselSpacing: CGFloat {
        switch self {
        case .spacious: return 16
        case .comfortable: return 12
        case .compact: return 8
        }
    }
}

enum HubHomeLayout: String, CaseIterable, Identifiable {
    case editorial, rails, grid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .editorial: return "Editorial"
        case .rails: return "Rails"
        case .grid: return "Grid"
        }
    }
}

enum AnimationIntensity: String, CaseIterable, Identifiable {
    case full, reduced, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .full: return "Full"
        case .reduced: return "Reduced"
        case .off: return "Off"
        }
    }
}

enum EffectsMode: String, CaseIterable, Identifiable {
    case quality, balanced, performance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quality: return "Quality"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    @Published var mode: AppAppearanceMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) } }
    @Published var accent: AccentTheme { didSet { UserDefaults.standard.set(accent.rawValue, forKey: Keys.accent) } }
    @Published var backgroundStyle: BackgroundStyle { didSet { UserDefaults.standard.set(backgroundStyle.rawValue, forKey: Keys.background) } }
    @Published var customBgColor: CustomBgColor { didSet { UserDefaults.standard.set(customBgColor.rawValue, forKey: Keys.customBgColor) } }
    @Published var backgroundDim: Double { didSet { UserDefaults.standard.set(backgroundDim, forKey: Keys.bgDim) } }
    @Published var customBackgroundImage: UIImage? {
        didSet { persistCustomPhoto(customBackgroundImage) }
    }
    @Published var cardStyle: GameCardStyle { didSet { UserDefaults.standard.set(cardStyle.rawValue, forKey: Keys.card) } }
    @Published var density: LibraryDensity { didSet { UserDefaults.standard.set(density.rawValue, forKey: Keys.density) } }
    @Published var hubLayout: HubHomeLayout { didSet { UserDefaults.standard.set(hubLayout.rawValue, forKey: Keys.hubLayout) } }
    @Published var animationIntensity: AnimationIntensity { didSet { UserDefaults.standard.set(animationIntensity.rawValue, forKey: Keys.animation) } }
    @Published var effectsMode: EffectsMode { didSet { UserDefaults.standard.set(effectsMode.rawValue, forKey: Keys.effects) } }
    @Published var glassIntensity: Double { didSet { UserDefaults.standard.set(glassIntensity, forKey: Keys.glass) } }
    @Published var uiSoundsEnabled: Bool { didSet { UserDefaults.standard.set(uiSoundsEnabled, forKey: Keys.sounds) } }
    @Published var controllerHapticsEnabled: Bool { didSet { UserDefaults.standard.set(controllerHapticsEnabled, forKey: Keys.controllerHaptics) } }
    /// Multiplier for in-game / test rumble (0.5 weak … 3.0 max). Default 1.6 for wired pads.
    @Published var controllerRumbleIntensity: Double {
        didSet {
            let clamped = min(max(controllerRumbleIntensity, 0.5), 3.0)
            if clamped != controllerRumbleIntensity {
                controllerRumbleIntensity = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.rumbleIntensity)
        }
    }
    @Published var showActivityOnHome: Bool { didSet { UserDefaults.standard.set(showActivityOnHome, forKey: Keys.showActivity) } }
    @Published var showGenreFilters: Bool { didSet { UserDefaults.standard.set(showGenreFilters, forKey: Keys.showGenres) } }

    private enum Keys {
        static let mode = "GameStream.appearanceMode"
        static let accent = "GameStream.accentTheme"
        static let background = "GameStream.backgroundStyle"
        static let customBgColor = "GameStream.customBgColor"
        static let bgDim = "GameStream.backgroundDim"
        static let card = "GameStream.cardStyle"
        static let density = "GameStream.libraryDensity"
        static let hubLayout = "GameStream.hubHomeLayout"
        static let animation = "GameStream.animationIntensity"
        static let effects = "GameStream.effectsMode"
        static let glass = "GameStream.glassIntensity"
        static let sounds = "GameStream.uiSoundsEnabled"
        static let controllerHaptics = "GameStream.controllerHapticsEnabled"
        static let rumbleIntensity = "GameStream.controllerRumbleIntensity"
        static let showActivity = "GameStream.showActivityOnHome"
        static let showGenres = "GameStream.showGenreFilters"
    }

    private var photoURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom-background.jpg")
    }

    private init() {
        mode = AppAppearanceMode(rawValue: UserDefaults.standard.string(forKey: Keys.mode) ?? "") ?? .dark
        accent = AccentTheme(rawValue: UserDefaults.standard.string(forKey: Keys.accent) ?? "") ?? .violet
        backgroundStyle = BackgroundStyle(rawValue: UserDefaults.standard.string(forKey: Keys.background) ?? "") ?? .aurora
        customBgColor = CustomBgColor(rawValue: UserDefaults.standard.string(forKey: Keys.customBgColor) ?? "") ?? .deepBlack
        backgroundDim = (UserDefaults.standard.object(forKey: Keys.bgDim) as? Double) ?? 0.45
        cardStyle = GameCardStyle(rawValue: UserDefaults.standard.string(forKey: Keys.card) ?? "") ?? .poster
        density = LibraryDensity(rawValue: UserDefaults.standard.string(forKey: Keys.density) ?? "") ?? .comfortable
        hubLayout = HubHomeLayout(rawValue: UserDefaults.standard.string(forKey: Keys.hubLayout) ?? "") ?? .editorial
        animationIntensity = AnimationIntensity(rawValue: UserDefaults.standard.string(forKey: Keys.animation) ?? "") ?? .full
        effectsMode = EffectsMode(rawValue: UserDefaults.standard.string(forKey: Keys.effects) ?? "") ?? .quality
        glassIntensity = (UserDefaults.standard.object(forKey: Keys.glass) as? Double) ?? 1.0
        uiSoundsEnabled = UserDefaults.standard.object(forKey: Keys.sounds) == nil
            ? true : UserDefaults.standard.bool(forKey: Keys.sounds)
        controllerHapticsEnabled = UserDefaults.standard.object(forKey: Keys.controllerHaptics) == nil
            ? true : UserDefaults.standard.bool(forKey: Keys.controllerHaptics)
        let storedIntensity = UserDefaults.standard.object(forKey: Keys.rumbleIntensity) as? Double
        controllerRumbleIntensity = min(max(storedIntensity ?? 1.6, 0.5), 3.0)
        showActivityOnHome = UserDefaults.standard.object(forKey: Keys.showActivity) == nil
            ? true : UserDefaults.standard.bool(forKey: Keys.showActivity)
        showGenreFilters = UserDefaults.standard.object(forKey: Keys.showGenres) == nil
            ? true : UserDefaults.standard.bool(forKey: Keys.showGenres)
        if let data = try? Data(contentsOf: photoURL),
           let image = UIImage(data: data) {
            customBackgroundImage = image
        } else {
            customBackgroundImage = nil
        }
    }

    func setCustomPhoto(_ image: UIImage?) {
        customBackgroundImage = image
        if image != nil {
            backgroundStyle = .customPhoto
        }
    }

    func clearCustomPhoto() {
        customBackgroundImage = nil
        try? FileManager.default.removeItem(at: photoURL)
        if backgroundStyle == .customPhoto {
            backgroundStyle = .aurora
        }
    }

    private func persistCustomPhoto(_ image: UIImage?) {
        guard let image else {
            try? FileManager.default.removeItem(at: photoURL)
            return
        }
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: photoURL, options: .atomic)
        }
    }
}
