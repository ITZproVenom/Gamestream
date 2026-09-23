import SwiftUI

struct SettingsFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.largeTitle.weight(.bold))
                    .padding(.top, 8)

                section("Account") {
                    LabeledContent("Signed in as", value: session.accountLabel ?? "Xbox")
                    Button(role: .destructive) {
                        session.signOut()
                    } label: {
                        Text("Sign out")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                }

                section("Appearance") {
                    Picker("Theme", selection: $appearance.mode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker("Accent", selection: $appearance.accent) {
                        ForEach(AccentTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    Picker("Background", selection: $appearance.backgroundStyle) {
                        ForEach(BackgroundStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                }

                section("Stream") {
                    Toggle("Keep screen awake", isOn: $session.keepScreenAwake)
                    Button {
                        session.clearCache()
                    } label: {
                        Text("Clear image cache")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    Button(role: .destructive) {
                        session.clearWebData()
                    } label: {
                        Text("Clear web data & sign out")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                }

                Text("Auth and streaming use the locked Core WebViews.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
