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

    /// What the site's on-screen controls should do.
    ///
    /// This replaced a single "hide the touch controls" switch, which could
    /// only ever take something away. Whether the overlay appears at all is
    /// decided by the session's input configuration, not by CSS, so the three
    /// states here are genuinely different things: hide what the site draws,
    /// leave the site's own judgement alone, or ask for touch input on every
    /// game.
    enum TouchControls: String, CaseIterable, Identifiable, Sendable {
        case hidden, whenOffered, everyGame

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hidden: return "Hidden"
            case .whenOffered: return "When offered"
            case .everyGame: return "Every game"
            }
        }

        /// Better xCloud's own touch controller setting, kept in step so the
        /// two cannot disagree inside the same stream.
        var betterXCloudValue: String {
            switch self {
            case .hidden: return "off"
            case .whenOffered: return "default"
            case .everyGame: return "all"
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
        static let recordingBitrate = "settings.recordingBitrate"
        static let recordMicrophone = "settings.recordMicrophone"
        static let recordingLimit = "settings.recordingLimit"
        static let enhancer = "settings.enhancer"
        static let preferHEVC = "settings.preferHEVC"
        static let sharpness = "settings.sharpness"
        static let saturation = "settings.saturation"
        static let contrast = "settings.contrast"
        static let hideTouchControls = "settings.hideTouchControls"
        static let touchControls = "settings.touchControls"
        static let cellularLimit = "settings.cellularLimit"
        static let cellularBitrate = "settings.cellularBitrateMbps"
        static let overlayButton = "settings.overlayButton"
    }

    @Published var theme: Theme { didSet { store(theme.rawValue, Key.theme) } }
    @Published var accent: Accent { didSet { store(accent.rawValue, Key.accent) } }
    @Published var keepAwake: Bool { didSet { store(keepAwake, Key.keepAwake) } }
    @Published var quality: Quality { didSet { store(quality.rawValue, Key.quality) } }
    @Published var region: Region { didSet { store(region.rawValue, Key.region) } }
    @Published var rumbleEnabled: Bool {
        didSet { store(rumbleEnabled, Key.rumbleEnabled); applyRumbleToLiveStream() }
    }
    @Published var rumbleIntensity: Float {
        didSet {
            store(Double(rumbleIntensity), Key.rumbleIntensity)
            applyRumbleToLiveStream()
        }
    }
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
    @Published var maxBitrateMbps: Int {
        didSet { store(maxBitrateMbps, Key.maxBitrate); applyToLiveStream() }
    }

    /// Clip recording.
    @Published var recordingBitrateMbps: Int {
        didSet { store(recordingBitrateMbps, Key.recordingBitrate) }
    }
    /// Off by default: a clip of a game should not record the room unless
    /// that was asked for.
    @Published var recordMicrophone: Bool {
        didSet { store(recordMicrophone, Key.recordMicrophone) }
    }
    /// A ceiling so a forgotten recording cannot fill the device.
    @Published var recordingLimitMinutes: Int {
        didSet { store(recordingLimitMinutes, Key.recordingLimit) }
    }

    /// GameStream's own in-page enhancement layer.
    @Published var enhancerEnabled: Bool {
        didSet { store(enhancerEnabled, Key.enhancer); applyToLiveStream() }
    }
    /// Ask for H.265 when the server offers it. Whether it does is reported,
    /// never assumed.
    @Published var preferHEVC: Bool {
        didSet { store(preferHEVC, Key.preferHEVC); applyToLiveStream() }
    }
    @Published var sharpness: Int {
        didSet { store(sharpness, Key.sharpness); applyToLiveStream() }
    }
    @Published var saturation: Int {
        didSet { store(saturation, Key.saturation); applyToLiveStream() }
    }
    @Published var contrast: Int {
        didSet { store(contrast, Key.contrast); applyToLiveStream() }
    }
    @Published var touchControls: TouchControls {
        didSet { store(touchControls.rawValue, Key.touchControls); applyToLiveStream() }
    }

    /// What the enhancement layer is told to hide. Derived so the CSS and the
    /// session configuration can never contradict each other.
    var hideTouchControls: Bool { touchControls == .hidden }

    /// Spend less on a cellular connection. The ceiling is negotiated when a
    /// session starts, so this applies to the next game rather than the one
    /// on screen.
    @Published var limitOnCellular: Bool {
        didSet { store(limitOnCellular, Key.cellularLimit) }
    }
    @Published var cellularBitrateMbps: Int {
        didSet { store(cellularBitrateMbps, Key.cellularBitrate) }
    }

    /// Open GameStream's overlay with the controller's View button, so the
    /// player does not have to find the screen to reach it.
    @Published var overlayButtonEnabled: Bool {
        didSet {
            store(overlayButtonEnabled, Key.overlayButton)
            ControllerShortcuts.shared.settingsChanged()
        }
    }

    private let defaults = UserDefaults.standard

    private init() {
        let defaults = UserDefaults.standard
        theme = Theme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        accent = Accent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .purple
        keepAwake = defaults.object(forKey: Key.keepAwake) as? Bool ?? true
        quality = Quality(rawValue: defaults.string(forKey: Key.quality) ?? "") ?? .auto
        region = Region(rawValue: defaults.string(forKey: Key.region) ?? "") ?? .auto
        rumbleEnabled = defaults.object(forKey: Key.rumbleEnabled) as? Bool ?? true
        rumbleIntensity = Float(defaults.object(forKey: Key.rumbleIntensity) as? Double ?? 1.6)
        autoStart = defaults.object(forKey: Key.autoStart) as? Bool ?? true
        showStreamStats = defaults.object(forKey: Key.showStats) as? Bool ?? false
        matchStreamStyle = defaults.object(forKey: Key.matchStreamStyle) as? Bool ?? true
        // Off by default. It is a consolation prize for hardware iOS cannot
        // drive, not something to hand to someone who plays on a pad.
        phoneRumbleFallback = defaults.object(forKey: Key.phoneRumbleFallback) as? Bool ?? true
        autoReconnect = defaults.object(forKey: Key.autoReconnect) as? Bool ?? true
        sessionLimitMinutes = defaults.object(forKey: Key.sessionLimit) as? Int ?? 0
        thermalGuard = defaults.object(forKey: Key.thermalGuard) as? Bool ?? true
        batteryGuard = defaults.object(forKey: Key.batteryGuard) as? Bool ?? true
        adaptiveQuality = defaults.object(forKey: Key.adaptiveQuality) as? Bool ?? true
        preflightCheck = defaults.object(forKey: Key.preflightCheck) as? Bool ?? true
        maxBitrateMbps = defaults.object(forKey: Key.maxBitrate) as? Int ?? 0
        recordingBitrateMbps = defaults.object(forKey: Key.recordingBitrate) as? Int ?? 12
        recordMicrophone = defaults.object(forKey: Key.recordMicrophone) as? Bool ?? false
        recordingLimitMinutes = defaults.object(forKey: Key.recordingLimit) as? Int ?? 10
        enhancerEnabled = defaults.object(forKey: Key.enhancer) as? Bool ?? true
        // On by default. The service offers H.265 and at the bitrate it
        // sends 1080p60 at, the same bandwidth spent on H.265 holds up far
        // better in motion than H.264 does. Both decode in hardware on this
        // device, so it costs nothing to ask.
        preferHEVC = defaults.object(forKey: Key.preferHEVC) as? Bool ?? true
        sharpness = defaults.object(forKey: Key.sharpness) as? Int ?? 0
        saturation = defaults.object(forKey: Key.saturation) as? Int ?? 100
        contrast = defaults.object(forKey: Key.contrast) as? Int ?? 100
        // Migrated from the old switch: someone who had chosen to hide the
        // site's controls keeps them hidden, and everyone else gets the
        // site's own judgement rather than a silent change of behaviour.
        if let stored = defaults.string(forKey: Key.touchControls),
           let mode = TouchControls(rawValue: stored) {
            touchControls = mode
        } else if let legacy = defaults.object(forKey: Key.hideTouchControls) as? Bool {
            touchControls = legacy ? .hidden : .whenOffered
        } else {
            touchControls = .hidden
        }
        limitOnCellular = defaults.object(forKey: Key.cellularLimit) as? Bool ?? true
        cellularBitrateMbps = defaults.object(forKey: Key.cellularBitrate) as? Int ?? 5
        overlayButtonEnabled = defaults.object(forKey: Key.overlayButton) as? Bool ?? false
    }

    /// The bitrate ceiling that applies to a session started right now.
    ///
    /// A cellular ceiling is not a second setting fighting the first: it is
    /// the lower of the two, so turning the limit on can only ever reduce
    /// what is asked for, never raise a cap the player set deliberately.
    var effectiveBitrateMbps: Int {
        guard limitOnCellular, Connectivity.shared.isMetered else { return maxBitrateMbps }
        if maxBitrateMbps == 0 { return cellularBitrateMbps }
        return min(maxBitrateMbps, cellularBitrateMbps)
    }

    /// The resolution that applies to a session started right now. A metered
    /// link gets 720p unless a lower resolution was already chosen.
    var effectiveQuality: Quality {
        guard limitOnCellular, Connectivity.shared.isMetered else { return quality }
        switch quality {
        case .auto, .p1080, .p1080hq: return .p720
        case .p720: return .p720
        }
    }

    /// Set when the ceiling in force is not the one the player chose, so the
    /// interface can say why rather than looking broken.
    var isLimitedByConnection: Bool {
        limitOnCellular && Connectivity.shared.isMetered
            && (effectiveBitrateMbps != maxBitrateMbps || effectiveQuality != quality)
    }

    /// The preferences handed to Better xCloud before it boots.
    ///
    /// The script keeps two stores, not one: global settings in
    /// `BetterXcloud` and per-stream settings in `BetterXcloud.Stream`. Every
    /// value below went into the global blob, so the stream-scoped ones were
    /// silently ignored and the script ran on its defaults — which is why its
    /// own statistics bar kept appearing over ours.
    func betterXCloudGlobalPreferences() -> [String: String] {
        var values: [String: String] = [
            "stream.video.resolution": effectiveQuality.betterXCloudValue,
            "touchController.mode": touchControls.betterXCloudValue
        ]
        // Bits per second. Zero is the script's "unlimited", which is its
        // maximum of 15 Mbps rather than genuinely uncapped: the server
        // decides the bitrate and Xbox does not send more than that.
        //
        // This is negotiated into the session description when the connection
        // is set up, so it can only ever apply to the next session.
        let ceiling = effectiveBitrateMbps
        if ceiling > 0 {
            values["stream.video.maxBitrate"] = String(ceiling * 1_000_000)
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

    /// Settings the script scopes to a stream.
    func betterXCloudStreamPreferences() -> [String: String] {
        [
            // Always off: GameStream draws its own statistics panel from the
            // peer connection, and two overlays reporting the same numbers in
            // different styles is worse than one.
            "stats.showWhenPlaying": "false",
            // Its phone-vibration path uses navigator.vibrate, which WebKit
            // does not implement; the native fallback covers that instead.
            "deviceVibration.mode": "off"
        ]
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    /// The configuration handed to GameStream's own enhancement layer.
    /// Pushes the picture settings into a stream that is already running.
    ///
    /// The page has always been able to accept a new configuration, and
    /// nothing ever sent it one, so moving a slider did nothing at all
    /// until the next launch. Rumble is carried the same way: it is read
    /// from two globals that were only ever written when the page loaded.
    private func applyToLiveStream() {
        let config = StreamEnhancer.json(enhancerConfiguration())
        XboxWebView.Registry.shared.run(
            "window.__gsEnhanceApply && window.__gsEnhanceApply(\(config));"
        )
    }

    private func applyRumbleToLiveStream() {
        XboxWebView.Registry.shared.run(
            "window.__gsRumbleMode = \"\(rumbleEnabled ? "page" : "off")\";"
            + "window.__gsRumbleScale = \(rumbleIntensity);"
        )
    }

    func enhancerConfiguration() -> StreamEnhancer.Configuration {
        StreamEnhancer.Configuration(
            enabled: enhancerEnabled,
            preferHEVC: preferHEVC,
            bitrateKbps: effectiveBitrateMbps > 0 ? effectiveBitrateMbps * 1000 : 0,
            sharpness: sharpness,
            saturation: saturation,
            contrast: contrast,
            hideTouchControls: hideTouchControls
        )
    }
}
