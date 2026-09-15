import SwiftUI
import Combine

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

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
    case violet, azure, emerald, crimson, gold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .violet: return "Violet"
        case .azure: return "Azure"
        case .emerald: return "Emerald"
        case .crimson: return "Crimson"
        case .gold: return "Gold"
        }
    }

    var tint: Color {
        switch self {
        case .violet: return Color(red: 0.62, green: 0.38, blue: 1.0)
        case .azure: return Color(red: 0.28, green: 0.58, blue: 1.0)
        case .emerald: return Color(red: 0.18, green: 0.78, blue: 0.58)
        case .crimson: return Color(red: 0.95, green: 0.28, blue: 0.42)
        case .gold: return Color(red: 0.96, green: 0.74, blue: 0.28)
        }
    }

    var primaryGlow: Color {
        switch self {
        case .violet: return Color(red: 0.45, green: 0.15, blue: 0.85)
        case .azure: return Color(red: 0.15, green: 0.35, blue: 0.95)
        case .emerald: return Color(red: 0.08, green: 0.55, blue: 0.42)
        case .crimson: return Color(red: 0.72, green: 0.12, blue: 0.28)
        case .gold: return Color(red: 0.72, green: 0.48, blue: 0.08)
        }
    }

    var secondaryGlow: Color {
        switch self {
        case .violet: return Color(red: 0.15, green: 0.35, blue: 0.95)
        case .azure: return Color(red: 0.10, green: 0.75, blue: 0.85)
        case .emerald: return Color(red: 0.12, green: 0.38, blue: 0.78)
        case .crimson: return Color(red: 0.45, green: 0.10, blue: 0.55)
        case .gold: return Color(red: 0.85, green: 0.35, blue: 0.12)
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case aurora, still, solid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .still: return "Still"
        case .solid: return "Solid"
        }
    }
}

enum GameCardStyle: String, CaseIterable, Identifiable {
    case poster, compact
    var id: String { rawValue }
    var title: String {
        switch self {
        case .poster: return "Poster"
        case .compact: return "Compact"
        }
    }
}

enum LibraryDensity: String, CaseIterable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var title: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .compact: return "Compact"
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
    @Published var cardStyle: GameCardStyle { didSet { UserDefaults.standard.set(cardStyle.rawValue, forKey: Keys.card) } }
    @Published var density: LibraryDensity { didSet { UserDefaults.standard.set(density.rawValue, forKey: Keys.density) } }
    @Published var animationIntensity: AnimationIntensity { didSet { UserDefaults.standard.set(animationIntensity.rawValue, forKey: Keys.animation) } }
    @Published var effectsMode: EffectsMode { didSet { UserDefaults.standard.set(effectsMode.rawValue, forKey: Keys.effects) } }
    @Published var glassIntensity: Double { didSet { UserDefaults.standard.set(glassIntensity, forKey: Keys.glass) } }
    @Published var uiSoundsEnabled: Bool { didSet { UserDefaults.standard.set(uiSoundsEnabled, forKey: Keys.sounds) } }

    private enum Keys {
        static let mode = "GameStream.appearanceMode"
        static let accent = "GameStream.accentTheme"
        static let background = "GameStream.backgroundStyle"
        static let card = "GameStream.cardStyle"
        static let density = "GameStream.libraryDensity"
        static let animation = "GameStream.animationIntensity"
        static let effects = "GameStream.effectsMode"
        static let glass = "GameStream.glassIntensity"
        static let sounds = "GameStream.uiSoundsEnabled"
    }

    private init() {
        mode = AppAppearanceMode(rawValue: UserDefaults.standard.string(forKey: Keys.mode) ?? "") ?? .dark
        accent = AccentTheme(rawValue: UserDefaults.standard.string(forKey: Keys.accent) ?? "") ?? .violet
        backgroundStyle = BackgroundStyle(rawValue: UserDefaults.standard.string(forKey: Keys.background) ?? "") ?? .aurora
        cardStyle = GameCardStyle(rawValue: UserDefaults.standard.string(forKey: Keys.card) ?? "") ?? .poster
        density = LibraryDensity(rawValue: UserDefaults.standard.string(forKey: Keys.density) ?? "") ?? .comfortable
        animationIntensity = AnimationIntensity(rawValue: UserDefaults.standard.string(forKey: Keys.animation) ?? "") ?? .full
        effectsMode = EffectsMode(rawValue: UserDefaults.standard.string(forKey: Keys.effects) ?? "") ?? .quality
        let storedGlass = UserDefaults.standard.object(forKey: Keys.glass) as? Double
        glassIntensity = storedGlass ?? 1.0
        if UserDefaults.standard.object(forKey: Keys.sounds) == nil {
            uiSoundsEnabled = true
        } else {
            uiSoundsEnabled = UserDefaults.standard.bool(forKey: Keys.sounds)
        }
    }
}
