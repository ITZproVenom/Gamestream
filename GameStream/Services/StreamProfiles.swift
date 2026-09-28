import Foundation

/// Per-game stream settings, and the presets behind them.
///
/// A single set of stream settings is wrong the moment you play two
/// different kinds of game. A slow strategy game wants resolution held and
/// frame rate capped; a shooter wants the opposite and a tight deadzone.
/// Changing five sliders on every launch is not customisation, it is a
/// chore, so the settings travel with the game.
///
/// Anything not overridden falls through to the global settings, which means
/// a profile stores what you actually changed rather than a frozen copy of
/// everything.
struct StreamProfile: Codable, Equatable, Sendable {
    var maxBitrateMbps: Int?
    var resolution: String?
    var maxFps: Int?
    var preventResolutionDrops: Bool?
    var codecProfile: String?
    var sharpness: Int?
    var brightness: Int?
    var contrast: Int?
    var saturation: Int?
    var zoom: Int?
    var fillScreen: Bool?
    var aspectRatio: String?
    var volumeBoost: Int?
    var deadzone: Int?
    var triggerDeadzone: Int?
    var touchMode: String?

    var isEmpty: Bool { self == StreamProfile() }

    /// How many settings this profile actually pins, for the UI to show.
    var overrideCount: Int {
        var count = 0
        if maxBitrateMbps != nil { count += 1 }
        if resolution != nil { count += 1 }
        if maxFps != nil { count += 1 }
        if preventResolutionDrops != nil { count += 1 }
        if codecProfile != nil { count += 1 }
        if sharpness != nil { count += 1 }
        if brightness != nil { count += 1 }
        if contrast != nil { count += 1 }
        if saturation != nil { count += 1 }
        if zoom != nil { count += 1 }
        if fillScreen != nil { count += 1 }
        if aspectRatio != nil { count += 1 }
        if volumeBoost != nil { count += 1 }
        if deadzone != nil { count += 1 }
        if triggerDeadzone != nil { count += 1 }
        if touchMode != nil { count += 1 }
        return count
    }
}

/// The ready-made starting points.
enum StreamPreset: String, CaseIterable, Identifiable, Sendable {
    case batterySaver
    case balanced
    case sharpest
    case competitive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batterySaver: return "Battery saver"
        case .balanced: return "Balanced"
        case .sharpest: return "Sharpest"
        case .competitive: return "Competitive"
        }
    }

    var detail: String {
        switch self {
        case .batterySaver:
            return "720p at 30 fps and a 5 Mbps ceiling. The phone runs cool and the "
                + "battery lasts; the picture is visibly softer."
        case .balanced:
            return "Everything left to the server, with a light sharpen. The default."
        case .sharpest:
            return "1080p, high profile, no bitrate limit, resolution held and a firm "
                + "sharpen. Best on a good connection, worst on a poor one."
        case .competitive:
            return "Frame rate over fidelity: no cap, resolution allowed to drop, a "
                + "small stick deadzone and the pad read every frame."
        }
    }

    var icon: String {
        switch self {
        case .batterySaver: return "battery.50"
        case .balanced: return "dial.medium"
        case .sharpest: return "sparkles"
        case .competitive: return "bolt.fill"
        }
    }

    var profile: StreamProfile {
        switch self {
        case .batterySaver:
            return StreamProfile(maxBitrateMbps: 5, resolution: "720p", maxFps: 30,
                                 preventResolutionDrops: false, sharpness: 0)
        case .balanced:
            return StreamProfile(maxBitrateMbps: 0, resolution: "", maxFps: 0,
                                 preventResolutionDrops: false, codecProfile: "",
                                 sharpness: 1)
        case .sharpest:
            return StreamProfile(maxBitrateMbps: 0, resolution: "1080p", maxFps: 0,
                                 preventResolutionDrops: true, codecProfile: "high",
                                 sharpness: 3)
        case .competitive:
            return StreamProfile(maxBitrateMbps: 0, resolution: "", maxFps: 0,
                                 preventResolutionDrops: false, codecProfile: "high",
                                 sharpness: 2, deadzone: 8)
        }
    }
}

/// Stores the profiles and applies them.
@MainActor
final class StreamProfiles: ObservableObject {
    static let shared = StreamProfiles()

    @Published private(set) var profiles: [String: StreamProfile] = [:]

    private let key = "settings.streamProfiles"
    private let defaults = UserDefaults.standard

    private init() {
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([String: StreamProfile].self, from: data) {
            profiles = stored
        }
    }

    func profile(for gameID: String) -> StreamProfile? { profiles[gameID.lowercased()] }

    func has(_ gameID: String) -> Bool {
        guard let profile = profile(for: gameID) else { return false }
        return !profile.isEmpty
    }

    func save(_ profile: StreamProfile, for gameID: String) {
        if profile.isEmpty {
            profiles.removeValue(forKey: gameID.lowercased())
        } else {
            profiles[gameID.lowercased()] = profile
        }
        persist()
    }

    func clear(_ gameID: String) {
        profiles.removeValue(forKey: gameID.lowercased())
        persist()
    }

    /// Captures the settings as they stand now, so "save this as the profile
    /// for this game" means what it looks like it means.
    func capture() -> StreamProfile {
        let settings = AppSettings.shared
        return StreamProfile(
            maxBitrateMbps: settings.maxBitrateMbps,
            resolution: settings.resolutionPref,
            maxFps: settings.maxFps,
            preventResolutionDrops: settings.preventResolutionDrops,
            codecProfile: settings.codecProfile,
            sharpness: settings.sharpness,
            brightness: settings.brightness,
            contrast: settings.contrast,
            saturation: settings.saturation,
            zoom: settings.zoom,
            fillScreen: settings.fillScreen,
            aspectRatio: settings.aspectRatio,
            volumeBoost: settings.volumeBoost,
            deadzone: settings.deadzone,
            triggerDeadzone: settings.triggerDeadzone,
            touchMode: settings.touchMode
        )
    }

    /// Applies a profile over the live settings. Only what it pins changes.
    func apply(_ profile: StreamProfile) {
        let settings = AppSettings.shared
        if let value = profile.maxBitrateMbps { settings.maxBitrateMbps = value }
        if let value = profile.resolution { settings.resolutionPref = value }
        if let value = profile.maxFps { settings.maxFps = value }
        if let value = profile.preventResolutionDrops { settings.preventResolutionDrops = value }
        if let value = profile.codecProfile { settings.codecProfile = value }
        if let value = profile.sharpness { settings.sharpness = value }
        if let value = profile.brightness { settings.brightness = value }
        if let value = profile.contrast { settings.contrast = value }
        if let value = profile.saturation { settings.saturation = value }
        if let value = profile.zoom { settings.zoom = value }
        if let value = profile.fillScreen { settings.fillScreen = value }
        if let value = profile.aspectRatio { settings.aspectRatio = value }
        if let value = profile.volumeBoost { settings.volumeBoost = value }
        if let value = profile.deadzone { settings.deadzone = value }
        if let value = profile.triggerDeadzone { settings.triggerDeadzone = value }
        if let value = profile.touchMode { settings.touchMode = value }
    }

    /// Called as a game starts, before the page is built.
    func applyProfile(for gameID: String) {
        guard let profile = profile(for: gameID), !profile.isEmpty else { return }
        apply(profile)
        AppLog.shared.info("stream",
                           "applied the saved profile for \(gameID) "
                           + "(\(profile.overrideCount) settings)")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }
}
