import SwiftUI
import Combine

/// User preferences, stored once and published so the interface follows them.
///
/// 1.x read several of these straight out of `UserDefaults` inside a SwiftUI
/// `Binding`. Nothing told SwiftUI the value had changed, so toggles appeared
/// to snap back to their old position. Everything here is `@Published`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Theme: String, CaseIterable, Identifiable, Sendable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum Accent: String, CaseIterable, Identifiable, Sendable {
        case purple, blue, green, orange, pink
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var color: Color {
            switch self {
            case .purple: return .purple
            case .blue: return .blue
            case .green: return .green
            case .orange: return .orange
            case .pink: return .pink
            }
        }
    }

    enum Quality: String, CaseIterable, Identifiable, Sendable {
        case auto, p720, p1080, p1080hq

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: return "Auto"
            case .p720: return "720p"
            case .p1080: return "1080p"
            case .p1080hq: return "1080p High quality"
            }
        }

        /// The value Better xCloud expects for `stream.video.resolution`.
        var betterXCloudValue: String {
            switch self {
            case .auto: return "auto"
            case .p720: return "720p"
            case .p1080: return "1080p"
            case .p1080hq: return "1080p-hq"
            }
        }
    }

    enum Region: String, CaseIterable, Identifiable, Sendable {
        case auto, northAmerica, europe, asia, australia

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: return "Auto"
            case .northAmerica: return "North America"
            case .europe: return "Europe"
            case .asia: return "Asia"
            case .australia: return "Australia"
            }
        }

        var betterXCloudValue: String {
            switch self {
            case .auto: return ""
            case .northAmerica: return "us"
            case .europe: return "eu"
            case .asia: return "jp"
            case .australia: return "au"
            }
        }
    }

    private enum Key {
        static let theme = "settings.theme"
        static let accent = "settings.accent"
        static let keepAwake = "settings.keepAwake"
        static let showActivity = "settings.showActivity"
        static let quality = "settings.quality"
        static let region = "settings.region"
        static let rumbleEnabled = "settings.rumbleEnabled"
        static let rumbleIntensity = "settings.rumbleIntensity"
        static let autoStart = "settings.autoStart"
        static let showStats = "settings.showStats"
    }

    @Published var theme: Theme { didSet { store(theme.rawValue, Key.theme) } }
    @Published var accent: Accent { didSet { store(accent.rawValue, Key.accent) } }
    @Published var keepAwake: Bool { didSet { store(keepAwake, Key.keepAwake) } }
    @Published var showActivity: Bool { didSet { store(showActivity, Key.showActivity) } }
    @Published var quality: Quality { didSet { store(quality.rawValue, Key.quality) } }
    @Published var region: Region { didSet { store(region.rawValue, Key.region) } }
    @Published var rumbleEnabled: Bool { didSet { store(rumbleEnabled, Key.rumbleEnabled) } }
    @Published var rumbleIntensity: Float { didSet { store(Double(rumbleIntensity), Key.rumbleIntensity) } }
    @Published var autoStart: Bool { didSet { store(autoStart, Key.autoStart) } }
    @Published var showStreamStats: Bool { didSet { store(showStreamStats, Key.showStats) } }

    private let defaults = UserDefaults.standard

    private init() {
        let defaults = UserDefaults.standard
        theme = Theme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        accent = Accent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .purple
        keepAwake = defaults.object(forKey: Key.keepAwake) as? Bool ?? true
        showActivity = defaults.object(forKey: Key.showActivity) as? Bool ?? true
        quality = Quality(rawValue: defaults.string(forKey: Key.quality) ?? "") ?? .auto
        region = Region(rawValue: defaults.string(forKey: Key.region) ?? "") ?? .auto
        rumbleEnabled = defaults.object(forKey: Key.rumbleEnabled) as? Bool ?? true
        rumbleIntensity = Float(defaults.object(forKey: Key.rumbleIntensity) as? Double ?? 1.6)
        autoStart = defaults.object(forKey: Key.autoStart) as? Bool ?? true
        showStreamStats = defaults.object(forKey: Key.showStats) as? Bool ?? false
    }

    /// The preferences handed to Better xCloud before it boots.
    func betterXCloudPreferences() -> [String: String] {
        var values: [String: String] = [
            "stream.video.resolution": quality.betterXCloudValue,
            "controller.vibration": rumbleEnabled ? "true" : "false",
            "native-mfi-controller.vibration": rumbleEnabled ? "true" : "false",
            "deviceVibration.mode": rumbleEnabled ? "on" : "off",
            "deviceVibration.intensity": "100",
            "stream.stats.showWhenPlaying": showStreamStats ? "true" : "false"
        ]
        if !region.betterXCloudValue.isEmpty {
            values["server.region"] = region.betterXCloudValue
        }
        return values
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
