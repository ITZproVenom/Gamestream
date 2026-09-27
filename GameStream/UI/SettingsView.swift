import UIKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var auth: XboxAuth
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rumble: ControllerRumble

    @Binding var showingBrowser: Bool

    @State private var showingDiagnostics = false
    @State private var showingSignOut = false
    @State private var cacheSize = 0

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                appearanceSection
                streamingSection
                controllerSection
                librarySection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingDiagnostics) { DiagnosticsView() }
            .task { cacheSize = await PosterCache.shared.diskUsage() }
            .confirmationDialog("Sign out of Xbox?", isPresented: $showingSignOut,
                                titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the Microsoft session stored on this device.")
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Signed in as", value: auth.state.gamertag ?? "Xbox account")
            Button("Open xbox.com") { showingBrowser = true }
            Button("Sign out", role: .destructive) { showingSignOut = true }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.theme) {
                ForEach(AppSettings.Theme.allCases) { Text($0.title).tag($0) }
            }
            Picker("Accent", selection: $settings.accent) {
                ForEach(AppSettings.Accent.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show activity on Home", isOn: $settings.showActivity)
        }
    }

    private var streamingSection: some View {
        Section {
            // Bound straight to stored settings, so opening this screen cannot
            // re-apply a value and reload a running stream, as 1.x did.
            Picker("Quality", selection: $settings.quality) {
                ForEach(AppSettings.Quality.allCases) { Text($0.title).tag($0) }
            }
            Picker("Server region", selection: $settings.region) {
                ForEach(AppSettings.Region.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Start games automatically", isOn: $settings.autoStart)
            Toggle("Show stream statistics", isOn: $settings.showStreamStats)
            Toggle("Keep screen awake", isOn: $settings.keepAwake)
        } header: {
            Text("Streaming")
        } footer: {
            Text("Quality and region are applied the next time a game starts.")
        }
    }

    private var controllerSection: some View {
        Section {
            LabeledContent("Controller", value: rumble.controllerName ?? "Not connected")
            if rumble.controllerName != nil && !rumble.supportsHaptics {
                Text("This controller does not report haptics support, so rumble is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Rumble", isOn: $settings.rumbleEnabled)

            if settings.rumbleEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Strength")
                        Spacer()
                        Text(String(format: "%.1f×", settings.rumbleIntensity))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.rumbleIntensity, in: 0.5...3, step: 0.1)
                }

                HStack(spacing: 10) {
                    Button("Left") { rumble.testLeft() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Right") { rumble.testRight() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Both") { rumble.testBoth() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
        } header: {
            Text("Controller")
        } footer: {
            Text("Rumble follows the game's own vibration, and stops when the game stops sending it.")
        }
    }

    private var librarySection: some View {
        Section("Library") {
            LabeledContent("Games in catalog", value: "\(catalog.games.count)")
            LabeledContent("Favorites", value: "\(library.favorites.count)")
            LabeledContent("Recently played", value: "\(library.recents.count)")
            LabeledContent("Up next", value: "\(library.queue.count)")
            LabeledContent("Lists", value: "\(library.lists.count)")
            Button("Clear favorites", role: .destructive) { library.clearFavorites() }
            Button("Clear recently played", role: .destructive) { library.clearRecents() }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button("Refresh catalog") { Task { await catalog.refresh() } }
            Button("Update Better xCloud") {
                Task { await BetterXCloud.shared.refresh() }
            }
            LabeledContent("Artwork cache", value: Format.bytes(cacheSize))
            Button("Clear artwork cache", role: .destructive) {
                Task {
                    await PosterCache.shared.clear()
                    cacheSize = await PosterCache.shared.diskUsage()
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            Button("Diagnostics") { showingDiagnostics = true }
            LabeledContent("Version", value: AppInfo.versionLine)
            Link("Better xCloud by redphx",
                 destination: URL(string: "https://github.com/redphx/better-xcloud")!)
        } header: {
            Text("About")
        } footer: {
            Text("GameStream is an unofficial client for Xbox Cloud Gaming and is not "
                 + "affiliated with Microsoft.")
        }
    }
}

/// Everything needed to explain a failure without a debugger attached.
struct DiagnosticsView: View {
    @EnvironmentObject private var auth: XboxAuth
    @ObservedObject private var log = AppLog.shared
    @Environment(\.dismiss) private var dismiss

    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section("Xbox session") {
                    LabeledContent("Status", value: statusText)
                    if let gamertag = auth.state.gamertag {
                        LabeledContent("Gamertag", value: gamertag)
                    }
                    LabeledContent("Token found in",
                                   value: auth.tokenSource.isEmpty ? "—" : auth.tokenSource)
                    LabeledContent("Token expires",
                                   value: auth.tokenExpires.isEmpty ? "—" : auth.tokenExpires)
                    if let checked = auth.lastCheck {
                        LabeledContent("Last checked",
                                       value: checked.formatted(date: .omitted, time: .standard))
                    }
                    if let error = auth.lastError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    Button("Check again") {
                        Task { await auth.refresh(reason: "diagnostics") }
                    }
                }

                Section("Build") {
                    LabeledContent("Version", value: AppInfo.versionLine)
                    LabeledContent("System", value: AppInfo.deviceLine)
                    LabeledContent("Better xCloud",
                                   value: BetterXCloud.shared.cachedScript == nil
                                       ? "Not downloaded" : "Ready")
                }

                Section("Log") {
                    if log.entries.isEmpty {
                        Text("Nothing logged yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(log.entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(entry.category, systemImage: entry.level.symbol)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(colour(for: entry.level))
                                Text(entry.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = log.exportText()
                            copied = true
                        } label: {
                            Label("Copy log", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: log.exportText()) {
                            Label("Share log", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            log.clear()
                        } label: {
                            Label("Clear log", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Log copied", isPresented: $copied) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var statusText: String {
        switch auth.state {
        case .unknown: return "Not checked yet"
        case .signedOut: return "No cloud-gaming token"
        case .signedIn: return "Ready to stream"
        }
    }

    private func colour(for level: AppLog.Level) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
