import SwiftUI

/// GameStream's own in-stream menu.
///
/// This replaces the third-party dialog rather than dressing it up. That
/// dialog is a web page built for a mouse: its rail wants hover and focus,
/// its dropdowns want a pointer, and dismissing it leaves an overlay that
/// swallows touches. None of that is fixable from outside it.
///
/// So this is native. It reads and writes the app's own settings, applies
/// them to the running player immediately, and works the same whether the
/// picture comes from the web player or the native one.
struct StreamMenuView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stream: StreamCoordinator
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case picture = "Picture"
        case quality = "Quality"
        case audio = "Audio"
        case controller = "Controller"
        case network = "Network"
        case session = "Session"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .picture: return "slider.horizontal.below.rectangle"
            case .quality: return "antenna.radiowaves.left.and.right"
            case .audio: return "speaker.wave.2.fill"
            case .controller: return "gamecontroller.fill"
            case .network: return "network"
            case .session: return "clock.fill"
            }
        }
    }

    @State private var tab: Tab = .picture

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .picture: picture
                    case .quality: quality
                    case .audio: audio
                    case .controller: controllerTab
                    case .network: networkTab
                    case .session: sessionTab
                    }
                }
                .padding(18)
            }
        }
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("GameStream").font(.title3.weight(.semibold))
                    Text(stream.rendererDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .padding(9)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // A plain row of pills. Everything is one tap from here, which is
            // the point of replacing a rail built for a cursor.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Tab.allCases) { item in
                        Button {
                            withAnimation(.snappy) { tab = item }
                        } label: {
                            Label(item.rawValue, systemImage: item.icon)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(tab == item
                                            ? AnyShapeStyle(.tint)
                                            : AnyShapeStyle(.regularMaterial),
                                            in: Capsule())
                                .foregroundStyle(tab == item ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
    }

    // MARK: - Picture

    private var picture: some View {
        Group {
            slider("Sharpness", value: $settings.sharpness, range: 0...5, step: 1,
                   caption: settings.sharpness == 0 ? "Off" : "\(settings.sharpness)",
                   help: "A real sharpening kernel over the video. It cannot add detail "
                       + "the stream never sent, and pushed hard it makes compression "
                       + "blocks clearer, not softer.")
            slider("Brightness", value: $settings.brightness, range: 50...150, step: 5,
                   caption: "\(settings.brightness)%")
            slider("Contrast", value: $settings.contrast, range: 50...150, step: 5,
                   caption: "\(settings.contrast)%")
            slider("Saturation", value: $settings.saturation, range: 50...150, step: 5,
                   caption: "\(settings.saturation)%")
            slider("Zoom", value: $settings.zoom, range: 100...140, step: 2,
                   caption: settings.zoom == 100 ? "Fit" : "\(settings.zoom)%")

            Divider().opacity(0.3)

            Text("Shape").font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Aspect ratio", selection: $settings.aspectRatio) {
                Text("As sent").tag("")
                Text("16:9").tag("16:9")
                Text("16:10").tag("16:10")
                Text("18:9").tag("18:9")
                Text("21:9").tag("21:9")
                Text("4:3").tag("4:3")
            }
            .pickerStyle(.segmented)

            Picker("Position", selection: $settings.videoPosition) {
                Text("Top").tag("top")
                Text("Centre").tag("center")
                Text("Bottom").tag("bottom")
            }
            .pickerStyle(.segmented)
            caption("Where the picture sits when a forced shape leaves room around it.")

            Toggle("Fill the screen", isOn: $settings.fillScreen)
            caption("Crops the edges instead of letterboxing. On a phone that usually "
                    + "costs a sliver of the top and bottom.")

            Button("Reset the picture") {
                settings.sharpness = 0
                settings.brightness = 100
                settings.contrast = 100
                settings.saturation = 100
                settings.zoom = 100
                settings.fillScreen = false
            }
            .buttonStyle(.bordered)
        }
        .onChange(of: settings.sharpness) { _, _ in apply() }
        .onChange(of: settings.brightness) { _, _ in apply() }
        .onChange(of: settings.contrast) { _, _ in apply() }
        .onChange(of: settings.saturation) { _, _ in apply() }
        .onChange(of: settings.zoom) { _, _ in apply() }
        .onChange(of: settings.fillScreen) { _, _ in apply() }
        .onChange(of: settings.aspectRatio) { _, _ in apply() }
        .onChange(of: settings.videoPosition) { _, _ in apply() }
    }

    // MARK: - Quality

    private var quality: some View {
        Group {
            slider("Bitrate limit", value: $settings.maxBitrateMbps, range: 0...15, step: 1,
                   caption: settings.maxBitrateMbps == 0
                       ? "Unlimited" : "\(settings.maxBitrateMbps) Mbps",
                   help: "Unlimited is Xbox's own maximum of 15 Mbps. The limit is "
                       + "negotiated when a session starts, so it applies to the next "
                       + "game you launch.")

            Divider().opacity(0.3)
            Text("Codec").font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("H.264 profile", selection: $settings.codecProfile) {
                Text("Whatever is offered").tag("")
                Text("Baseline").tag("baseline")
                Text("Main").tag("main")
                Text("High").tag("high")
            }
            .pickerStyle(.segmented)
            caption("Higher profiles fit more detail into the same bitrate. The server "
                    + "decides whether it offers one, and the choice is made when a "
                    + "session starts.")

            Toggle("Request HDR (H.265)", isOn: $settings.preferHEVC)
            caption(hdrExplanation)

            Divider().opacity(0.3)

            Picker("Resolution", selection: $settings.resolutionPref) {
                Text("Server's choice").tag("")
                Text("720p").tag("720p")
                Text("1080p").tag("1080p")
            }
            .pickerStyle(.segmented)

            slider("Frame rate cap", value: $settings.maxFps, range: 0...60, step: 10,
                   caption: settings.maxFps == 0 ? "Uncapped" : "\(settings.maxFps) fps",
                   help: "A lower cap spends the same bitrate on fewer, better frames. "
                       + "The sender may ignore it.")

            Toggle("Hold the resolution", isOn: $settings.preventResolutionDrops)
            caption("Asks the encoder not to drop resolution when the connection dips. "
                    + "You get stutter instead of blur, which suits slower games and "
                    + "hurts fast ones.")

            Divider().opacity(0.3)

            Picker("Touch controls", selection: $settings.touchMode) {
                Text("Off").tag("off")
                Text("Supported games").tag("default")
                Text("All games").tag("all")
            }
            .pickerStyle(.segmented)

            if settings.touchMode != "off" {
                slider("Touch opacity", value: $settings.touchOpacity,
                       range: 20...100, step: 5, caption: "\(settings.touchOpacity)%")
            }

            Toggle("Hide the site's own overlays", isOn: $settings.hideSiteOverlays)

            if let stats = stream.stats {
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Now").font(.subheadline.weight(.semibold))
                    HStack(spacing: 20) {
                        metric("\(stats.fps)", "fps")
                        metric(String(format: "%.1f", Double(stats.bitrateKbps) / 1000), "Mbps")
                        metric("\(stats.rttMs)", "ms")
                        metric("\(stats.decodeMs)", "decode")
                    }
                    if !stats.codec.isEmpty {
                        Text("\(stats.codec) · \(stats.width)×\(stats.height)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: settings.touchMode) { _, _ in apply() }
        .onChange(of: settings.touchOpacity) { _, _ in apply() }
        .onChange(of: settings.hideSiteOverlays) { _, _ in apply() }
    }

    private func metric(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Audio

    private var audio: some View {
        Group {
            slider("Volume boost", value: $settings.volumeBoost, range: 100...300, step: 10,
                   caption: settings.volumeBoost == 100 ? "Normal" : "\(settings.volumeBoost)%",
                   help: "A stream's own volume cannot go above normal. This routes it "
                       + "through a gain stage that can. Past about 200% quiet games "
                       + "become usable and loud ones start to clip.")
        }
        .onChange(of: settings.volumeBoost) { _, _ in apply() }
    }

    // MARK: - Controller

    private var controllerTab: some View {
        Group {
            Toggle("Rumble", isOn: $settings.rumbleEnabled)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Rumble strength").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.1f×", settings.rumbleIntensity))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.rumbleIntensity, in: 0.5...2.5, step: 0.1)
            }
            Divider().opacity(0.3)

            slider("Stick deadzone", value: $settings.deadzone, range: 0...40, step: 1,
                   caption: settings.deadzone == 0 ? "Off" : "\(settings.deadzone)%",
                   help: "Ignores the first part of the stick's travel, then rescales "
                       + "the rest so there is no jump at the edge of the zone. "
                       + "Applied before the stream ever sees the stick.")

            slider("Trigger deadzone", value: $settings.triggerDeadzone,
                   range: 0...40, step: 1,
                   caption: settings.triggerDeadzone == 0
                       ? "Off" : "\(settings.triggerDeadzone)%")

            slider("Polling floor", value: $settings.pollingRate, range: 0...16, step: 2,
                   caption: settings.pollingRate == 0
                       ? "Every frame" : "\(settings.pollingRate) ms",
                   help: "How often the pad is actually read. Every frame is the most "
                       + "current; a floor trades a little latency for less work.")

            Divider().opacity(0.3)

            Toggle("Use the phone when the pad cannot rumble",
                   isOn: $settings.phoneRumbleFallback)
            caption("Some controllers advertise haptics they cannot actually play. This "
                    + "is the consolation prize, and it is the phone buzzing, not the pad.")
        }
        .onChange(of: settings.deadzone) { _, _ in apply() }
        .onChange(of: settings.pollingRate) { _, _ in apply() }
        .onChange(of: settings.triggerDeadzone) { _, _ in apply() }
    }

    // MARK: - Network

    private var networkTab: some View {
        Group {
            Toggle("Prefer IPv6", isOn: $settings.preferIPv6)
            caption("Puts IPv6 candidates first when negotiating. On a network with "
                    + "real IPv6 this often skips a layer of carrier NAT; where there "
                    + "is none, nothing changes.")

            Toggle("Block telemetry", isOn: $settings.blockTracking)
            caption("Drops requests to known analytics hosts. Matched on the host "
                    + "itself, never on a guess about what a URL is for, because "
                    + "keyword matching catches real API calls and breaks the player.")

            Toggle("Skip the launch animation", isOn: $settings.skipSplash)
            Toggle("Hide the loading artwork", isOn: $settings.hideLoadingArt)
            Toggle("Hide social panels", isOn: $settings.blockSocial)
            Toggle("Reduce animations", isOn: $settings.reduceAnimations)
            Toggle("Hide scrollbars", isOn: $settings.hideScrollbars)

            Divider().opacity(0.3)
            Text("Region").font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Region", selection: $settings.region) {
                ForEach(AppSettings.Region.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
        .onChange(of: settings.blockTracking) { _, _ in apply() }
        .onChange(of: settings.skipSplash) { _, _ in apply() }
        .onChange(of: settings.hideLoadingArt) { _, _ in apply() }
        .onChange(of: settings.blockSocial) { _, _ in apply() }
        .onChange(of: settings.reduceAnimations) { _, _ in apply() }
        .onChange(of: settings.hideScrollbars) { _, _ in apply() }
    }

    /// Said plainly, because a switch that quietly does nothing is worse
    /// than no switch at all.
    private var hdrExplanation: String {
        let offered = stream.offeredCodecs
        if offered.isEmpty {
            return "HDR needs H.265, and the service only sends it to clients it "
                + "offers it to. This asks. Start a game and the codecs the server "
                + "actually offered appear here."
        }
        if offered.localizedCaseInsensitiveContains("H265")
            || offered.localizedCaseInsensitiveContains("HEVC") {
            return "Server offered: \(offered). H.265 is available, so HDR is "
                + "genuinely possible on this connection."
        }
        return "Server offered: \(offered). No H.265, so this stream is SDR and "
            + "asking again will not change that. The toggle stays on for the next "
            + "session in case the server's answer changes."
    }

    // MARK: - Session

    private var sessionTab: some View {
        Group {
            Toggle("Keep the screen awake", isOn: $settings.keepAwake)
            Toggle("Reconnect automatically", isOn: $settings.autoReconnect)
            Toggle("Stop if the phone overheats", isOn: $settings.thermalGuard)
            Toggle("Warn on low battery", isOn: $settings.batteryGuard)
            Divider().opacity(0.3)
            Text("Statistics").font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Position", selection: $settings.statsPosition) {
                Text("Top").tag("top")
                Text("Bottom").tag("bottom")
            }
            .pickerStyle(.segmented)
            slider("Opacity", value: $settings.statsOpacity, range: 20...100, step: 5,
                   caption: "\(settings.statsOpacity)%")
            slider("Text size", value: $settings.statsTextSize, range: 70...150, step: 10,
                   caption: "\(settings.statsTextSize)%")

            Divider().opacity(0.3)
            slider("Session limit", value: $settings.sessionLimitMinutes,
                   range: 0...240, step: 15,
                   caption: settings.sessionLimitMinutes == 0
                       ? "Off" : "\(settings.sessionLimitMinutes) min")
        }
    }

    // MARK: - Pieces

    private func slider(_ title: String,
                        value: Binding<Int>,
                        range: ClosedRange<Int>,
                        step: Int,
                        caption text: String,
                        help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
            if let help { caption(help) }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func apply() { stream.applyEnhancements() }
}
