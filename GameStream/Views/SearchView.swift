import SwiftUI
import Foundation

struct SearchView: View {
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            AnimatedBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Search")
                            .font(.system(size: 34, weight: .bold, design: .rounded))

                        Text("Find your next game")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)

                    // Search field — real glass
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField("Search games", text: $searchText)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 17, weight: .medium))

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
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .glassEffect(
                        searchFocused ? .regular.interactive() : .regular,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )

                    // Content
                    if searchText.isEmpty {
                        emptyState
                    } else {
                        resultsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("What are you playing?")
                    .font(.title3.weight(.semibold))

                Text("Search for games available on Xbox Cloud Gaming.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                openXboxSearch()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                    Text("Search Xbox Cloud Gaming")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
            }
            .buttonStyle(.glass)

            Text("Results")
                .font(.title3.weight(.semibold))
                .padding(.top, 4)

            Text("Search Xbox Cloud Gaming for \"\(searchText)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func openXboxSearch() {
        guard let encoded = searchText.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else { return }

        guard let url = URL(
            string: "https://www.xbox.com/en-IN/play#search?query=\(encoded)"
        ) else { return }

        searchFocused = false

        NotificationCenter.default.post(
            name: .openXboxSearch,
            object: url
        )
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore

    @AppStorage("streamQuality")
    private var streamQuality = "Auto"

    @AppStorage("serverRegion")
    private var serverRegion = "Auto"

    var body: some View {
        ZStack {
            AnimatedBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .padding(.top, 12)

                    GlassRow(
                        title: "Account",
                        value: session.accountLabel ?? "Not signed in"
                    )

                    GlassRow(
                        title: "Stream quality",
                        value: streamQuality
                    )

                    GlassRow(
                        title: "Server region",
                        value: serverRegion
                    )

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

// MARK: - GlassRow (native)

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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension Notification.Name {
    static let openXboxSearch = Notification.Name("openXboxSearch")
}
