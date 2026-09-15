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
    case violet
    case azure
    case emerald
    case crimson
    case gold

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

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    @Published var mode: AppAppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }

    @Published var accent: AccentTheme {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Keys.accent) }
    }

    private enum Keys {
        static let mode = "GameStream.appearanceMode"
        static let accent = "GameStream.accentTheme"
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.mode),
           let stored = AppAppearanceMode(rawValue: raw) {
            mode = stored
        } else {
            mode = .dark
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.accent),
           let stored = AccentTheme(rawValue: raw) {
            accent = stored
        } else {
            accent = .violet
        }
    }
}
