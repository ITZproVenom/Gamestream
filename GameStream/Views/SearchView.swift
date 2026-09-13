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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Search")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Find your next game")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 12)

                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        TextField("Search games", text: $searchText)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .font(.system(size: 17, weight: .medium))

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                        .strokeBorder(
                            .white.opacity(searchFocused ? 0.3 : 0.12),
                            lineWidth: 1
                        )
                    }

                    if searchText.isEmpty {
                        VStack(spacing: 18) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 42, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))

                            VStack(spacing: 6) {
                                Text("What are you playing?")
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)

                                Text("Search for games available on Xbox Cloud Gaming.")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                    } else {
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
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 58)
                            .background(
                                .ultraThinMaterial,
                                in: RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                                .strokeBorder(
                                    .white.opacity(0.15),
                                    lineWidth: 1
                                )
                            }
                        }
                        .buttonStyle(.plain)

                        Text("Results")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(.top, 8)

                        Text("Search Xbox Cloud Gaming for \"\(searchText)\".")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func openXboxSearch() {
        guard let encoded = searchText.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else {
            return
        }

        guard let url = URL(
            string: "https://www.xbox.com/en-IN/play#search?query=\(encoded)"
        ) else {
            return
        }

        searchFocused = false

        NotificationCenter.default.post(
            name: .openXboxSearch,
            object: url
        )
    }
}

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
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
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
                            .background(
                                .ultraThinMaterial,
                                in: RoundedRectangle(
                                    cornerRadius: 18,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 18,
                                    style: .continuous
                                )
                                .strokeBorder(
                                    .white.opacity(0.1),
                                    lineWidth: 1
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct GlassRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.white)
                .font(.body.weight(.medium))

            Spacer()

            Text(value)
                .foregroundStyle(.white.opacity(0.5))
                .font(.subheadline)
        }
        .padding(16)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .strokeBorder(
                .white.opacity(0.1),
                lineWidth: 1
            )
        }
    }
}

extension Notification.Name {
    static let openXboxSearch = Notification.Name("openXboxSearch")
}