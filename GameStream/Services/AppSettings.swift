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
        /// The same colour as CSS needs it, for styling the in-stream menus.
        /// Better xCloud reads its button colours from comma-separated RGB
        /// custom properties, not from hex.
        var rgbTriple: String {
            switch self {
            case .purple: return "175,82,222"
            case .blue: return "0,122,255"
            case .green: return "52,199,89"
            case .orange: return "255,149,0"
            case .pink: return "255,45,85"
            }
        }

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
        static let matchStreamStyle = "settings.matchStreamStyle"
        static let phoneRumbleFallback = "settings.phoneRumbleFallback"
        static let autoReconnect = "settings.autoReconnect"
        static let sessionLimit = "settings.sessionLimitMinutes"
        static let thermalGuard = "settings.thermalGuard"
        static let batteryGuard = "settings.batteryGuard"
        static let adaptiveQuality = "settings.adaptiveQuality"
        static let preflightCheck = "settings.preflightCheck"
        static let maxBitrate = "settings.maxBitrateMbps"
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
    /// Vibrate the phone when no controller route can rumble.
    @Published var phoneRumbleFallback: Bool {
        didSet {
            store(phoneRumbleFallback, Key.phoneRumbleFallback)
            ControllerRumble.shared.settingsChanged()
        }
    }
    /// Restyle the streaming enhancement's own web menus to match the app.
    @Published var matchStreamStyle: Bool { didSet { store(matchStreamStyle, Key.matchStreamStyle) } }
    /// Rejoin automatically when the stream drops rather than stranding the
    /// player on an error screen.
    @Published var autoReconnect: Bool { didSet { store(autoReconnect, Key.autoReconnect) } }
    /// Minutes before a session ends itself. Zero means no limit.
    @Published var sessionLimitMinutes: Int { didSet { store(sessionLimitMinutes, Key.sessionLimit) } }
    @Published var thermalGuard: Bool { didSet { store(thermalGuard, Key.thermalGuard) } }
    @Published var batteryGuard: Bool { didSet { store(batteryGuard, Key.batteryGuard) } }
    /// Drop the resolution by itself when the connection cannot hold it.
    @Published var adaptiveQuality: Bool { didSet { store(adaptiveQuality, Key.adaptiveQuality) } }
    /// Measure the connection before a game starts.
    @Published var preflightCheck: Bool { didSet { store(preflightCheck, Key.preflightCheck) } }
    /// Ceiling in megabits per second. Zero means no cap, which is Xbox's own
    /// maximum of 15 Mbps — there is nothing above that to ask for.
    @Published var maxBitrateMbps: Int { didSet { store(maxBitrateMbps, Key.maxBitrate) } }

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
        matchStreamStyle = defaults.object(forKey: Key.matchStreamStyle) as? Bool ?? true
        // Off by default. It is a consolation prize for hardware iOS cannot
        // drive, not something to hand to someone who plays on a pad.
        phoneRumbleFallback = defaults.object(forKey: Key.phoneRumbleFallback) as? Bool ?? false
        autoReconnect = defaults.object(forKey: Key.autoReconnect) as? Bool ?? true
        sessionLimitMinutes = defaults.object(forKey: Key.sessionLimit) as? Int ?? 0
        thermalGuard = defaults.object(forKey: Key.thermalGuard) as? Bool ?? true
        batteryGuard = defaults.object(forKey: Key.batteryGuard) as? Bool ?? true
        adaptiveQuality = defaults.object(forKey: Key.adaptiveQuality) as? Bool ?? true
        preflightCheck = defaults.object(forKey: Key.preflightCheck) as? Bool ?? true
        maxBitrateMbps = defaults.object(forKey: Key.maxBitrate) as? Int ?? 0
    }

    /// The preferences handed to Better xCloud before it boots.
    func betterXCloudPreferences() -> [String: String] {
        var values: [String: String] = [
            "stream.video.resolution": quality.betterXCloudValue,
            // GameStream owns rumble now. Its bridge reads the packets off the
            // data channel, applies the intensity setting and plays them, so
            // the enhancement's own handling is switched off: two owners
            // playing the same packets produces doubled effects.
            "controller.vibration": "false",
            "native-mfi-controller.vibration": "false",
            // Its phone-vibration path uses navigator.vibrate, which WebKit
            // does not implement; the native fallback covers that instead.
            "deviceVibration.mode": "off",
            // Always off: GameStream draws its own statistics panel from the
            // peer connection, and two overlays reporting the same numbers in
            // different styles is worse than one.
            "stream.stats.showWhenPlaying": "false"
        ]
        // Bits per second. Zero is the enhancement's "unlimited", which is
        // its maximum of 15 Mbps rather than genuinely uncapped: the server
        // decides the bitrate and Xbox does not send more than that.
        //
        // This is negotiated into the session description when the connection
        // is set up, so it can only ever apply to the next session.
        if maxBitrateMbps > 0 {
            values["stream.video.maxBitrate"] = String(maxBitrateMbps * 1_000_000)
        }
        if matchStreamStyle {
            // The dark base is the only one of its themes that a translucent
            // skin can sit on without fighting a light panel underneath.
            values["ui.theme"] = "dark-oled"
            values["ui.streamMenu.simplify"] = "true"
        }
        if !region.betterXCloudValue.isEmpty {
            values["server.region"] = region.betterXCloudValue
        }
        return values
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
