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

    private enum Key {
        static let theme = "settings.theme"
        static let accent = "settings.accent"
        static let keepAwake = "settings.keepAwake"
        static let rumbleEnabled = "settings.rumbleEnabled"
        static let rumbleIntensity = "settings.rumbleIntensity"
        static let autoStart = "settings.autoStart"
        static let showStats = "settings.showStats"
        static let phoneRumbleFallback = "settings.phoneRumbleFallback"
        static let autoReconnect = "settings.autoReconnect"
        static let sessionLimit = "settings.sessionLimitMinutes"
        static let thermalGuard = "settings.thermalGuard"
        static let batteryGuard = "settings.batteryGuard"
        static let adaptiveQuality = "settings.adaptiveQuality"
        static let preflightCheck = "settings.preflightCheck"
        static let maxBitrate = "settings.maxBitrateMbps"
        static let enhancer = "settings.enhancer"
        static let preferHEVC = "settings.preferHEVC"
        static let sharpness = "settings.sharpness"
        static let saturation = "settings.saturation"
        static let contrast = "settings.contrast"
        static let brightness = "settings.brightness"
        static let zoom = "settings.zoom"
        static let fillScreen = "settings.fillScreen"
        static let volumeBoost = "settings.volumeBoost"
        static let hideSiteOverlays = "settings.hideSiteOverlays"
        static let codecProfile = "settings.codecProfile"
        static let preferIPv6 = "settings.preferIPv6"
        static let blockTracking = "settings.blockTracking"
        static let skipSplash = "settings.skipSplash"
        static let deadzone = "settings.deadzone"
        static let triggerDeadzone = "settings.triggerDeadzone"
        static let aspectRatio = "settings.aspectRatio"
        static let videoPosition = "settings.videoPosition"
        static let maxFps = "settings.maxFps"
        static let resolutionPref = "settings.resolutionPref"
        static let preventResolutionDrops = "settings.preventResolutionDrops"
        static let touchMode = "settings.touchMode"
        static let touchOpacity = "settings.touchOpacity"
        static let blockSocial = "settings.blockSocial"
        static let reduceAnimations = "settings.reduceAnimations"
        static let hideScrollbars = "settings.hideScrollbars"
        static let hideLoadingArt = "settings.hideLoadingArt"
        static let pollingRate = "settings.pollingRate"
        static let statsPosition = "settings.statsPosition"
        static let statsOpacity = "settings.statsOpacity"
        static let statsTextSize = "settings.statsTextSize"
        static let recordingBitrate = "settings.recordingBitrate"
        static let recordMicrophone = "settings.recordMicrophone"
        static let recordingLimit = "settings.recordingLimit"
    }

    @Published var theme: Theme { didSet { store(theme.rawValue, Key.theme) } }
    @Published var accent: Accent { didSet { store(accent.rawValue, Key.accent) } }
    @Published var keepAwake: Bool { didSet { store(keepAwake, Key.keepAwake) } }
    @Published var rumbleEnabled: Bool {
        didSet {
            store(rumbleEnabled, Key.rumbleEnabled)
            ControllerRumble.shared.settingsChanged()
        }
    }
    @Published var rumbleIntensity: Float {
        didSet {
            store(Double(rumbleIntensity), Key.rumbleIntensity)
            ControllerRumble.shared.syncPage()
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

    /// GameStream's own in-page enhancement layer.
    @Published var enhancerEnabled: Bool { didSet { store(enhancerEnabled, Key.enhancer) } }
    /// Ask for H.265 when the server offers it. Whether it does is reported,
    /// never assumed.
    @Published var preferHEVC: Bool { didSet { store(preferHEVC, Key.preferHEVC) } }
    @Published var sharpness: Int { didSet { store(sharpness, Key.sharpness) } }
    @Published var saturation: Int { didSet { store(saturation, Key.saturation) } }
    @Published var contrast: Int { didSet { store(contrast, Key.contrast) } }
    @Published var brightness: Int { didSet { store(brightness, Key.brightness) } }
    @Published var zoom: Int { didSet { store(zoom, Key.zoom) } }
    @Published var fillScreen: Bool { didSet { store(fillScreen, Key.fillScreen) } }
    @Published var volumeBoost: Int { didSet { store(volumeBoost, Key.volumeBoost) } }
    @Published var hideSiteOverlays: Bool {
        didSet { store(hideSiteOverlays, Key.hideSiteOverlays) }
    }
    /// "", "baseline", "main" or "high". Higher profiles compress better at
    /// the same bitrate; the server decides whether it offers one.
    @Published var codecProfile: String { didSet { store(codecProfile, Key.codecProfile) } }
    @Published var preferIPv6: Bool { didSet { store(preferIPv6, Key.preferIPv6) } }
    @Published var blockTracking: Bool { didSet { store(blockTracking, Key.blockTracking) } }
    @Published var skipSplash: Bool { didSet { store(skipSplash, Key.skipSplash) } }
    @Published var deadzone: Int { didSet { store(deadzone, Key.deadzone) } }
    @Published var triggerDeadzone: Int {
        didSet { store(triggerDeadzone, Key.triggerDeadzone) }
    }
    @Published var aspectRatio: String { didSet { store(aspectRatio, Key.aspectRatio) } }
    @Published var videoPosition: String { didSet { store(videoPosition, Key.videoPosition) } }
    @Published var maxFps: Int { didSet { store(maxFps, Key.maxFps) } }
    @Published var resolutionPref: String {
        didSet { store(resolutionPref, Key.resolutionPref) }
    }
    @Published var preventResolutionDrops: Bool {
        didSet { store(preventResolutionDrops, Key.preventResolutionDrops) }
    }
    @Published var touchMode: String { didSet { store(touchMode, Key.touchMode) } }
    @Published var touchOpacity: Int { didSet { store(touchOpacity, Key.touchOpacity) } }
    @Published var blockSocial: Bool { didSet { store(blockSocial, Key.blockSocial) } }
    @Published var reduceAnimations: Bool {
        didSet { store(reduceAnimations, Key.reduceAnimations) }
    }
    @Published var hideScrollbars: Bool { didSet { store(hideScrollbars, Key.hideScrollbars) } }
    @Published var hideLoadingArt: Bool { didSet { store(hideLoadingArt, Key.hideLoadingArt) } }
    @Published var pollingRate: Int { didSet { store(pollingRate, Key.pollingRate) } }
    /// Where the app's own statistics sit and how loud they are.
    @Published var statsPosition: String { didSet { store(statsPosition, Key.statsPosition) } }
    @Published var statsOpacity: Int { didSet { store(statsOpacity, Key.statsOpacity) } }
    @Published var statsTextSize: Int { didSet { store(statsTextSize, Key.statsTextSize) } }
    /// Clip recording.
    @Published var recordingBitrateMbps: Int {
        didSet { store(recordingBitrateMbps, Key.recordingBitrate) }
    }
    @Published var recordMicrophone: Bool {
        didSet { store(recordMicrophone, Key.recordMicrophone) }
    }
    @Published var recordingLimitMinutes: Int {
        didSet { store(recordingLimitMinutes, Key.recordingLimit) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        let defaults = UserDefaults.standard
        theme = Theme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        accent = Accent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .purple
        keepAwake = defaults.object(forKey: Key.keepAwake) as? Bool ?? true
        rumbleEnabled = defaults.object(forKey: Key.rumbleEnabled) as? Bool ?? true
        rumbleIntensity = Float(defaults.object(forKey: Key.rumbleIntensity) as? Double ?? 1.6)
        autoStart = defaults.object(forKey: Key.autoStart) as? Bool ?? true
        showStreamStats = defaults.object(forKey: Key.showStats) as? Bool ?? false
        // On by default. A pad that reports haptics iOS cannot actually
        // drive is common enough that silence is the wrong default; the
        // phone buzzing at least tells the truth about what happened.
        phoneRumbleFallback = defaults.object(forKey: Key.phoneRumbleFallback) as? Bool ?? true
        autoReconnect = defaults.object(forKey: Key.autoReconnect) as? Bool ?? true
        sessionLimitMinutes = defaults.object(forKey: Key.sessionLimit) as? Int ?? 0
        thermalGuard = defaults.object(forKey: Key.thermalGuard) as? Bool ?? true
        batteryGuard = defaults.object(forKey: Key.batteryGuard) as? Bool ?? true
        adaptiveQuality = defaults.object(forKey: Key.adaptiveQuality) as? Bool ?? true
        preflightCheck = defaults.object(forKey: Key.preflightCheck) as? Bool ?? true
        maxBitrateMbps = defaults.object(forKey: Key.maxBitrate) as? Int ?? 0
        enhancerEnabled = defaults.object(forKey: Key.enhancer) as? Bool ?? true
        preferHEVC = defaults.object(forKey: Key.preferHEVC) as? Bool ?? false
        sharpness = defaults.object(forKey: Key.sharpness) as? Int ?? 0
        saturation = defaults.object(forKey: Key.saturation) as? Int ?? 100
        contrast = defaults.object(forKey: Key.contrast) as? Int ?? 100
        brightness = defaults.object(forKey: Key.brightness) as? Int ?? 100
        zoom = defaults.object(forKey: Key.zoom) as? Int ?? 100
        fillScreen = defaults.object(forKey: Key.fillScreen) as? Bool ?? false
        volumeBoost = defaults.object(forKey: Key.volumeBoost) as? Int ?? 100
        hideSiteOverlays = defaults.object(forKey: Key.hideSiteOverlays) as? Bool ?? true
        codecProfile = defaults.string(forKey: Key.codecProfile) ?? ""
        preferIPv6 = defaults.object(forKey: Key.preferIPv6) as? Bool ?? false
        blockTracking = defaults.object(forKey: Key.blockTracking) as? Bool ?? true
        skipSplash = defaults.object(forKey: Key.skipSplash) as? Bool ?? true
        deadzone = defaults.object(forKey: Key.deadzone) as? Int ?? 0
        triggerDeadzone = defaults.object(forKey: Key.triggerDeadzone) as? Int ?? 0
        aspectRatio = defaults.string(forKey: Key.aspectRatio) ?? ""
        videoPosition = defaults.string(forKey: Key.videoPosition) ?? "center"
        maxFps = defaults.object(forKey: Key.maxFps) as? Int ?? 0
        resolutionPref = defaults.string(forKey: Key.resolutionPref) ?? ""
        preventResolutionDrops = defaults.object(forKey: Key.preventResolutionDrops) as? Bool ?? false
        touchMode = defaults.string(forKey: Key.touchMode) ?? "off"
        touchOpacity = defaults.object(forKey: Key.touchOpacity) as? Int ?? 100
        blockSocial = defaults.object(forKey: Key.blockSocial) as? Bool ?? false
        reduceAnimations = defaults.object(forKey: Key.reduceAnimations) as? Bool ?? false
        hideScrollbars = defaults.object(forKey: Key.hideScrollbars) as? Bool ?? true
        hideLoadingArt = defaults.object(forKey: Key.hideLoadingArt) as? Bool ?? false
        pollingRate = defaults.object(forKey: Key.pollingRate) as? Int ?? 0
        statsPosition = defaults.string(forKey: Key.statsPosition) ?? "top"
        statsOpacity = defaults.object(forKey: Key.statsOpacity) as? Int ?? 90
        statsTextSize = defaults.object(forKey: Key.statsTextSize) as? Int ?? 100
        recordingBitrateMbps = defaults.object(forKey: Key.recordingBitrate) as? Int ?? 12
        recordMicrophone = defaults.object(forKey: Key.recordMicrophone) as? Bool ?? false
        recordingLimitMinutes = defaults.object(forKey: Key.recordingLimit) as? Int ?? 10
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    /// The configuration handed to GameStream's own enhancement layer.
    func enhancerConfiguration() -> StreamEnhancer.Configuration {
        StreamEnhancer.Configuration(
            enabled: enhancerEnabled,
            preferHEVC: preferHEVC,
            bitrateKbps: maxBitrateMbps > 0 ? maxBitrateMbps * 1000 : 0,
            sharpness: sharpness,
            saturation: saturation,
            contrast: contrast,
            brightness: brightness,
            zoom: zoom,
            fillScreen: fillScreen,
            volumeBoost: volumeBoost,
            hideTouchControls: touchMode == "off",
            hideSiteOverlays: hideSiteOverlays,
            codecProfile: codecProfile,
            preferIPv6: preferIPv6,
            blockTracking: blockTracking,
            skipSplash: skipSplash,
            deadzone: deadzone,
            triggerDeadzone: triggerDeadzone,
            vibrationScale: Int(rumbleIntensity * 100),
            aspectRatio: aspectRatio,
            videoPosition: videoPosition,
            maxFps: maxFps,
            resolution: resolutionPref,
            preventResolutionDrops: preventResolutionDrops,
            touchMode: touchMode,
            touchOpacity: touchOpacity,
            blockSocial: blockSocial,
            reduceAnimations: reduceAnimations,
            hideScrollbars: hideScrollbars,
            hideLoadingArt: hideLoadingArt,
            pollingRate: pollingRate
        )
    }
}
