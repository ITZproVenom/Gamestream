import SwiftUI

struct SearchView: View {
    @EnvironmentObject var session: SessionStore
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            AnimatedBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Search")
                            .font(.system(size: 34, weight: .bold, design: .rounded))

                        Text("Find your next game")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Search field
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField("Search games", text: $searchText)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 17, weight: .medium))
                            .submitLabel(.search)
                            .onSubmit {
                                performSearch()
                            }

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .glassEffect(
                        searchFocused ? .regular.interactive() : .regular,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                    // Content
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        emptyState
                    } else {
                        resultsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("What are you playing?")
                    .font(.title3.weight(.semibold))

                Text("Search for any game available on Xbox Cloud Gaming.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                performSearch()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                    Text("Search Xbox Cloud Gaming")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
            }
            .buttonStyle(.glassProminent)

            Text("Results")
                .font(.title3.weight(.semibold))
                .padding(.top, 6)

            Text("Tap above to search Xbox Cloud Gaming for \"\(searchText)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        searchFocused = false
        session.openSearch(query: query)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore

    @AppStorage("streamQuality") private var streamQuality = "Auto"
    @AppStorage("serverRegion") private var serverRegion = "Auto"

    private let qualityOptions = ["Auto", "1080p", "720p", "Performance"]
    private let regionOptions = ["Auto", "North America", "Europe", "Asia", "Australia"]

    var body: some View {
        ZStack {
            AnimatedBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .padding(.top, 8)

                    // Better xCloud status
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Better xCloud")
                                .font(.body.weight(.medium))
                            Text("Always active — all features enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .padding(16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Account
                    GlassRow(title: "Account", value: session.accountLabel ?? "Not signed in")

                    // Stream Quality
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stream quality")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(qualityOptions, id: \.self) { option in
                                    Button {
                                        streamQuality = option
                                    } label: {
                                        Text(option)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.glass)
                                    .opacity(streamQuality == option ? 1.0 : 0.55)
                                }
                            }
                        }
                    }

                    // Server Region
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server region")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(regionOptions, id: \.self) { option in
                                    Button {
                                        serverRegion = option
                                    } label: {
                                        Text(option)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.glass)
                                    .opacity(serverRegion == option ? 1.0 : 0.55)
                                }
                            }
                        }
                    }

                    if session.isSignedIn {
                        Button {
                            session.signOut()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                                Spacer()
                            }
                            .foregroundStyle(.red)
                            .padding(16)
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - GlassRow

struct GlassRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body.weight(.medium))

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
